class LedgerTransaction < ApplicationRecord
  has_many :entries, dependent: nil
  belongs_to :reverses, class_name: "LedgerTransaction", optional: true
  has_one :reversed_by, class_name: "LedgerTransaction", foreign_key: :reverses_id, inverse_of: :reverses
end
