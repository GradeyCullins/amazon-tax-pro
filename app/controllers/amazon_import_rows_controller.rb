class AmazonImportRowsController < ApplicationController
  ACCEPT_VERBS = { "Save" => "Saved", "Restore" => "Restored" }.freeze

  def update
    row = Current.user.amazon_import_rows.find(params[:id])

    if params[:commit] == "Skip"
      row.skip!
      notice = "Skipped. That row won't count toward your totals."
    else
      row.accept!(row_params.fetch(:tax_category))
      notice = "#{ACCEPT_VERBS.fetch(params[:commit], "Accepted")} as #{row.tax_category_name}."
    end

    redirect_back_or_to review_path(year: row.posted_on&.year), notice: notice
  rescue ActiveRecord::RecordInvalid => error
    redirect_back_or_to review_path(year: row.posted_on&.year), alert: error.record.errors.full_messages.to_sentence
  end

  private

  def row_params
    params.require(:amazon_import_row).permit(:tax_category)
  end
end
