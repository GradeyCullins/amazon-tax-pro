# AGENTS.md

## Project Overview

Amazon Tax Pro is a small Rails app for Amazon seller tax prep. It imports Amazon settlement or 2025 transaction report CSV/TSV files, lets users review and categorize rows, and generates tax packet and TurboTax export views.

## Stack

- Ruby on Rails 8.1
- SQLite
- Puma
- ERB views with app-wide inline CSS in `app/views/layouts/application.html.erb`

## Key Paths

- `config/routes.rb`: root dashboard, Amazon imports, tax packet, and TurboTax export routes.
- `app/models/amazon_settlement_importer.rb`: Amazon CSV/TSV parsing and category suggestions.
- `app/models/amazon_import_row.rb`: tax categories, row statuses, and accepted tax totals.
- `app/views/dashboard/index.html.erb`: home dashboard.
- `app/views/amazon_import_batches/new.html.erb`: Amazon upload page.
- `app/views/amazon_import_batches/show.html.erb`: import row review page.
- `app/views/tax_packets/show.html.erb`: tax packet summary.
- `app/views/turbo_tax_exports/show.html.erb`: TurboTax export and manual COGS inputs.

## Development Server

- Do not start the Rails development server for this project.
- The user runs it with `bin/dev`, which binds Rails to `0.0.0.0:3002` by default.
- If the development server appears to be unavailable when it is needed for verification, remind the user to run `bin/dev` instead of starting it yourself.

## Useful Commands

- Boot check: `bundle exec rails runner 'puts "rails boot ok"'`
- Database migrations: `bin/rails db:migrate`
- Rails console: `bin/rails console`
- Whitespace check: `git diff --check`

## Testing Notes

- There is currently no `test/` or `spec/` directory in this repository.
- When changing code, use the Rails boot check and focused manual verification unless a test suite is added.
- Avoid treating generated or local SQLite files under `storage/` as source changes unless the user explicitly asks for database state changes.

## Implementation Notes

- Prefer the existing Rails/ERB style and shared CSS variables in the layout.
- Keep UI changes consistent with the current bold card, table, and button styling.
- Amazon import guidance should reflect the actual flow: upload Seller Central report, normalize rows, review categories, then use the tax packet or TurboTax export.
