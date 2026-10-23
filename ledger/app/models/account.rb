class Account < ApplicationRecord
  KINDS = %w[asset liability equity revenue expense].freeze
  SIDES = %w[debit credit].freeze

  has_one :balance, class_name: "AccountBalance", dependent: :destroy

  validates :code, presence: true, uniqueness: true
  validates :kind, inclusion: { in: KINDS }
  validates :normal_side, inclusion: { in: SIDES }
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }

  after_create :create_balance!
end
