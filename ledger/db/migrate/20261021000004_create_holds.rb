class CreateHolds < ActiveRecord::Migration[8.1]
  def change
    create_table :holds do |t|
      t.references :account, null: false, foreign_key: true
      t.bigint :amount_minor, null: false
      t.text :status, null: false, default: "active"
      t.text :idempotency_key, null: false
      t.column :request_hash, "char(64)", null: false
      t.references :ledger_transaction, foreign_key: true, index: { unique: true }
      t.timestamps

      t.index :idempotency_key, unique: true
      t.check_constraint "amount_minor > 0", name: "holds_amount_minor_check"
      t.check_constraint "status IN ('active', 'captured', 'released')", name: "holds_status_check"
      t.check_constraint "(status = 'captured') = (ledger_transaction_id IS NOT NULL)", name: "holds_captured_has_transaction_check"
    end
  end
end
