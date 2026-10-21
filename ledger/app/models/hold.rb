class Hold < ApplicationRecord
  STATUSES = %w[active captured released].freeze

  belongs_to :account
  belongs_to :ledger_transaction, optional: true

  validates :status, inclusion: { in: STATUSES }
end
