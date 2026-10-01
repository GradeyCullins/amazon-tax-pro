# Year-level facts for one seller, shared by the dashboard, Review, and output pages.
class TaxYearStatus
  attr_reader :user, :year

  def initialize(user, year)
    @user = user
    @year = year.to_i
  end

  def rows
    user.amazon_import_rows.for_year(year)
  end

  def review_counts
    @review_counts ||= rows.review_counts
  end

  def needs_review_count
    review_counts.fetch("needs_review")
  end

  def counted_rows_count
    review_counts.fetch("auto_accepted") + review_counts.fetch("user_accepted")
  end

  def row_count
    review_counts.values.sum
  end

  def rows?
    row_count.positive?
  end

  def synced?
    @synced = user.synced_tax_years.include?(year) if @synced.nil?
    @synced
  end

  def syncable?
    AmazonTransactionsSync.selectable_tax_years.include?(year)
  end

  def uploaded_rows
    rows.uploaded
  end

  # Rows from Amazon's fixed sandbox sample (development only) aren't real seller data.
  def sandbox_sample?
    rows.joins(:amazon_import_batch).where(amazon_import_batches: { sandbox_sample: true }).exists?
  end

  # Uploaded rows in a synced year can duplicate transactions the sync already pulled in.
  def mixed_sources?
    @mixed_sources = synced? && uploaded_rows.exists? if @mixed_sources.nil?
    @mixed_sources
  end

  def latest_sync
    return @latest_sync if defined?(@latest_sync)

    @latest_sync = user.amazon_import_batches.source_sp_api.where(tax_year: year).order(:created_at).last
  end

  # A sync for this year that's still running (stale runs don't count; see AmazonConnection#active_sync_batch).
  def active_sync
    return @active_sync if defined?(@active_sync)

    sync = user.amazon_connection&.active_sync_batch
    @active_sync = sync if sync&.tax_year == year
  end
end
