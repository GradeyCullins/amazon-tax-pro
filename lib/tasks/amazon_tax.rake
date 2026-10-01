namespace :amazon do
  desc "Re-run category rules and auto-accept on rows no one has reviewed (dry run unless APPLY=1; EMAIL=... limits to one seller)"
  task recategorize: :environment do
    rows = AmazonImportRow.where(reviewed_at: nil).where.not(status: :skipped).includes(:amazon_import_batch)
    rows = rows.where(user: User.find_by!(email_address: ENV["EMAIL"])) if ENV["EMAIL"].present?

    # Synced rows keep their Amazon breakdown path, so the current rules can re-categorize them.
    # Uploaded rows keep their category; only the auto-accept status rule is re-applied.
    changes = []
    rows.find_each do |row|
      category = if row.amazon_import_batch.source_sp_api?
        AmazonTaxCategorizer.for_transaction_breakdown(row.transaction_type, row.amount_type.to_s.split(" > "), row.amount_cents)
      else
        row.tax_category
      end
      status = AmazonImportRow.initial_status_for(category).to_s
      changes << [row, category, status] if category != row.tax_category || status != row.status
    end

    money = ->(list) { ActiveSupport::NumberHelper.number_to_currency(list.sum { |row, _, _| row.amount_cents } / 100.0) }
    puts "Checked #{rows.count} rows no one has reviewed (#{ENV["EMAIL"].presence || "all sellers"}). #{changes.size} would change."

    category_moves = changes.reject { |row, category, _| category == row.tax_category }.group_by { |row, category, _| [row.tax_category, category] }
    puts "Category changes:" if category_moves.any?
    category_moves.sort_by { |_, list| -list.size }.each do |(from, to), list|
      puts "  #{from} -> #{to}: #{list.size} #{"row".pluralize(list.size)} (#{money.call(list)})"
    end

    status_moves = changes.reject { |row, _, status| status == row.status }.group_by { |row, _, status| [row.status, status] }
    puts "Status changes:" if status_moves.any?
    status_moves.each do |(from, to), list|
      note = to == "accepted" ? "auto-categorized" : "back to Needs review"
      puts "  #{from} -> #{to}: #{list.size} #{"row".pluralize(list.size)} (#{note})"
    end

    if ENV["APPLY"] == "1"
      AmazonImportRow.transaction do
        changes.each { |row, category, status| row.update!(tax_category: category, status: status) }
        AmazonImportBatch.where(id: changes.map { |row, _, _| row.amazon_import_batch_id }.uniq).find_each(&:refresh_status!)
      end
      puts "Applied. Rows a person accepted or skipped were not changed."
    else
      puts "Dry run. Re-run with APPLY=1 to save these changes."
    end
  end
end

namespace :amazon do
  namespace :sandbox_seller do
    desc "Create the sandbox seller login if missing and restore its password and connection"
    task ensure: :environment do
      user = SandboxSeller.ensure_user!
      puts "Sandbox seller ready: #{user.email_address} (Amazon connection #{user.amazon_connection.selling_partner_id})."
    end

    desc "Delete the sandbox seller's synced and uploaded rows, sync history, and export inputs (keeps the login)"
    task reset: :environment do
      SandboxSeller.reset!
      puts "Sandbox seller data cleared. Sign in and sync a tax year to regenerate it."
    end
  end
end
