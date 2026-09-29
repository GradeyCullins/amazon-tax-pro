namespace :amazon do
  desc "Reclassify pending SP-API receipt rows for one seller (dry run unless APPLY=1)"
  task reclassify_non_sales: :environment do
    email = ENV.fetch("EMAIL")
    user = User.find_by!(email_address: email)
    rows = user.amazon_import_rows
      .joins(:amazon_import_batch)
      .where(amazon_import_batches: { source: AmazonImportBatch.sources.fetch("sp_api") })
      .pending
      .where(tax_category: %w[gross_sales shipping])

    corrections = rows.filter_map do |row|
      category = AmazonTaxCategorizer.for_transaction_breakdown(
        row.transaction_type,
        row.amount_type.to_s.split(" > "),
        row.amount_cents
      )
      [row, category] unless category == row.tax_category
    end

    puts "#{corrections.size} pending rows to reclassify (#{corrections.sum { |row, _| row.amount_cents } / 100.0} dollars removed from gross receipts)."
    corrections.group_by(&:last).each do |category, matches|
      puts "  #{category}: #{matches.size} rows"
    end

    if ENV["APPLY"] == "1"
      AmazonImportRow.transaction do
        corrections.each { |row, category| row.update!(tax_category: category) }
      end
      puts "Applied. Reviewed and skipped rows were not changed."
    else
      puts "Dry run. Set APPLY=1 to update these pending rows."
    end
  end
end
