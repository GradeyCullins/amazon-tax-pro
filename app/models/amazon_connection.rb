class AmazonConnection < ApplicationRecord
  US_MARKETPLACE_ID = "ATVPDKIKX0DER".freeze

  belongs_to :user
  has_many :amazon_import_batches, dependent: :nullify

  encrypts :refresh_token

  enum :status, { active: 0, revoked: 1, error: 2 }

  validates :selling_partner_id, :refresh_token, :region, :marketplace_id, :connected_at, presence: true
  validates :selling_partner_id, uniqueness: true

  def self.connect!(user:, selling_partner_id:, refresh_token:)
    connection = user.amazon_connection || user.build_amazon_connection
    connection.update!(
      selling_partner_id: selling_partner_id,
      refresh_token: refresh_token,
      status: :active,
      connected_at: Time.current,
      last_error: nil
    )
    connection
  end

  # Batches that stop reporting progress (e.g. the worker died) no longer block new syncs.
  def active_sync_batch
    amazon_import_batches.where(sync_status: %i[queued running]).where(updated_at: 30.minutes.ago..).order(:created_at).last
  end

  def mark_revoked!(message)
    update!(status: :revoked, last_error: message)
  end
end
