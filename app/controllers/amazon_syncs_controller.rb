class AmazonSyncsController < ApplicationController
  before_action :set_sync_target

  # Sync wins: syncing a year that has uploaded rows first asks to remove them, so nothing is counted twice.
  def new
    @year_status = TaxYearStatus.new(Current.user, @tax_year)
    return redirect_to(root_path) unless @year_status.uploaded_rows.exists?

    counts = @year_status.uploaded_rows.group(:amazon_import_batch_id).count
    @uploads = Current.user.amazon_import_batches.where(id: counts.keys).order(:imported_at).map { |batch| [batch, counts.fetch(batch.id)] }
    @uploaded_row_count = counts.values.sum
    @reviewed_row_count = @year_status.uploaded_rows.where.not(reviewed_at: nil).count
  end

  def create
    uploaded_rows = TaxYearStatus.new(Current.user, @tax_year).uploaded_rows
    removed_count = 0

    if uploaded_rows.exists?
      return redirect_to new_amazon_sync_path(tax_year: @tax_year) unless params[:remove_uploads] == "1"

      removed_count = Current.user.remove_uploaded_rows!(@tax_year)
    end

    AmazonImportBatch.start_sp_api_sync!(connection: @connection, tax_year: @tax_year)
    remember_tax_year(@tax_year)
    notice = "Syncing #{@tax_year} from Amazon. A full year can take a few minutes; you can leave this page."
    notice = "Removed #{helpers.pluralize(helpers.number_with_delimiter(removed_count), "uploaded row")} from #{@tax_year}. #{notice}" if removed_count.positive?
    redirect_to root_path, notice: notice
  end

  private

  def set_sync_target
    @connection = Current.user.amazon_connection
    @tax_year = params[:tax_year].to_s.to_i

    if @connection.nil?
      redirect_to root_path, alert: "Connect your Amazon seller account first."
    elsif !@connection.active?
      redirect_to root_path, alert: "Amazon needs you to reconnect before you can sync."
    elsif !AmazonTransactionsSync.selectable_tax_years.include?(@tax_year)
      redirect_to root_path, alert: "Choose a tax year from #{helpers.sync_year_range} to sync."
    elsif (active_batch = @connection.active_sync_batch)
      redirect_to amazon_import_batch_path(active_batch), alert: "A sync is already running. You can start another when it finishes."
    end
  end
end
