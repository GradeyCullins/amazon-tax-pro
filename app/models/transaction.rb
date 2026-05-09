class Transaction < ApplicationRecord
  belongs_to :debit_account, class_name: 'Account'
  belongs_to :credit_account, class_name: 'Account'

  scope :current_month, -> { where(transacted_on: Date.current.beginning_of_month..Date.current.end_of_month) }
  scope :revenue, -> { joins(:credit_account).where(accounts: { kind: :revenue }) }
  scope :expense, -> { joins(:debit_account).where(accounts: { kind: :expense }) }

  validates :description, :transacted_on, :amount_cents, presence: true
end
