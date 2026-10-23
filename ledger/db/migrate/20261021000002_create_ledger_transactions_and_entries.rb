class CreateLedgerTransactionsAndEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :ledger_transactions do |t|
      t.text :idempotency_key, null: false
      t.column :request_hash, "char(64)", null: false
      t.timestamptz :effective_at, null: false
      t.jsonb :metadata, null: false, default: {}
      t.bigint :reverses_id
      t.timestamptz :created_at, null: false, default: -> { "now()" }

      t.index :idempotency_key, unique: true
      t.index :reverses_id, unique: true
      t.foreign_key :ledger_transactions, column: :reverses_id
    end

    create_table :entries do |t|
      t.bigint :ledger_transaction_id, null: false
      t.bigint :account_id, null: false
      t.text :direction, null: false
      t.bigint :amount_minor, null: false
      t.column :currency, "char(3)", null: false

      t.index :ledger_transaction_id
      t.index :account_id
      t.foreign_key :ledger_transactions
      t.foreign_key :accounts
      t.check_constraint "direction IN ('debit', 'credit')", name: "entries_direction_check"
      t.check_constraint "amount_minor > 0", name: "entries_amount_minor_check"
    end
  end
end
