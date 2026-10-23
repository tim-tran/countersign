class GuardAccountEditsAndPinSearchPath < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE FUNCTION ledger_forbid_account_redefinition() RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
      BEGIN
        IF (NEW.normal_side IS DISTINCT FROM OLD.normal_side OR NEW.kind IS DISTINCT FROM OLD.kind)
           AND EXISTS (SELECT 1 FROM entries WHERE account_id = OLD.id) THEN
          RAISE EXCEPTION 'account % is in use; normal_side and kind cannot change', OLD.id;
        END IF;
        RETURN NEW;
      END;
      $$;

      CREATE TRIGGER accounts_redefinition_guard
        BEFORE UPDATE OF normal_side, kind ON accounts
        FOR EACH ROW EXECUTE FUNCTION ledger_forbid_account_redefinition();

      ALTER FUNCTION ledger_forbid_change() SET search_path = public;
      ALTER FUNCTION ledger_check_balanced() SET search_path = public;
    SQL
  end

  def down
    execute <<~SQL
      ALTER FUNCTION ledger_check_balanced() RESET search_path;
      ALTER FUNCTION ledger_forbid_change() RESET search_path;
      DROP TRIGGER accounts_redefinition_guard ON accounts;
      DROP FUNCTION ledger_forbid_account_redefinition();
    SQL
  end
end
