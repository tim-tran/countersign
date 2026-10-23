module Ledger
  # Posts one balanced, multi-entry transaction and updates the touched
  # balance rows in the same database transaction.
  class PostTransaction
    DIRECTIONS = %w[debit credit].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(key:, entries:, effective_at: nil, metadata: {}, operation: "post", reverses_id: nil, release_held: {})
      @key = key
      @entries = entries
      @effective_at = effective_at
      @metadata = metadata
      @operation = operation
      @reverses_id = reverses_id
      @release_held = release_held
    end

    def call
      validate_shape!
      if (existing = LedgerTransaction.find_by(idempotency_key: @key))
        return replay(existing)
      end

      owns_transaction = !ApplicationRecord.connection.transaction_open?
      post_new
    rescue ActiveRecord::RecordNotUnique
      raise unless owns_transaction

      existing = LedgerTransaction.find_by(idempotency_key: @key)
      raise unless existing

      replay(existing)
    end

    private

    # Same key and same canonical request returns the stored transaction;
    # the same key with a different request is a client error.
    def replay(existing)
      raise ConflictError, "idempotency key #{@key.inspect} was already used for a different request" unless existing.request_hash == request_hash

      existing.reload
    end

    def post_new
      load_accounts!
      check_currencies!
      check_balanced!

      replayed = nil
      posted = ApplicationRecord.transaction do
        balances = lock_balances
        # A duplicate that waited on the lock may now see the winner's commit;
        # replay it before the (now drained) balances can reject the request.
        # Uncached: the pre-check above may have cached a nil for this query.
        replayed = LedgerTransaction.uncached { LedgerTransaction.find_by(idempotency_key: @key) }
        next if replayed

        ensure_not_already_reversed!

        @release_held.each { |account_id, amount| balances.fetch(account_id).held_minor -= amount }
        apply_deltas(balances)
        check_available!(balances)

        txn = LedgerTransaction.create!(
          idempotency_key: @key,
          request_hash: request_hash,
          effective_at: @effective_at || Time.current,
          metadata: @metadata,
          reverses_id: @reverses_id
        )
        @entries.each do |e|
          account = @accounts.fetch(e[:account_code])
          txn.entries.create!(account: account, direction: e[:direction], amount_minor: e[:amount_minor], currency: account.currency)
        end
        balances.each_value do |row|
          row.version += 1
          row.save!
        end
        txn
      end
      replayed ? replay(replayed) : posted
    end

    # Runs under the balance locks, so concurrent reversals of one transaction
    # (which touch the same accounts) serialize here and the loser gets a
    # clear InvalidState before the funds check can mask it. The unique index
    # on reverses_id remains the backstop.
    def ensure_not_already_reversed!
      return unless @reverses_id
      return unless LedgerTransaction.uncached { LedgerTransaction.exists?(reverses_id: @reverses_id) }

      raise InvalidState, "transaction #{@reverses_id} has already been reversed"
    end

    # Locks every touched balance row in ascending account_id order so that
    # concurrent posts serialize per account and cannot deadlock each other.
    def lock_balances
      ids = (@accounts.values.map(&:id) + @release_held.keys).uniq
      AccountBalance.where(account_id: ids).order(:account_id).lock("FOR UPDATE").index_by(&:account_id)
    end

    def validate_shape!
      raise InvalidRequest, "a transaction needs at least two entries" unless @entries.is_a?(Array) && @entries.size >= 2

      @entries.each do |e|
        raise InvalidRequest, "entry must be a hash" unless e.is_a?(Hash)
        raise InvalidRequest, "unknown direction #{e[:direction].inspect}" unless DIRECTIONS.include?(e[:direction])

        amount = e[:amount_minor]
        raise InvalidRequest, "amount_minor must be a positive Integer" unless amount.is_a?(Integer) && amount.positive?
      end
    end

    def load_accounts!
      codes = @entries.map { |e| e[:account_code] }.uniq
      @accounts = Account.where(code: codes).index_by(&:code)
      missing = codes - @accounts.keys
      raise NotFound, "unknown account #{missing.first.inspect}" if missing.any?
    end

    def check_currencies!
      @entries.each do |e|
        next unless e.key?(:currency) && !e[:currency].nil?

        account = @accounts.fetch(e[:account_code])
        raise CurrencyMismatch, "#{account.code} is #{account.currency}, entry says #{e[:currency]}" if e[:currency] != account.currency
      end
    end

    def check_balanced!
      totals = Hash.new(0)
      @entries.each do |e|
        sign = e[:direction] == "debit" ? 1 : -1
        totals[@accounts.fetch(e[:account_code]).currency] += sign * e[:amount_minor]
      end
      unbalanced = totals.select { |_, net| net != 0 }
      raise Unbalanced, "entries do not balance in #{unbalanced.keys.join(', ')}" if unbalanced.any?
    end

    def apply_deltas(balances)
      @entries.each do |e|
        row = balances.fetch(@accounts.fetch(e[:account_code]).id)
        if e[:direction] == "debit"
          row.debits_minor += e[:amount_minor]
        else
          row.credits_minor += e[:amount_minor]
        end
      end
    end

    def check_available!(balances)
      @accounts.each_value do |account|
        next if account.allow_negative

        row = balances.fetch(account.id)
        posted = Balance.posted_minor(normal_side: account.normal_side, debits_minor: row.debits_minor, credits_minor: row.credits_minor)
        raise InsufficientFunds, "#{account.code} would go below zero available" if posted - row.held_minor < 0
      end
    end

    def request_hash
      RequestHash.call(operation: @operation, entries: @entries, effective_at: @effective_at, metadata: @metadata)
    end
  end
end
