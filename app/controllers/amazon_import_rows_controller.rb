class AmazonImportRowsController < ApplicationController
  def update
    row = AmazonImportRow.find(params[:id])

    if params[:commit] == "Skip"
      row.skip!
    else
      row.accept!(row_params.fetch(:tax_category))
    end

    redirect_to amazon_import_batch_path(row.amazon_import_batch), notice: "Updated import row ##{row.source_row_number}."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to amazon_import_batch_path(row.amazon_import_batch), alert: error.record.errors.full_messages.to_sentence
  end

  private

  def row_params
    params.require(:amazon_import_row).permit(:tax_category)
  end
end
