module Ledger
  module Balance
    Snapshot = Data.define(:posted_minor, :held_minor, :available_minor)

    # The one place that turns debit/credit totals into a signed balance.
    def self.posted_minor(normal_side:, debits_minor:, credits_minor:)
      normal_side == "debit" ? debits_minor - credits_minor : credits_minor - debits_minor
    end

    def self.for(account_code)
      account = Account.includes(:balance).find_by(code: account_code)
      raise NotFound, "unknown account #{account_code}" unless account

      row = account.balance
      posted = posted_minor(normal_side: account.normal_side, debits_minor: row.debits_minor, credits_minor: row.credits_minor)
      Snapshot.new(posted_minor: posted, held_minor: row.held_minor, available_minor: posted - row.held_minor)
    end
  end
end
