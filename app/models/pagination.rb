# Offset pagination for long row tables, without a gem.
class Pagination
  attr_reader :page, :per_page, :total_count, :total_pages

  def initialize(scope, page:, per_page: 100)
    @scope = scope
    @per_page = per_page
    @total_count = scope.count
    @total_pages = [(total_count.to_f / per_page).ceil, 1].max
    @page = page.to_s.to_i.clamp(1, total_pages)
  end

  def records
    @records ||= @scope.offset((page - 1) * per_page).limit(per_page)
  end

  def first_item
    total_count.zero? ? 0 : (page - 1) * per_page + 1
  end

  def last_item
    [page * per_page, total_count].min
  end

  def previous_page
    page - 1 if page > 1
  end

  def next_page
    page + 1 if page < total_pages
  end
end
