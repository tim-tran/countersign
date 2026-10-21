class Entry < ApplicationRecord
  belongs_to :ledger_transaction
  belongs_to :account
end
