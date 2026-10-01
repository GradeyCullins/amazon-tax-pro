# Sync history (index), run details (show), and the upload fallback (new/create/destroy).
class AmazonImportBatchesController < ApplicationController
  def index
    @batches = Current.user.amazon_import_batches.order(created_at: :desc)
    @needs_review_counts = Current.user.amazon_import_rows.needs_review.group(:amazon_import_batch_id).count
    @upload_years = Current.user.amazon_import_rows.uploaded.where.not(posted_on: nil).distinct
      .pluck(:amazon_import_batch_id, Arel.sql(AmazonImportRow::POSTED_YEAR_SQL))
      .select { |_batch_id, year| AmazonImportRow.tax_years.cover?(year) }
      .group_by(&:first).transform_values { |pairs| pairs.map(&:last).sort }
  end

  def new
    @synced_years = Current.user.synced_tax_years
  end

  def create
    result = AmazonSettlementImporter.import!(params[:file], user: Current.user)
    return redirect_to(new_amazon_import_batch_path, alert: result.errors.to_sentence) if result.errors.any?

    batch = result.batch
    needs_review_count = batch.amazon_import_rows.needs_review.count
    notice = ["Imported #{helpers.pluralize(helpers.number_with_delimiter(batch.row_count), "row")}."]
    notice << (needs_review_count.zero? ? "Every row was categorized." : "#{helpers.pluralize(helpers.number_with_delimiter(needs_review_count), "row")} still #{needs_review_count == 1 ? "needs" : "need"} a category.")
    if result.skipped_count.positive?
      notice << "Skipped #{helpers.pluralize(helpers.number_with_delimiter(result.skipped_count), "row")} from #{result.skipped_years.to_sentence} because Amazon sync already covers #{result.skipped_years.one? ? "that year" : "those years"}."
    end
    redirect_to amazon_import_batch_path(batch), notice: notice.join(" ")
  end

  def show
    @batch = Current.user.amazon_import_batches.find(params[:id])
    rows = @batch.amazon_import_rows
    @year_summaries = rows.years.map { |year| [year, rows.for_year(year).review_counts] }
    @undated_count = rows.where(posted_on: nil).count
  end

  # Only uploads can be deleted; synced rows are managed by re-syncing.
  def destroy
    batch = Current.user.amazon_import_batches.source_upload.find(params[:id])
    removed_count = AmazonImportBatch.transaction do
      AmazonImportRow.where(amazon_import_batch: batch).delete_all.tap { batch.destroy! }
    end
    redirect_to amazon_import_batches_path, notice: "Deleted #{batch.display_name} and its #{helpers.pluralize(helpers.number_with_delimiter(removed_count), "row")}."
  end
end
