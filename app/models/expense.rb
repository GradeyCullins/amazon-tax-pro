class Expense < ApplicationRecord
  scope :current_month, -> { where(spent_on: Date.current.beginning_of_month..Date.current.end_of_month) }
end
