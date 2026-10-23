require "rails_helper"

RSpec.describe "Ledger holds" do
  before { setup_accounts(cash_minor: 50_000) }

  def captured_hold
    hold = Ledger::PlaceHold.call(key: "captured-h", account_code: "cash", amount_minor: 100)
    Ledger::CaptureHold.call(hold_id: hold.id, key: "captured-c", counter_account_code: "vendor", amount_minor: 100)
  end

  def released_hold
    hold = Ledger::PlaceHold.call(key: "released-h", account_code: "cash", amount_minor: 100)
    Ledger::ReleaseHold.call(hold_id: hold.id)
  end

  it "available = posted - held, and a hold blocks overspending" do
    Ledger::PlaceHold.call(key: "h1", account_code: "cash", amount_minor: 40_000)
    expect(Ledger::Balance.for("cash")).to have_attributes(posted_minor: 50_000, held_minor: 40_000, available_minor: 10_000)
    expect { spend("cash", 20_000) }.to raise_error(Ledger::InsufficientFunds)
    expect { Ledger::PlaceHold.call(key: "h2", account_code: "cash", amount_minor: 20_000) }.to raise_error(Ledger::InsufficientFunds)
  end

  it "captures less than held and frees the remainder" do
    hold = Ledger::PlaceHold.call(key: "h1", account_code: "cash", amount_minor: 40_000)
    Ledger::CaptureHold.call(hold_id: hold.id, key: "c1", counter_account_code: "vendor", amount_minor: 39_500)
    expect(hold.reload).to have_attributes(status: "captured", ledger_transaction: be_present)
    expect(Ledger::Balance.for("cash")).to have_attributes(posted_minor: 10_500, held_minor: 0, available_minor: 10_500)
    expect_ledger_consistent!
  end

  it "rejects capturing more than held" do
    hold = Ledger::PlaceHold.call(key: "h1", account_code: "cash", amount_minor: 100)
    expect { Ledger::CaptureHold.call(hold_id: hold.id, key: "c1", counter_account_code: "vendor", amount_minor: 101) }.to raise_error(Ledger::InvalidRequest)
  end

  it "release frees the hold and posts nothing" do
    hold = Ledger::PlaceHold.call(key: "h1", account_code: "cash", amount_minor: 100)
    expect { Ledger::ReleaseHold.call(hold_id: hold.id) }.not_to change(LedgerTransaction, :count)
    expect(Ledger::Balance.for("cash").held_minor).to eq 0
    expect_ledger_consistent!
  end

  it "replays: same place key, same capture key, second release" do
    hold = Ledger::PlaceHold.call(key: "h1", account_code: "cash", amount_minor: 100)
    expect(Ledger::PlaceHold.call(key: "h1", account_code: "cash", amount_minor: 100)).to eq hold
    capture = -> { Ledger::CaptureHold.call(hold_id: hold.id, key: "c1", counter_account_code: "vendor", amount_minor: 100) }
    capture.call
    expect { capture.call }.not_to change(Entry, :count)
    other = Ledger::PlaceHold.call(key: "h2", account_code: "cash", amount_minor: 100)
    2.times { Ledger::ReleaseHold.call(hold_id: other.id) }
    expect(other.reload.status).to eq "released"
    expect_ledger_consistent!
  end

  it "rejects invalid transitions" do
    captured, released = captured_hold, released_hold
    expect { Ledger::ReleaseHold.call(hold_id: captured.id) }.to raise_error(Ledger::InvalidState)
    expect { Ledger::CaptureHold.call(hold_id: released.id, key: "c9", counter_account_code: "vendor", amount_minor: 1) }.to raise_error(Ledger::InvalidState)
    expect { Ledger::CaptureHold.call(hold_id: captured.id, key: "c-other", counter_account_code: "vendor", amount_minor: 1) }.to raise_error(Ledger::InvalidState)
  end

  it "capture on a credit-normal account debits it" do  # Review Focus 5
    float = create(:account, :credit_normal, code: "float")
    post([ leg("funding", "debit", 5_000), leg("float", "credit", 5_000) ])
    hold = Ledger::PlaceHold.call(key: "hf", account_code: "float", amount_minor: 2_000)
    Ledger::CaptureHold.call(hold_id: hold.id, key: "cf", counter_account_code: "cash", amount_minor: 2_000)
    expect(Ledger::Balance.for("float").posted_minor).to eq 3_000
    expect(hold.reload.ledger_transaction.entries.find_by(account: float).direction).to eq "debit"
  end

  it "conflicts when a key is reused for a different request" do
    hold = Ledger::PlaceHold.call(key: "h1", account_code: "cash", amount_minor: 100)
    expect { Ledger::PlaceHold.call(key: "h1", account_code: "cash", amount_minor: 200) }.to raise_error(Ledger::ConflictError)
    Ledger::CaptureHold.call(hold_id: hold.id, key: "c1", counter_account_code: "vendor", amount_minor: 100)
    expect { Ledger::CaptureHold.call(hold_id: hold.id, key: "c1", counter_account_code: "vendor", amount_minor: 99) }.to raise_error(Ledger::ConflictError)
    post([ leg("vendor", "debit", 1), leg("cash", "credit", 1) ], key: "used")
    other = Ledger::PlaceHold.call(key: "h2", account_code: "cash", amount_minor: 100)
    expect { Ledger::CaptureHold.call(hold_id: other.id, key: "used", counter_account_code: "vendor", amount_minor: 100) }.to raise_error(Ledger::ConflictError)
  end

  it "replays a duplicate capture whose hold was read before the original committed" do
    hold = Ledger::PlaceHold.call(key: "h1", account_code: "cash", amount_minor: 100)
    stale = Hold.includes(:account).find(hold.id)
    capture = -> { Ledger::CaptureHold.call(hold_id: hold.id, key: "c1", counter_account_code: "vendor", amount_minor: 100) }
    capture.call
    # The duplicate's first read of the hold still shows it active, without a transaction.
    allow(Hold).to receive(:includes).with(:account).and_return(instance_double(ActiveRecord::Relation, find_by: stale))

    expect { expect(capture.call).to eq hold }.not_to change(Entry, :count)
  end

  it "raises NotFound for an unknown hold or account" do
    expect { Ledger::ReleaseHold.call(hold_id: 0) }.to raise_error(Ledger::NotFound)
    expect { Ledger::CaptureHold.call(hold_id: 0, key: "c1", counter_account_code: "vendor", amount_minor: 1) }.to raise_error(Ledger::NotFound)
    expect { Ledger::PlaceHold.call(key: "h1", account_code: "nope", amount_minor: 1) }.to raise_error(Ledger::NotFound)
  end

  context "concurrently", :concurrency do
    before { spend("cash", 40_000) }

    it "10 duplicates of a hold that drains the account make one hold, with the query cache on" do
      results = run_concurrently(10) do
        ActiveRecord::Base.cache { Ledger::PlaceHold.call(key: "race", account_code: "cash", amount_minor: 10_000) }
      end

      expect(results).to all(be_a(Hold))
      expect(results.map(&:id).uniq.size).to eq 1
      expect(Hold.count).to eq 1
      expect(Ledger::Balance.for("cash")).to have_attributes(held_minor: 10_000, available_minor: 0)
      expect_ledger_consistent!
    end

    it "10 duplicates of one capture post once and all get the captured hold" do
      hold = Ledger::PlaceHold.call(key: "h1", account_code: "cash", amount_minor: 10_000)

      results = run_concurrently(10) do
        Ledger::CaptureHold.call(hold_id: hold.id, key: "c1", counter_account_code: "vendor", amount_minor: 10_000)
      end

      expect(results).to all(eq(hold.reload))
      expect(hold).to have_attributes(status: "captured")
      expect(LedgerTransaction.where(idempotency_key: "c1").count).to eq 1
      expect(Ledger::Balance.for("cash")).to have_attributes(posted_minor: 0, held_minor: 0)
      expect_ledger_consistent!
    end
  end
end
