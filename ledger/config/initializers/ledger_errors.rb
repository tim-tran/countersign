# The Rails application module is also named Ledger (config/application.rb), so
# Zeitwerk sees the constant as already defined and never autoloads
# app/services/ledger.rb. Load it explicitly; it only reopens the module to
# define the error classes, so reloading is idempotent.
Rails.application.config.to_prepare do
  load Rails.root.join("app/services/ledger.rb")
end
