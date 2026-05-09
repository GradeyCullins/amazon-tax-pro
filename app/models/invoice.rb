class Invoice < ApplicationRecord
  enum :status, { draft: 0, sent: 1, paid: 2, overdue: 3 }

  scope :outstanding, -> { where(status: [:sent, :overdue]) }
end
