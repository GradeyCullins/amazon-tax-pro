class OutsideExpensesController < ApplicationController
  before_action :set_year
  before_action :set_expense, only: [:edit, :update, :destroy, :restore]

  def index
    @expense = Current.user.outside_expenses.new(business_use_percent: 100)
    load_entries
  end

  def create
    @expense = Current.user.outside_expenses.new(expense_params)
    return render_invalid unless date_in_selected_year?

    if @expense.save
      redirect_to outside_expenses_path(year: @year), notice: "Saved outside Amazon expense."
    else
      render_invalid
    end
  end

  def edit
    redirect_to outside_expenses_path(year: @year) if @expense.archived_at?
  end

  def update
    @expense.assign_attributes(expense_params)
    unless date_in_selected_year?
      render :edit, status: :unprocessable_entity
      return
    end

    if @expense.save
      redirect_to outside_expenses_path(year: @year), notice: "Updated outside Amazon expense."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @expense.update!(archived_at: Time.current)
    redirect_to outside_expenses_path(year: @year), notice: "Removed the expense. You can restore it below."
  end

  def restore
    @expense.update!(archived_at: nil)
    redirect_to outside_expenses_path(year: @year), notice: "Restored the expense."
  end

  private

  def set_year
    @year = current_tax_year
  end

  def set_expense
    @expense = Current.user.outside_expenses.for_year(@year).find(params[:id])
  end

  def expense_params
    params.require(:outside_expense).permit(:spent_on, :payee, :category, :amount_dollars, :business_use_percent, :description)
  end

  def date_in_selected_year?
    return true if @expense.spent_on&.year == @year

    @expense.errors.add(:spent_on, "must be in #{@year}, the selected tax year")
    false
  end

  def render_invalid
    load_entries
    render :index, status: :unprocessable_entity
  end

  def load_entries
    year_entries = Current.user.outside_expenses.for_year(@year)
    @entries = year_entries.active.order(spent_on: :desc, id: :desc).to_a
    @archived_entries = year_entries.archived.order(archived_at: :desc).to_a
    @total_cents = @entries.sum(&:deductible_cents)
  end
end
