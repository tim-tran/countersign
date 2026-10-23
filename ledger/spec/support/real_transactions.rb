# Examples tagged :concurrency run outside the wrapping transaction so that
# several database connections can see each other's commits. Everything they
# write is truncated afterwards.
RSpec.shared_context "with real transactions" do
  self.use_transactional_tests = false

  after { truncate_ledger_tables }

  def truncate_ledger_tables
    connection = ActiveRecord::Base.connection
    tables = connection.tables - %w[schema_migrations ar_internal_metadata]
    return if tables.empty?

    connection.execute(
      "TRUNCATE #{tables.map { |table| connection.quote_table_name(table) }.join(', ')} RESTART IDENTITY CASCADE"
    )
  end
end

RSpec.configure do |config|
  config.include_context "with real transactions", :concurrency
end
