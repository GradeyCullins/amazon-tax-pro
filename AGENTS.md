# AGENTS.md

## Project Overview

Amazon Tax Pro is a small multi-tenant Rails app for Amazon seller tax prep. Sellers create an account, connect their Amazon Seller Central account through the Selling Partner API (SP-API), and sync a tax year's financial transactions. Manual upload of settlement or 2025 transaction report CSV/TSV files remains as a fallback. Users review and categorize rows, then generate tax packet and TurboTax export views.

## Stack

- Ruby on Rails 8.1, Ruby 3.4.5 (pinned in `mise.toml`)
- SQLite (primary DB plus a Solid Queue DB at `storage/*_queue.sqlite3`)
- Puma, with Solid Queue running inside Puma when `SOLID_QUEUE_IN_PUMA` is set (`bin/dev` and Kamal set it)
- Rails 8 authentication generator (email/password; password reset is not enabled because there is no SMTP)
- `peddler` gem for Login with Amazon (LWA) and Finances API v2024-06-19
- ERB views with app-wide inline CSS in `app/views/layouts/application.html.erb`; the site gate uses `app/views/layouts/gate.html.erb`

## Key Paths

- `config/routes.rb`: site gate, auth, sign-up, dashboard, Amazon connection/sync, imports, tax packet, TurboTax export.
- `app/controllers/concerns/site_gate.rb`: shared-password gate (production, or `SITE_GATE=1`); 30-day signed cookie tied to the password.
- `app/controllers/concerns/authentication.rb`, `sessions_controller.rb`, `registrations_controller.rb`: user accounts.
- `app/controllers/user_accounts_controller.rb`: account page (`/account`) with password-confirmed account + data deletion (`User#destroy_with_data!`).
- `app/controllers/amazon_connections_controller.rb`: SP-API OAuth (consent, Login URI, Redirect URI, disconnect).
- `app/controllers/amazon_syncs_controller.rb`: starts a tax-year sync.
- `app/models/amazon_sp_api.rb`: SP-API config, consent URL, LWA token exchange, Finances client.
- `app/models/amazon_connection.rb`: one per user; refresh token encrypted with Active Record Encryption.
- `app/models/amazon_transactions_sync.rb` + `app/jobs/amazon_transactions_sync_job.rb`: tax-year backfill via `listTransactions` (≤180-day windows, paginated, rate limited, deduped by `external_id`).
- `app/models/amazon_transaction_normalizer.rb`: API transaction → import rows (one per leaf breakdown, plus residual row).
- `app/models/amazon_tax_categorizer.rb`: category rules shared by the CSV importer and the API sync.
- `app/models/amazon_settlement_importer.rb`: Amazon CSV/TSV parsing (fallback upload).
- `app/models/amazon_import_row.rb`: tax categories, row statuses, and accepted tax totals.
- `app/views/dashboard/index.html.erb` + `_amazon_connection.html.erb`: home dashboard and connect/sync card.
- `app/views/amazon_import_batches/`: upload page, batch list, row review page (shows sync progress).
- `app/views/tax_packets/show.html.erb`, `app/views/turbo_tax_exports/show.html.erb`: outputs.

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
- `listTransactions` is not a grantless operation, so even the static sandbox (`https://sandbox.sellingpartnerapi-na.amazon.com`) needs a refresh token from an authorized account.

## Deploying

- Kamal builds and tags images by git commit, so **credential changes must be committed before `kamal deploy`**; otherwise production keeps running the previously committed `config/credentials.yml.enc`.
- Verify which values production actually loaded with:
  `kamal app exec --reuse 'bin/rails runner "puts Rails.application.credentials.amazon_sp_api[:application_id].to_s.first(18)"'`

## Security and Compliance

- Rotate the LWA client secret every 180 days (Amazon gives a 7-day overlap); update `amazon_sp_api.lwa_client_secret`.
- Never log tokens or OAuth codes (see `config/initializers/filter_parameter_logging.rb`).
- Amazon refresh tokens and row `raw_data` are encrypted with Active Record Encryption.
- Users can delete their account at `/account`, which removes their connection, batches, rows, and export inputs.
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
- Database migrations: `bin/rails db:migrate` (or `mise run migrate`)
- Rails console: `bin/rails console`
- Whitespace check: `git diff --check`

## Testing Notes

- There is currently no `test/` or `spec/` directory in this repository.
- When changing code, use the Rails boot check and focused manual verification (e.g. `bin/rails runner` scripts using `ActionDispatch::Integration::Session`) unless a test suite is added.
- Avoid treating generated or local SQLite files under `storage/` as source changes unless the user explicitly asks for database state changes.

## Implementation Notes

- Prefer the existing Rails/ERB style and shared CSS variables in the layout.
- Keep UI changes consistent with the current bold card, table, and button styling.
- Amazon import guidance should reflect the actual flow: connect Amazon and sync a tax year (or upload a Seller Central report as a fallback), review categories, then use the tax packet or TurboTax export.
