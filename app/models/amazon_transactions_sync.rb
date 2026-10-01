# Pulls one tax year of Finances API v2024-06-19 transactions into an sp_api AmazonImportBatch.
class AmazonTransactionsSync
  WINDOW_LENGTH = 179.days # listTransactions returns nothing when postedAfter/postedBefore are >180 days apart
  PAGE_DELAY_SECONDS = 2 # listTransactions allows 0.5 requests/second
  ACCESS_TOKEN_TTL = 50.minutes
  # The static sandbox matches these exact values from Amazon's Finances API model.
  # Its sample nextToken is a request parameter, not a real pagination cursor.
  SANDBOX_PARAMETERS = { posted_after: "2023-03-07", next_token: "jehgri34yo7jr9e8f984tr9i4o" }.freeze
  # Still-deferred transactions haven't been released to the seller yet; they show up as DEFERRED_RELEASED once they are.
  SKIPPED_STATUSES = %w[DEFERRED].freeze
  YEARS_OFFERED = 3

  def self.selectable_tax_years
    Date.current.year.downto(Date.current.year - YEARS_OFFERED).to_a
  end

  def initialize(batch, sleeper: ->(seconds) { sleep(seconds) })
    @batch = batch
    @connection = batch.amazon_connection
    @user = batch.user
    @sleeper = sleeper
  end

  def run!
    raise AmazonSpApi::Error, "This sync isn't linked to an Amazon connection." unless @connection

    @batch.update!(sync_status: :running, started_at: Time.current, error_message: nil)
    @row_number = @batch.amazon_import_rows.maximum(:source_row_number).to_i
    @transactions_fetched = 0

    windows.each { |posted_after, posted_before| import_window(posted_after, posted_before) }

    @batch.refresh_status!
    @batch.update!(sync_status: :succeeded, finished_at: Time.current, transactions_fetched: @transactions_fetched)
    @connection.update!(last_synced_at: Time.current, status: :active, last_error: nil)
  rescue AmazonSpApi::AuthorizationRevoked => error
    @connection&.mark_revoked!(error.message)
    fail!(error)
  rescue StandardError => error
    Rails.logger.error("[AmazonTransactionsSync] batch=#{@batch.id} #{error.class}: #{error.message}")
    fail!(error)
  end

  private

  def windows
    zone = ActiveSupport::TimeZone[AmazonTransactionNormalizer::REPORTING_TIME_ZONE]
    year_start = zone.local(@batch.tax_year, 1, 1)
    year_end = [zone.local(@batch.tax_year + 1, 1, 1), 3.minutes.ago].min
    raise AmazonSpApi::Error, "#{@batch.tax_year} has not started yet." if year_start >= year_end

    # Fetch the canned sandbox response once, regardless of the selected tax year.
    return [[year_start, year_end]] if AmazonSpApi.sandbox?

    windows = []
    window_start = year_start
    while window_start < year_end
      window_end = [window_start + WINDOW_LENGTH, year_end].min
      windows << [window_start, window_end]
      window_start = window_end
    end
    windows
  end

  def import_window(posted_after, posted_before)
    next_token = nil
    loop do
      page = list_transactions(posted_after, posted_before, next_token)
      transactions = Array(page.dig("payload", "transactions"))
      import_transactions(transactions)
      @transactions_fetched += transactions.size
      @batch.update_columns(transactions_fetched: @transactions_fetched, row_count: @batch.amazon_import_rows.count, updated_at: Time.current)

      # The static response contains a placeholder nextToken with no follow-up page.
      break if AmazonSpApi.sandbox?

      next_token = page.dig("payload", "nextToken").presence
      break unless next_token

      @sleeper.call(PAGE_DELAY_SECONDS)
    end
  end

  def list_transactions(posted_after, posted_before, next_token)
    parameters = if AmazonSpApi.sandbox?
      SANDBOX_PARAMETERS
    else
      { posted_after: posted_after.utc.iso8601, posted_before: posted_before.utc.iso8601, next_token: next_token }
    end
    finances_client.list_transactions(**parameters).to_h
  rescue Peddler::Errors::Unauthorized, Peddler::Errors::AccessDenied => error
    raise AmazonSpApi::AuthorizationRevoked, "Amazon denied access to financial data (#{error.message}). Reconnect your Amazon account."
  end

  def import_transactions(transactions)
    rows = transactions
      .reject { |transaction| SKIPPED_STATUSES.include?(transaction["transactionStatus"]) }
      .flat_map { |transaction| AmazonTransactionNormalizer.rows_for(transaction) }
    return if rows.empty?

    existing_ids = @user.amazon_import_rows.where(external_id: rows.map { |row| row[:external_id] }).pluck(:external_id).to_set

    rows.each do |attrs|
      next if existing_ids.include?(attrs[:external_id])

      @row_number += 1
      status = AmazonImportRow.initial_status_for(attrs[:tax_category])
      @batch.amazon_import_rows.create!(attrs.merge(user: @user, source_row_number: @row_number, status: status))
    rescue ActiveRecord::RecordNotUnique
      next
    end
  end

  def finances_client
    if @finances_client.nil? || @token_fetched_at < ACCESS_TOKEN_TTL.ago
      @token_fetched_at = Time.current
      @finances_client = AmazonSpApi.finances_client(@connection, access_token: AmazonSpApi.access_token_for(@connection))
    end
    @finances_client
  end

  def fail!(error)
    @batch.refresh_status!
    @batch.update!(sync_status: :failed, finished_at: Time.current, error_message: error.message.to_s.truncate(1000))
    @connection&.update!(last_error: error.message.to_s.truncate(1000)) unless @connection&.revoked?
  end
end
