class AmazonTransactionsSyncJob < ApplicationJob
  queue_as :default

  limits_concurrency to: 1, key: ->(batch) { batch.amazon_connection_id }, duration: 2.hours

  def perform(batch)
    AmazonTransactionsSync.new(batch).run!
  end
end
