class AmazonImportBatchesController < ApplicationController
  def index
    @batches = AmazonImportBatch.order(imported_at: :desc)
  end

  def new
  end

  def create
    result = AmazonSettlementImporter.import!(params[:file])

    if result.errors.any?
      redirect_to new_amazon_import_batch_path, alert: result.errors.to_sentence
    else
      redirect_to amazon_import_batch_path(result.batch), notice: "Imported #{result.batch.row_count} Amazon settlement rows."
    end
  end

  def show
    @batch = AmazonImportBatch.find(params[:id])
    @rows = @batch.amazon_import_rows.order(:source_row_number)
  end
end
