class CreateAccountsAndBalances < ActiveRecord::Migration[8.1]
  def up
    create_table :accounts do |t|
      t.text :code, null: false
      t.text :kind, null: false
      t.text :normal_side, null: false
      t.column :currency, "char(3)", null: false
      t.boolean :allow_negative, null: false, default: false
      t.timestamps

      t.index :code, unique: true
      t.check_constraint "kind IN ('asset', 'liability', 'equity', 'revenue', 'expense')", name: "accounts_kind_check"
      t.check_constraint "normal_side IN ('debit', 'credit')", name: "accounts_normal_side_check"
      t.check_constraint "currency ~ '^[A-Z]{3}$'", name: "accounts_currency_check"
    end

    create_table :account_balances, id: false do |t|
      t.bigint :account_id, null: false
      t.bigint :debits_minor, null: false, default: 0
      t.bigint :credits_minor, null: false, default: 0
      t.bigint :held_minor, null: false, default: 0
      t.bigint :version, null: false, default: 0

      t.foreign_key :accounts
      t.check_constraint "debits_minor >= 0", name: "account_balances_debits_minor_check"
      t.check_constraint "credits_minor >= 0", name: "account_balances_credits_minor_check"
      t.check_constraint "held_minor >= 0", name: "account_balances_held_minor_check"
      t.check_constraint "version >= 0", name: "account_balances_version_check"
    end

    # Plain primary key: t.bigint ... primary_key: true would add a serial default.
    execute "ALTER TABLE account_balances ADD PRIMARY KEY (account_id)"
  end

  def down
    drop_table :account_balances
    drop_table :accounts
  end
end
