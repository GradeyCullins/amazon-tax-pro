module ApplicationHelper
  # Pill color says whether a row counts: green counts, orange needs action, gray doesn't count, red failed.
  REVIEW_PILL_CLASSES = { "needs_review" => "warn", "auto_accepted" => "good", "user_accepted" => "good", "skipped" => nil }.freeze
  SYNC_PILL_CLASSES = { "queued" => "warn", "running" => "warn", "succeeded" => "good", "failed" => "bad" }.freeze

  def money(cents)
    number_to_currency(cents.to_i / 100.0)
  end

  def review_pill(review_status, text = AmazonImportRow::REVIEW_STATUSES.fetch(review_status))
    tag.span(text, class: ["pill", REVIEW_PILL_CLASSES[review_status]])
  end

  def sync_pill(batch)
    tag.span(batch.sync_status_label, class: ["pill", SYNC_PILL_CLASSES[batch.sync_status.to_s]])
  end

  def nav_review_count
    Current.user.amazon_import_rows.needs_review.for_year(current_tax_year).count
  end

  def nav_link(name, path, &block)
    link_to(path, aria: { current: ("page" if current_page?(path)) }) { block ? capture(&block) : name }
  end

  def page_path(page)
    query = request.query_parameters.merge("page" => page)
    query.delete("page") if page == 1
    query.empty? ? request.path : "#{request.path}?#{query.to_query}"
  end

  def sync_year_range
    years = AmazonTransactionsSync.selectable_tax_years
    "#{years.min}–#{years.max}"
  end
end
