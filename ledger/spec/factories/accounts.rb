FactoryBot.define do
  factory :account do
    sequence(:code) { |n| "acct_#{n}" }
    kind { "asset" }
    normal_side { "debit" }
    currency { "USD" }

    trait :credit_normal do
      kind { "liability" }
      normal_side { "credit" }
    end

    trait :allow_negative do
      allow_negative { true }
    end

    trait :cad do
      currency { "CAD" }
    end
  end
end
