module Ledger
  # Posts an active hold through PostTransaction: the whole hold is released
  # from held_minor and `amount_minor` (at most the held amount) moves from the
  # held account to the counter account. Any uncaptured remainder is freed.
  class CaptureHold
    def self.call(...)
      new(...).call
    end

    def initialize(hold_id:, key:, counter_account_code:, amount_minor:)
      @hold_id = hold_id
      @key = key
      @counter_account_code = counter_account_code
      @amount_minor = amount_minor
    end

    def call
      ApplicationRecord.transaction do
        hold = Hold.includes(:account).find_by(id: @hold_id)
        raise NotFound, "unknown hold #{@hold_id.inspect}" unless hold

        @hold = hold
        if (existing = LedgerTransaction.find_by(idempotency_key: @key))
          next replay(existing)
        end

        # Lock order: hold row first; PostTransaction then locks balance rows
        # in ascending account_id.
        hold.lock!("FOR UPDATE")
        # A duplicate that waited on the hold lock may now see the winner's
        # capture; replay it instead of reporting the hold as captured.
        if (existing = LedgerTransaction.uncached { LedgerTransaction.find_by(idempotency_key: @key) })
          next replay(existing)
        end
        raise InvalidState, "hold #{hold.id} is #{hold.status}, cannot capture" unless hold.status == "active"
        raise InvalidRequest, "counter account must differ from the held account" if @counter_account_code == hold.account.code
        raise InvalidRequest, "amount_minor must be an Integer in 1..#{hold.amount_minor}" unless @amount_minor.is_a?(Integer) && @amount_minor.between?(1, hold.amount_minor)

        txn = PostTransaction.call(
          key: @key,
          entries: entries,
          operation: "capture",
          metadata: metadata,
          release_held: { hold.account_id => hold.amount_minor }
        )
        hold.update!(status: "captured", ledger_transaction: txn)
        hold
      end
    end

    private

    # The key is taken: only a repeat of this hold's own capture replays. The
    # hash covers operation "capture" and metadata {"hold_id" => id}, so it
    # cannot match another hold's capture or a plain posting. It is compared
    # instead of @hold.ledger_transaction_id, which may be a stale read taken
    # before the original capture committed.
    def replay(existing)
      raise ConflictError, "idempotency key #{@key.inspect} was already used for a different request" unless existing.request_hash == request_hash

      @hold.reload
    end

    # The held account is moved against its normal side (credit for a
    # debit-normal account, debit for a credit-normal one); the counter
    # account takes the opposite side.
    def entries
      held_side = @hold.account.normal_side == "debit" ? "credit" : "debit"
      counter_side = held_side == "debit" ? "credit" : "debit"
      [
        { account_code: @hold.account.code, direction: held_side, amount_minor: @amount_minor },
        { account_code: @counter_account_code, direction: counter_side, amount_minor: @amount_minor }
      ]
    end

    def metadata
      { "hold_id" => @hold.id }
    end

    def request_hash
      RequestHash.call(operation: "capture", entries: entries, effective_at: nil, metadata: metadata)
    end
  end
end
