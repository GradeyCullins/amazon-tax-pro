class Account < ApplicationRecord
  enum :kind, { asset: 0, liability: 1, equity: 2, revenue: 3, expense: 4 }

  validates :name, :kind, presence: true
end
