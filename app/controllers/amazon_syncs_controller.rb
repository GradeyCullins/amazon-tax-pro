class AmazonSyncsController < ApplicationController
  def create
    connection = Current.user.amazon_connection
    tax_year = params[:tax_year].to_i

    if connection.nil?
      redirect_to root_path, alert: "Connect your Amazon seller account first."
    elsif !connection.active?
      redirect_to root_path, alert: "Your Amazon authorization is no longer valid. Reconnect your Amazon account."
    elsif !AmazonTransactionsSync.selectable_tax_years.include?(tax_year)
      redirect_to root_path, alert: "Choose a tax year to sync."
    elsif (active_batch = connection.active_sync_batch)
      redirect_to amazon_import_batch_path(active_batch), alert: "A sync is already in progress."
    else
      batch = AmazonImportBatch.start_sp_api_sync!(connection: connection, tax_year: tax_year)
      redirect_to amazon_import_batch_path(batch), notice: "Syncing #{tax_year} transactions from Amazon. This can take a few minutes."
    end
  end
end
