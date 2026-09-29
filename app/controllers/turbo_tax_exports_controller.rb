class TurboTaxExportsController < ApplicationController
  before_action :set_year
  before_action :set_input

  def show
    @export = TurboTaxExport.new(year: @year, input: @input)
  end

  def update
    if @input.update(input_params)
      redirect_to turbo_tax_export_path(year: @input.tax_year), notice: "Updated TurboTax export inputs."
    else
      @export = TurboTaxExport.new(year: @year, input: @input)
      flash.now[:alert] = @input.errors.full_messages.to_sentence
      render :show, status: :unprocessable_entity
    end
  end

  def download
    @input.save! if @input.new_record?
    export = TurboTaxExport.new(year: @year, input: @input)

    case params[:format_type]
    when "audit"
      send_data export.audit_csv, filename: "amazon_seller_#{@year}_audit.csv", type: "text/csv"
    when "instructions"
      send_data export.instructions_html, filename: "amazon_seller_#{@year}_turbotax_instructions.html", type: "text/html"
    else
      send_data export.txf, filename: "amazon_seller_#{@year}_schedule_c.txf", type: "application/octet-stream"
    end
  end

  private

  def set_year
    @year = params[:year].presence&.to_i || Current.user.amazon_import_rows.where.not(posted_on: nil).maximum("strftime('%Y', posted_on)")&.to_i || Date.current.year
  end

  def set_input
    @input = Current.user.turbo_tax_export_inputs.for_year(@year)
  end

  def input_params
    params.require(:turbo_tax_export_input).permit(
      :tax_year,
      :business_name,
      :beginning_inventory_dollars,
      :purchases_dollars,
      :materials_dollars,
      :labor_dollars,
      :other_costs_dollars,
      :ending_inventory_dollars
    )
  end
end
