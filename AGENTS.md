# AGENTS.md

## Project Overview

Amazon Tax Pro is a small multi-tenant Rails app for Amazon seller tax prep. The app is **sync-first**: sellers create an account, connect their Amazon Seller Central account through the Selling Partner API (SP-API), and sync a tax year's financial transactions. Rows with a suggested category are auto-accepted; sellers only fix the Uncategorized rows on the per-year Review page, add cost of goods sold, then use the tax packet and TurboTax export. Uploading a settlement or 2025 transaction report CSV/TSV is a hidden fallback for sellers who can't connect, and synced data always wins over uploads.

`DESIGN.md` is the source of truth for product, UX, visual, and copy decisions; follow it and update it with any design change.

## Stack

- Ruby on Rails 8.1, Ruby 3.4.5 (pinned in `mise.toml`)
- SQLite (primary DB plus a Solid Queue DB at `storage/*_queue.sqlite3`)
- Puma, with Solid Queue running inside Puma when `SOLID_QUEUE_IN_PUMA` is set (`bin/dev` and Kamal set it)
- Rails 8 authentication generator (email/password; password reset is not enabled because there is no SMTP)
- `peddler` gem for Login with Amazon (LWA) and Finances API v2024-06-19
- Windows dev support: `tzinfo-data` plus `Gem.win_platform?` guards in `config/boot.rb` and `config/initializers/windows_template_glob.rb` (no-ops elsewhere)
- ERB views with app-wide inline CSS in `app/views/layouts/application.html.erb`; the site gate uses `app/views/layouts/gate.html.erb`

## Key Paths

- `DESIGN.md`: design source of truth (principles, IA, tokens, components, copy glossary, decision log).
- `config/routes.rb`: site gate, auth, sign-up, dashboard, Amazon connection/sync, Review, Sync history (`/amazon-imports`), tax packet, TurboTax export.
- `app/controllers/concerns/site_gate.rb`: shared-password gate (production, or `SITE_GATE=1`); 30-day signed cookie tied to the password.
- `app/controllers/concerns/authentication.rb`, `sessions_controller.rb`, `registrations_controller.rb`: user accounts.
- `app/controllers/user_accounts_controller.rb`: Profile & settings (`/account`): display name, business name (prefills TurboTax export), default tax year (used by `TaxYearContext` after params/session), password change at `PATCH /account/password` (signs out other sessions), and password-confirmed account + data deletion (`User#destroy_with_data!`).
- `app/controllers/amazon_connections_controller.rb`: SP-API OAuth (consent, Login URI, Redirect URI, disconnect).
- `app/controllers/amazon_syncs_controller.rb`: starts a tax-year sync; `new` is the "sync wins" confirmation that removes a year's uploaded rows (`User#remove_uploaded_rows!`) before syncing it.
- `app/controllers/concerns/tax_year_context.rb`: the app-wide tax year (`current_tax_year`, `tax_year_options`): `?year=` → session → defaults; reset on sign-in.
- `app/controllers/reviews_controller.rb` + `app/views/reviews/show.html.erb`: one Review page per tax year across all syncs and uploads (status tabs, category/import filters, 100-row pages).
- `app/controllers/amazon_import_rows_controller.rb`: row Accept/Save/Skip/Restore; redirects back to the filtered Review page.
- `app/models/amazon_sp_api.rb`: SP-API config, consent URL, LWA token exchange, Finances client.
- `app/models/amazon_connection.rb`: one per user; refresh token encrypted with Active Record Encryption.
- `app/models/amazon_transactions_sync.rb` + `app/jobs/amazon_transactions_sync_job.rb`: tax-year backfill via `listTransactions` (≤180-day windows, paginated, rate limited, deduped by `external_id`).
- `app/models/sandbox_seller.rb` + `app/models/sandbox_seller/`: the shared sandbox seller login, its fake Finances client, and the deterministic per-year transaction generator.
- `app/models/amazon_transaction_normalizer.rb`: API transaction → import rows (one per leaf breakdown, plus residual row).
- `app/models/amazon_tax_categorizer.rb`: category rules shared by the CSV importer and the API sync.
- `app/models/amazon_settlement_importer.rb`: Amazon CSV/TSV parsing (fallback upload).
- `app/models/amazon_import_row.rb`: tax categories, row statuses, review buckets (`REVIEW_STATUSES`), the auto-accept rule (`initial_status_for`), and seller-friendly `plain_label`s. `reviewed_at` is NULL until a person accepts or skips the row.
- `app/models/tax_year_status.rb`: per-year facts (review counts, synced?, uploaded rows, mixed sources, latest/active sync) shared by the dashboard, Review, and outputs.
- `app/models/pagination.rb` + `app/views/shared/_pagination.html.erb`: in-house pagination (no gem).
- `app/models/amazon_year_activity.rb`: signed yearly totals from accepted rows (credits net; gross receipts; after-fee revenue reference), shared by the dashboard, tax packet, and TurboTax export.
- `app/models/turbo_tax_export.rb`: TXF, audit CSV, and readiness warnings; counts accepted rows only, like the tax packet.
- `app/models/build_info.rb`: build ID shown in the app layout footer (first 8 characters of `KAMAL_VERSION` in deployed containers, git `HEAD` locally, reread on every request in development).
- `app/helpers/application_helper.rb`: `money`, `review_pill`, `sync_pill`, `nav_link`, `page_path`, `sync_year_range`.
- `app/views/shared/`: year switcher, pagination, mixed-source warning partials; `app/views/amazon_syncs/_sync_action.html.erb` picks the next step (upload / connect / reconnect / progress / Sync YEAR).
- `app/views/dashboard/index.html.erb` + `_amazon_connection.html.erb`: sync-first dashboard and connect/sync card.
- `app/views/amazon_import_batches/`: Sync history (index), run details (show, refreshes while syncing), upload fallback (new); uploads can be deleted, sync runs can't.
- `app/views/tax_packets/show.html.erb`, `app/views/turbo_tax_exports/show.html.erb`: outputs.
- `lib/tasks/amazon_tax.rake`: `amazon:recategorize`.

## Tenancy

- All Amazon data (`amazon_import_batches`, `amazon_import_rows`, `turbo_tax_export_inputs`, `amazon_connections`) belongs to a user. Always scope queries through `Current.user`.
- Legacy `accounts`/`expenses`/`invoices`/`transactions` tables are unused by the UI.

## Credentials

Edit with `bin/rails credentials:edit`:

```yaml
site_password: "shared gate password"
active_record_encryption: { primary_key: ..., deterministic_key: ..., key_derivation_salt: ... }
amazon_sp_api:
  application_id: amzn1.sp.solution.xxxx
  lwa_client_id: amzn1.application-oa2-client.xxxx
  lwa_client_secret: xxxx
  sandbox_lwa_client_id: amzn1.application-oa2-client.xxxx
  sandbox_lwa_client_secret: xxxx
  sandbox_refresh_token: Atzr|xxxx
  draft: true   # adds version=beta to the consent URL until the app is published
```

## SP-API App Registration

- Solution Provider Portal: public developer profile → role **Finance and Accounting** only → app (starts in Draft).
- Login URI: `https://amazontaxpro.com/amazon/connection/login`
- Redirect URI: `https://amazontaxpro.com/amazon/connection/callback`
- Unlisted public apps allow 25 seller authorizations; up to 10 self-authorizations for testing.
- Local dev cannot receive the HTTPS redirect. Self-authorize the app in Seller Central, then attach the refresh token in the console:
  `AmazonConnection.connect!(user: User.find_by(email_address: "..."), selling_partner_id: "...", refresh_token: "Atzr|...")`
- **The connecting seller must be the primary user of a Professional selling account.** Individual-plan accounts cannot authorize apps; Seller Central answers with "You must be the primary user of a Professional selling account to take advantage of apps." This is an Amazon account restriction, not an app bug.
- Development uses the static sandbox (`https://sandbox.sellingpartnerapi-na.amazon.com`) and the three `sandbox_*` credentials above. Create a Sandbox app in Solution Provider Portal and use View sandbox credentials and Action → Create Token; seller authorization is not required. The development Connect Amazon action creates a per-user sandbox connection, and the refresh token is read directly from credentials. Production continues to use seller authorization and the production LWA credentials.
- Sandbox sync sends the fixed `listTransactions` sample parameters from Amazon's API model and imports one canned response; its returned `nextToken` is a placeholder. The selected tax year does not change the sample data. Sample rows keep Amazon's original posted dates, so select that year for tax outputs.

## Sandbox Seller

- A shared team login in every environment (including production, behind the site gate) with fake but realistic data for "Summit Trail Goods LLC":
  - Email: `sandbox@amazontaxpro.com`
  - Password: `sandbox-seller-2026`
- The account is created on its first sign-in (or with `bin/rails amazon:sandbox_seller:ensure`) and comes pre-connected to Amazon as seller `A3SBX7TRAILGDS`. Sign-up with that email is blocked; its password can't be changed and the account can't be deleted.
- Clicking **Sync YEAR** runs the normal sync job, normalizer, and categorizer, but `AmazonTransactionsSync` swaps in `SandboxSeller::FinancesClient`, which answers `listTransactions` from `SandboxSeller::TransactionGenerator` (≈1,000 transactions / 5,000 rows per year, paginated, no rate-limit delay). No Amazon credentials or network calls are involved, and this takes precedence over the development static sandbox.
- Data is deterministic per tax year, so re-syncing only adds missing rows. Each year has a few Uncategorized rows for Review. Sync runs are flagged `sandbox_sample`.
- Start over with `bin/rails amazon:sandbox_seller:reset` (keeps the login and connection; deletes rows, sync history, and export inputs).

## Deploying

- Kamal builds and tags images by git commit, so **credential changes must be committed before `kamal deploy`**; otherwise production keeps running the previously committed `config/credentials.yml.enc`.
- Verify which values production actually loaded with:
  `kamal app exec --reuse 'bin/rails runner "puts Rails.application.credentials.amazon_sp_api[:application_id].to_s.first(18)"'`

## Security and Compliance

- Rotate the LWA client secret every 180 days (Amazon gives a 7-day overlap); update `amazon_sp_api.lwa_client_secret`.
- Never log tokens or OAuth codes (see `config/initializers/filter_parameter_logging.rb`).
- Amazon refresh tokens and row `raw_data` are encrypted with Active Record Encryption.
- Users can delete their account at `/account`, which removes their connection, sync runs, uploads, rows, and export inputs.
- Only financial data is requested (no PII roles). Disconnecting deletes the stored refresh token; sellers should also revoke the app in Seller Central → Manage Your Apps.
- Complete Amazon's Data Protection Policy self-assessment before publishing the app.

## Development Server

- Do not start the Rails development server for this project.
- The user runs it with `bin/dev` (or `mise run dev`), which binds Rails to `0.0.0.0:3002` by default and runs Solid Queue in Puma.
- If the development server appears to be unavailable when it is needed for verification, remind the user to run `bin/dev` instead of starting it yourself.

## Useful Commands

- Tool install: `mise install`
- Setup: `mise run setup` (bundle install + `bin/rails db:prepare`)
- Boot + whitespace check: `mise run check`
- Boot check: `bundle exec rails runner 'puts "rails boot ok"'`
- Database migrations: `bin/rails db:migrate` (or `mise run migrate`); roll back with `bin/rails db:rollback:primary` (multi-database app)
- Re-apply category rules to rows no one has reviewed: `bin/rails amazon:recategorize` (dry run; add `APPLY=1` to save, `EMAIL=...` for one seller). Run it after changing `AmazonTaxCategorizer` rules.
- Categorizer tests: `mise exec -- ruby test/amazon_tax_categorizer_test.rb`
- Year totals and TXF line tests (uses the test DB; run `bin/rails db:test:prepare` first): `mise exec -- ruby test/amazon_year_activity_test.rb`
- Rails console: `bin/rails console`
- Whitespace check: `git diff --check`

## Testing Notes

- Sign-in is rate limited (10 per 3 minutes). Back-to-back runner scripts that each sign in can hit it; the symptom is a silent 302 to the sign-in page.
- `test/` holds standalone Minitest files: `amazon_tax_categorizer_test.rb` (category rules, no Rails) and `amazon_year_activity_test.rb` (loads Rails in the test env; totals, TXF lines, plain labels). There is no `bin/rails test` setup (`test_helper`) yet.
- When changing code, use the Rails boot check and focused manual verification (e.g. `bin/rails runner` scripts using `ActionDispatch::Integration::Session`; set `ActionController::Base.allow_forgery_protection = false` and `ActiveJob::Base.queue_adapter = :test` in the script so POSTs work and no real sync jobs run).
- Avoid treating generated or local SQLite files under `storage/` as source changes unless the user explicitly asks for database state changes.

## Implementation Notes

- Follow `DESIGN.md` for UI, IA, and copy (glossary and banned terms included); record new design decisions in its decision log.
- Prefer the existing Rails/ERB style and shared CSS variables in the layout; no inline styles, no JS.
- Guidance and copy should reflect the sync-first flow: connect Amazon and sync a tax year, fix the rows we couldn't categorize, add cost of goods sold, then use the tax packet or TurboTax export. Upload is only mentioned as a fallback.
- Year-scoped pages (dashboard, Review, tax packet, TurboTax export) use `current_tax_year` and pass `year:` in links between them.
