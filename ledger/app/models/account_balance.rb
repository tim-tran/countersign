class AccountBalance < ApplicationRecord
  self.primary_key = "account_id"

  belongs_to :account
end
