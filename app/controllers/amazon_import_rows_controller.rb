class AmazonImportRowsController < ApplicationController
  def update
    row = Current.user.amazon_import_rows.find(params[:id])

    if params[:commit] == "Skip"
      row.skip!
    else
      row.accept!(row_params.fetch(:tax_category))
    end

    redirect_to review_path(row), notice: "Updated import row ##{row.source_row_number}."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to review_path(row), alert: error.record.errors.full_messages.to_sentence
  end

  private

  def row_params
    params.require(:amazon_import_row).permit(:tax_category)
  end

  def review_path(row)
    filters = params.permit(:q, :category, :status, :min_amount, :max_amount, :sort, :view, :page, :open_group).to_h.compact
    amazon_import_batch_path(row.amazon_import_batch, filters)
  end
end
