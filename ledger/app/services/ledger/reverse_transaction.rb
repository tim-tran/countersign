module Ledger
  # Corrects a mistake with a new mirror-image transaction. A transaction can
  # be reversed at most once and a reversal is never itself reversed; the
  # unique index on ledger_transactions.reverses_id settles races.
  class ReverseTransaction
    REVERSES_INDEX = "index_ledger_transactions_on_reverses_id".freeze
    FLIP = { "debit" => "credit", "credit" => "debit" }.freeze

    def self.call(...)
      new(...).call
    end

    def initialize(transaction_id:, key:)
      @transaction_id = transaction_id
      @key = key
    end

    def call
      original = LedgerTransaction.find_by(id: @transaction_id)
      raise NotFound, "transaction #{@transaction_id.inspect} not found" unless original
      raise InvalidState, "a reversal cannot be reversed; re-post instead" if original.reverses_id.present?

      PostTransaction.call(
        key: @key,
        entries: flipped_entries(original),
        operation: "reverse",
        reverses_id: original.id,
        metadata: { "reverses_id" => original.id }
      )
    rescue ActiveRecord::RecordNotUnique => e
      raise unless e.message.include?(REVERSES_INDEX)

      raise InvalidState, "transaction #{original.id} has already been reversed"
    end

    private

    def flipped_entries(original)
      original.entries.includes(:account).order(:id).map do |entry|
        { account_code: entry.account.code, direction: FLIP.fetch(entry.direction), amount_minor: entry.amount_minor }
      end
    end
  end
end
