module Ledger
  # Reserves money on one account: the hold raises held_minor, so available
  # (posted - held) drops while posted is unchanged.
  #
  # Idempotent like PostTransaction. The request hash reuses RequestHash with
  # operation "place_hold" and a single debit leg for the held account:
  #   RequestHash.call(operation: "place_hold",
  #                    entries: [{ account_code:, direction: "debit", amount_minor: }],
  #                    effective_at: nil, metadata: {})
  class PlaceHold
    def self.call(...)
      new(...).call
    end

    def initialize(key:, account_code:, amount_minor:)
      @key = key
      @account_code = account_code
      @amount_minor = amount_minor
    end

    def call
      raise InvalidRequest, "amount_minor must be a positive Integer" unless @amount_minor.is_a?(Integer) && @amount_minor.positive?
      if (existing = Hold.find_by(idempotency_key: @key))
        return replay(existing)
      end

      owns_transaction = !ApplicationRecord.connection.transaction_open?
      place_new
    rescue ActiveRecord::RecordNotUnique
      raise unless owns_transaction

      existing = Hold.find_by(idempotency_key: @key)
      raise unless existing

      replay(existing)
    end

    private

    def replay(existing)
      raise ConflictError, "idempotency key #{@key.inspect} was already used for a different hold" unless existing.request_hash == request_hash

      existing.reload
    end

    def place_new
      account = Account.find_by(code: @account_code)
      raise NotFound, "unknown account #{@account_code.inspect}" unless account

      replayed = nil
      placed = ApplicationRecord.transaction do
        balance = AccountBalance.lock("FOR UPDATE").find(account.id)
        # A duplicate that waited on the lock may now see the winner's commit;
        # replay it before the (now reduced) available can reject the request.
        # Uncached: the pre-check above may have cached a nil for this query.
        replayed = Hold.uncached { Hold.find_by(idempotency_key: @key) }
        next if replayed

        check_available!(account, balance)
        hold = Hold.create!(account: account, amount_minor: @amount_minor, idempotency_key: @key, request_hash: request_hash)
        balance.held_minor += @amount_minor
        balance.version += 1
        balance.save!
        hold
      end
      replayed ? replay(replayed) : placed
    end

    def check_available!(account, balance)
      return if account.allow_negative

      posted = Balance.posted_minor(normal_side: account.normal_side, debits_minor: balance.debits_minor, credits_minor: balance.credits_minor)
      raise InsufficientFunds, "#{account.code} has less than #{@amount_minor} available" if posted - balance.held_minor < @amount_minor
    end

    def request_hash
      @request_hash ||= RequestHash.call(
        operation: "place_hold",
        entries: [ { account_code: @account_code, direction: "debit", amount_minor: @amount_minor } ],
        effective_at: nil,
        metadata: {}
      )
    end
  end
end
