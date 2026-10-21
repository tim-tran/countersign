class AddLedgerGuards < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE FUNCTION ledger_forbid_change() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        RAISE EXCEPTION 'ledger rows are immutable';
      END;
      $$;

      CREATE TRIGGER ledger_transactions_immutable
        BEFORE UPDATE OR DELETE ON ledger_transactions
        FOR EACH ROW EXECUTE FUNCTION ledger_forbid_change();

      CREATE TRIGGER entries_immutable
        BEFORE UPDATE OR DELETE ON entries
        FOR EACH ROW EXECUTE FUNCTION ledger_forbid_change();

      CREATE UNIQUE INDEX index_accounts_on_id_and_currency ON accounts (id, currency);

      ALTER TABLE entries
        ADD CONSTRAINT entries_account_currency_fkey
        FOREIGN KEY (account_id, currency) REFERENCES accounts (id, currency);

      CREATE FUNCTION ledger_check_balanced() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF (SELECT count(*) FROM entries WHERE ledger_transaction_id = NEW.ledger_transaction_id) < 2
           OR EXISTS (
             SELECT 1 FROM entries
             WHERE ledger_transaction_id = NEW.ledger_transaction_id
             GROUP BY currency
             HAVING sum(CASE direction WHEN 'debit' THEN amount_minor ELSE -amount_minor END) <> 0
           ) THEN
          RAISE EXCEPTION 'ledger transaction % is unbalanced', NEW.ledger_transaction_id;
        END IF;
        RETURN NULL;
      END;
      $$;

      CREATE CONSTRAINT TRIGGER entries_balanced
        AFTER INSERT ON entries
        DEFERRABLE INITIALLY DEFERRED
        FOR EACH ROW EXECUTE FUNCTION ledger_check_balanced();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER entries_balanced ON entries;
      DROP FUNCTION ledger_check_balanced();
      ALTER TABLE entries DROP CONSTRAINT entries_account_currency_fkey;
      DROP INDEX index_accounts_on_id_and_currency;
      DROP TRIGGER entries_immutable ON entries;
      DROP TRIGGER ledger_transactions_immutable ON ledger_transactions;
      DROP FUNCTION ledger_forbid_change();
    SQL
  end
end
