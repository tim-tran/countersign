require "rails_helper"

RSpec.describe "Ledger trial balance", :concurrency do
  it "stays balanced after 2,000 random postings" do
    seed = Integer(ENV.fetch("TRIAL_SEED", Random.new_seed))
    rng = Random.new(seed)
    accounts = {
      "USD" => create_list(:account, 6, :allow_negative),
      "CAD" => create_list(:account, 4, :allow_negative, :cad)
    }

    2_000.times do |i|
      currency, pool = accounts.to_a.sample(random: rng)
      legs = Array.new(rng.rand(1..3)) { [ pool.sample(random: rng), rng.rand(1..1_000_000) ] }
      entries = legs.flat_map { |acct, amt| [ leg(acct.code, "debit", amt), leg(pool.sample(random: rng).code, "credit", amt) ] }
      Ledger::PostTransaction.call(key: "trial-#{seed}-#{i}", entries:)
    end

    aggregate_failures("TRIAL_SEED=#{seed}") { expect_ledger_consistent!(label: "TRIAL_SEED=#{seed}") }
  end
end
