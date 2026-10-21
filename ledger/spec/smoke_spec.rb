require "rails_helper"

RSpec.describe "test tooling" do
  it "talks to the database" do
    expect(ActiveRecord::Base.connection.select_value("select 1")).to eq(1)
  end

  it "runs threads concurrently", :concurrency do
    expect(run_concurrently(10) { |i| i }.sort).to eq((0..9).to_a)
  end
end
