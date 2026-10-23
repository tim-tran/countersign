require "rails_helper"

RSpec.describe "Ledger database guards" do
  let(:connection) { ApplicationRecord.connection }

  def insert_transaction_sql
    connection.select_value(<<~SQL.squish)
      INSERT INTO ledger_transactions (idempotency_key, request_hash, effective_at)
      VALUES (#{connection.quote(SecureRandom.uuid)}, #{connection.quote('a' * 64)}, now())
      RETURNING id
    SQL
  end

  def insert_entry_sql(ledger_transaction_id: insert_transaction_sql, account: Account.find_by!(code: "cash"),
                       direction: "debit", amount_minor: 100, currency: account.currency)
    connection.execute(<<~SQL.squish)
      INSERT INTO entries (ledger_transaction_id, account_id, direction, amount_minor, currency)
      VALUES (#{connection.quote(ledger_transaction_id)}, #{connection.quote(account.id)},
              #{connection.quote(direction)}, #{connection.quote(amount_minor)}, #{connection.quote(currency)})
    SQL
  end

  def insert_transaction_with_entries_sql(legs)
    transaction_id = insert_transaction_sql
    accounts = { "debit" => Account.find_by!(code: "cash"), "credit" => Account.find_by!(code: "funding") }
    legs.each do |direction, amount|
      insert_entry_sql(ledger_transaction_id: transaction_id, account: accounts.fetch(direction),
                       direction: direction, amount_minor: amount)
    end
    transaction_id
  end

  before { setup_accounts }

  describe "immutability" do
    let!(:txn) { post([ leg("cash", "debit", 500), leg("funding", "credit", 500) ]) }
    let(:entry) { Entry.first }

    it "refuses update, update_columns, destroy, delete_all and raw SQL" do
      [ -> { txn.update!(metadata: { "x" => 1 }) },
        -> { entry.update_columns(amount_minor: 1) },
        -> { entry.destroy },
        -> { Entry.delete_all },
        -> { LedgerTransaction.connection.execute("DELETE FROM ledger_transactions") },
        -> { LedgerTransaction.connection.execute("UPDATE entries SET amount_minor = 1") } ].each do |attempt|
        expect { ApplicationRecord.transaction(requires_new: true) { attempt.call } }
          .to raise_error(ActiveRecord::StatementInvalid, /immutable/)
      end
    end
  end

  it "refuses an entry whose currency differs from its account" do
    expect { insert_entry_sql(currency: "CAD") }.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it "refuses an unbalanced transaction at commit" do
    insert_transaction_with_entries_sql([ [ "debit", 100 ], [ "credit", 99 ] ])
    expect { connection.execute("SET CONSTRAINTS ALL IMMEDIATE") }
      .to raise_error(ActiveRecord::StatementInvalid, /unbalanced/)
  end

  it "accepts a balanced transaction at commit" do
    insert_transaction_with_entries_sql([ [ "debit", 100 ], [ "credit", 100 ] ])
    expect { connection.execute("SET CONSTRAINTS ALL IMMEDIATE") }.not_to raise_error
  end

  it "refuses a single-entry transaction" do
    insert_entry_sql
    expect { connection.execute("SET CONSTRAINTS ALL IMMEDIATE") }
      .to raise_error(ActiveRecord::StatementInvalid, /unbalanced/)
  end
end
