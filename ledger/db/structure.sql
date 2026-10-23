SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: ledger_check_balanced(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ledger_check_balanced() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
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


--
-- Name: ledger_forbid_account_redefinition(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ledger_forbid_account_redefinition() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
  IF (NEW.normal_side IS DISTINCT FROM OLD.normal_side OR NEW.kind IS DISTINCT FROM OLD.kind)
     AND EXISTS (SELECT 1 FROM entries WHERE account_id = OLD.id) THEN
    RAISE EXCEPTION 'account % is in use; normal_side and kind cannot change', OLD.id;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: ledger_forbid_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ledger_forbid_change() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
  RAISE EXCEPTION 'ledger rows are immutable';
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: account_balances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.account_balances (
    account_id bigint NOT NULL,
    debits_minor bigint DEFAULT 0 NOT NULL,
    credits_minor bigint DEFAULT 0 NOT NULL,
    held_minor bigint DEFAULT 0 NOT NULL,
    version bigint DEFAULT 0 NOT NULL,
    CONSTRAINT account_balances_credits_minor_check CHECK ((credits_minor >= 0)),
    CONSTRAINT account_balances_debits_minor_check CHECK ((debits_minor >= 0)),
    CONSTRAINT account_balances_held_minor_check CHECK ((held_minor >= 0)),
    CONSTRAINT account_balances_version_check CHECK ((version >= 0))
);


--
-- Name: accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounts (
    id bigint NOT NULL,
    code text NOT NULL,
    kind text NOT NULL,
    normal_side text NOT NULL,
    currency character(3) NOT NULL,
    allow_negative boolean DEFAULT false NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT accounts_currency_check CHECK ((currency ~ '^[A-Z]{3}$'::text)),
    CONSTRAINT accounts_kind_check CHECK ((kind = ANY (ARRAY['asset'::text, 'liability'::text, 'equity'::text, 'revenue'::text, 'expense'::text]))),
    CONSTRAINT accounts_normal_side_check CHECK ((normal_side = ANY (ARRAY['debit'::text, 'credit'::text])))
);


--
-- Name: accounts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounts_id_seq OWNED BY public.accounts.id;


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.entries (
    id bigint NOT NULL,
    ledger_transaction_id bigint NOT NULL,
    account_id bigint NOT NULL,
    direction text NOT NULL,
    amount_minor bigint NOT NULL,
    currency character(3) NOT NULL,
    CONSTRAINT entries_amount_minor_check CHECK ((amount_minor > 0)),
    CONSTRAINT entries_direction_check CHECK ((direction = ANY (ARRAY['debit'::text, 'credit'::text])))
);


--
-- Name: entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.entries_id_seq OWNED BY public.entries.id;


--
-- Name: holds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.holds (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    amount_minor bigint NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    idempotency_key text NOT NULL,
    request_hash character(64) NOT NULL,
    ledger_transaction_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT holds_amount_minor_check CHECK ((amount_minor > 0)),
    CONSTRAINT holds_captured_has_transaction_check CHECK (((status = 'captured'::text) = (ledger_transaction_id IS NOT NULL))),
    CONSTRAINT holds_status_check CHECK ((status = ANY (ARRAY['active'::text, 'captured'::text, 'released'::text])))
);


--
-- Name: holds_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.holds_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: holds_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.holds_id_seq OWNED BY public.holds.id;


--
-- Name: ledger_transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ledger_transactions (
    id bigint NOT NULL,
    idempotency_key text NOT NULL,
    request_hash character(64) NOT NULL,
    effective_at timestamp with time zone NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    reverses_id bigint,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: ledger_transactions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ledger_transactions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ledger_transactions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ledger_transactions_id_seq OWNED BY public.ledger_transactions.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: accounts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts ALTER COLUMN id SET DEFAULT nextval('public.accounts_id_seq'::regclass);


--
-- Name: entries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entries ALTER COLUMN id SET DEFAULT nextval('public.entries_id_seq'::regclass);


--
-- Name: holds id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.holds ALTER COLUMN id SET DEFAULT nextval('public.holds_id_seq'::regclass);


--
-- Name: ledger_transactions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_transactions ALTER COLUMN id SET DEFAULT nextval('public.ledger_transactions_id_seq'::regclass);


--
-- Name: account_balances account_balances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_balances
    ADD CONSTRAINT account_balances_pkey PRIMARY KEY (account_id);


--
-- Name: accounts accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT accounts_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: entries entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entries
    ADD CONSTRAINT entries_pkey PRIMARY KEY (id);


--
-- Name: holds holds_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.holds
    ADD CONSTRAINT holds_pkey PRIMARY KEY (id);


--
-- Name: ledger_transactions ledger_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_transactions
    ADD CONSTRAINT ledger_transactions_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: index_accounts_on_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounts_on_code ON public.accounts USING btree (code);


--
-- Name: index_accounts_on_id_and_currency; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounts_on_id_and_currency ON public.accounts USING btree (id, currency);


--
-- Name: index_entries_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_entries_on_account_id ON public.entries USING btree (account_id);


--
-- Name: index_entries_on_ledger_transaction_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_entries_on_ledger_transaction_id ON public.entries USING btree (ledger_transaction_id);


--
-- Name: index_holds_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_holds_on_account_id ON public.holds USING btree (account_id);


--
-- Name: index_holds_on_idempotency_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_holds_on_idempotency_key ON public.holds USING btree (idempotency_key);


--
-- Name: index_holds_on_ledger_transaction_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_holds_on_ledger_transaction_id ON public.holds USING btree (ledger_transaction_id);


--
-- Name: index_ledger_transactions_on_idempotency_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_ledger_transactions_on_idempotency_key ON public.ledger_transactions USING btree (idempotency_key);


--
-- Name: index_ledger_transactions_on_reverses_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_ledger_transactions_on_reverses_id ON public.ledger_transactions USING btree (reverses_id);


--
-- Name: accounts accounts_redefinition_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER accounts_redefinition_guard BEFORE UPDATE OF normal_side, kind ON public.accounts FOR EACH ROW EXECUTE FUNCTION public.ledger_forbid_account_redefinition();


--
-- Name: entries entries_balanced; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER entries_balanced AFTER INSERT ON public.entries DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.ledger_check_balanced();


--
-- Name: entries entries_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER entries_immutable BEFORE DELETE OR UPDATE ON public.entries FOR EACH ROW EXECUTE FUNCTION public.ledger_forbid_change();


--
-- Name: ledger_transactions ledger_transactions_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ledger_transactions_immutable BEFORE DELETE OR UPDATE ON public.ledger_transactions FOR EACH ROW EXECUTE FUNCTION public.ledger_forbid_change();


--
-- Name: entries entries_account_currency_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entries
    ADD CONSTRAINT entries_account_currency_fkey FOREIGN KEY (account_id, currency) REFERENCES public.accounts(id, currency);


--
-- Name: holds fk_rails_0e68052f5b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.holds
    ADD CONSTRAINT fk_rails_0e68052f5b FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: entries fk_rails_37a3feaeb6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entries
    ADD CONSTRAINT fk_rails_37a3feaeb6 FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: ledger_transactions fk_rails_969c84a0e1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_transactions
    ADD CONSTRAINT fk_rails_969c84a0e1 FOREIGN KEY (reverses_id) REFERENCES public.ledger_transactions(id);


--
-- Name: holds fk_rails_aa253fcf62; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.holds
    ADD CONSTRAINT fk_rails_aa253fcf62 FOREIGN KEY (ledger_transaction_id) REFERENCES public.ledger_transactions(id);


--
-- Name: entries fk_rails_dfe59f25ea; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entries
    ADD CONSTRAINT fk_rails_dfe59f25ea FOREIGN KEY (ledger_transaction_id) REFERENCES public.ledger_transactions(id);


--
-- Name: account_balances fk_rails_f3e5781e9c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_balances
    ADD CONSTRAINT fk_rails_f3e5781e9c FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20261022000001'),
('20261021000004'),
('20261021000003'),
('20261021000002'),
('20261021000001');

