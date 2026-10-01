# Amazon Tax Pro Design

This file is the source of truth for Amazon Tax Pro's product, UX, visual, and copy decisions.
Update it in the same change as any design change. If the code and this file disagree, either fix
the code or record the new decision here (see the [decision log](#16-decision-log)).

## 1. Product principles

1. **Sync first.** The main path is **Connect Amazon → Sync a tax year → Fix what we couldn't
   categorize → Add cost of goods sold and export**. Each page's main call to action moves the
   seller one step along that path.
2. **Tax-year centric.** Sellers think in tax years, not syncs or files. The whole app shares one
   selected year. Every year-scoped page shows that year and has the same year switcher.
3. **Automate, then handle exceptions.** Any row that gets a suggested category counts right away
   (it's *auto-categorized*). People only have to act on rows we couldn't categorize, but they can
   still change, skip, or restore any row. Copy nudges sellers to spot-check before filing.
4. **Upload is a fallback.** It's for sellers who can't connect: an Individual selling plan, not
   the account's primary user, or the connection is unavailable. Upload never appears in the nav
   or a page header. Sellers reach it through "Can't connect? Upload a report" links and the
   "Amazon connection unavailable" state.
5. **Sync wins.** Each year has one source of data. Uploads skip rows dated in synced years.
   Syncing a year that already has uploads first asks the seller to remove those uploaded rows.
6. **Outputs only count what counts.** The tax packet, TXF, and audit CSV include accepted rows
   only, meaning auto-categorized plus accepted by a person. Pages say plainly what's left out
   and why.
7. **Earn trust.** We request read-only financial data. Tokens and raw rows are encrypted,
   disconnecting and deleting the account each take one step, and we always say "review with a
   tax professional before filing." We don't give tax advice.

## 2. Information architecture

### Navigation

The nav order is: brand (dashboard) · **Review** · **Tax Packet** · **TurboTax Export** ·
account email · Sign out.

- The Review link carries a count pill with the number of rows that need review in the
  current year. The pill is hidden when the count is zero.
- Sync history, upload, and account pages are reached from inside pages, not from the nav.

| Page | Path | Purpose | Primary action |
|---|---|---|---|
| Dashboard | `/` | Amazon connection, the year's status, and what needs attention | The next step for the current state (see below) |
| Review | `/review` | All of the year's rows, opening on *Needs review* | Accept / Save / Skip / Restore per row |
| Tax Packet | `/tax-packet` | Year totals by category and an audit trail of counted rows, to share with a tax professional | None (read-only); links to Review and TurboTax Export |
| TurboTax Export | `/turbotax-export` | Cost of goods sold inputs, Schedule C preview, readiness, downloads | Download TXF |
| Sync history | `/amazon-imports` | Every sync run and upload | Sync the current year |
| Run details | `/amazon-imports/:id` | Progress and what one sync or upload added | "Review YEAR" links; Delete this upload (uploads only) |
| Sync confirmation | `/amazon/syncs/new` | Confirm removing uploaded rows before syncing their year | Remove N uploaded rows and sync YEAR |
| Upload | `/amazon-imports/new` | Fallback upload of a Seller Central report | Upload report |
| Profile & settings | `/account` (nav shows the display name, else the email) | Display name, business name (prefills new TurboTax export years), default tax year, connection status, password change (signs out other sessions), account deletion | Save profile |
| Sign up / Sign in | `/sign-up`, `/session/new` | Email/password accounts; sign-up leads to Connect Amazon | Create account / Sign in |
| Gate | `/unlock` | Shared-password gate in production (or with `SITE_GATE=1`) | Unlock |

The `/amazon-imports` path predates the pivot and stays so old links keep working. The UI never
says "imports".

### Next-step order

`amazon_syncs/_sync_action` picks the one next step for getting a year's data in:

1. Amazon not configured → **Upload a report**
2. Not connected → **Connect Amazon**
3. Connection needs reauthorization → **Reconnect Amazon**
4. A sync is running → **View sync progress** (secondary button)
5. The year can be synced (the current year and the 3 before it) → **Sync YEAR**
6. Otherwise → a note naming the years Amazon sync covers

Once data is in, the order is Review (if rows need a category), then cost of goods sold, then
export. The dashboard's "What needs attention" checklist shows these steps in this order.

### The tax year

`TaxYearContext#current_tax_year` resolves the year in this order:

1. a valid `?year=` on any request (2000 through the current year); the choice is also saved in
   the session
2. the year saved in the session
3. the seller's **default tax year** from Profile & settings, if they set one
4. last year, if the seller has rows dated in it
5. the latest year with rows
6. last year

More rules:

- The session year resets on sign-in.
- Rows count toward the year of their posted date. Uploaded dates outside 2000 through the current year
  (a typo like `20255`) import as undated: they never count toward a year, and run details says how many.
- The switcher lists every year that can be synced plus every year with rows, newest first.
- Switching submits a GET to the current path with only `year`, which also resets filters and
  pagination.
- Year-scoped pages are the Dashboard, Review, Tax Packet, and TurboTax Export. The h1 on these
  pages is the nav label plus the year ("Review 2025", "Tax Packet 2025"). The dashboard is the
  exception: its h1 has no year, so it prefixes each stat label with the year instead.
- Links between year-scoped pages pass `year:`, so a second browser tab on another year can't
  silently switch this one.
- The **Sync YEAR** button always syncs the page's selected year. There is one year control per
  page, never a second year picker.

### Auto-refresh

`<meta http-equiv="refresh" content="5">` is only used on pages where nobody is filling in a form:

- the dashboard, while the current year's sync runs
- run details, while that sync is active

Review never auto-refreshes, because it has row forms. It shows a "Syncing YEAR" banner with a
link to the progress page instead.

## 3. Review model

| Review status | Stored as | Pill | Counted in outputs | Row actions |
|---|---|---|---|---|
| Needs review | `pending` | orange (`warn`) | No | Accept · Skip |
| Auto-categorized | `accepted`, `reviewed_at` NULL | green (`good`) | Yes | Save · Skip |
| Accepted | `accepted`, `reviewed_at` set | green (`good`) | Yes | Save · Skip |
| Skipped | `skipped` | gray | No | Restore |

- New rows from syncs and uploads follow one rule: Uncategorized → Needs review; any other
  category → Auto-categorized.
- Accepting a row as Uncategorized is refused with "Choose a tax category before accepting, or
  skip the row."
- Row actions redirect back to the same filtered and paginated Review URL.
- Each row leads with a plain-language label (`AmazonImportRow#plain_label`: "Referral fee",
  "Customer refund", "Shipping charge"). Amazon's own wording, the order, and the source row sit in a
  collapsed "Amazon details" disclosure, with a link to every row from the same order.
- Review filters: status tabs, search (description, order ID, Amazon type fields, or row number),
  category, amount range by size (|amount|), and sort (oldest, newest, largest amount). "Largest
  amount first" is the spot-check view for auto-categorized rows.
- **Totals are signed.** `AmazonYearActivity` sums accepted rows with Amazon's signs, so credits net
  against their category (a refunded fee lowers fees). The tax packet shows expenses and withheld
  tax as positive totals. Positive shipping is gross receipts; shipping Amazon charged the seller
  goes on Other business expenses. The audit trail shows each row's signed amount.
- **Gross receipts vs after-fee revenue.** Gross receipts (sales + shipping credits) is the Schedule C
  figure. After-fee revenue (gross receipts minus refunds, Amazon and FBA fees, ads, and shipping
  charges) is a planning figure only: it's labeled "reference only" on the export and never becomes
  a TXF line.
- Transfers, marketplace-withheld tax, and reserves are counted rows, but they're left out of
  Schedule C lines ("not on Schedule C").
- Category rule fixes reach existing rows through `bin/rails amazon:recategorize`. It's a dry run
  unless `APPLY=1`, and it only touches rows no person has reviewed.

## 4. Visual language

"Amazon-flavored neo-brutalism":

- **Palette.** Ink `#131921` (Amazon's header navy-black) with white and gray surfaces, and one
  accent: Amazon orange `#ff9900`. The only other colors are status colors.
- **Page.** A 34px grid-paper background and an 8px orange bar across the top of every page.
- **Edges.** Thick ink borders (3–4px) and hard offset shadows with no blur: 7px on cards, 4px on
  buttons, callouts, and flashes. Buttons, nav links, pills, and tabs are rounded pills.
- **Tilt.** Small rotations give a hand-placed sticker-board feel:
  - nav −0.35°
  - stat cards cycle through −0.4°, 0.5°, −0.2°, 0.3°
  - auth card −0.3°
  - gate vault −1.2° and its sticker 8°
  - the nav loses its tilt under 720px
- **Big serif numbers.** Headlines and stat values use a heavy serif. Stat values are orange.

Before 2026-06-08 the app used a multicolor palette. Commit `b4b2551` moved it to the Amazon
palette. Keep orange as the only accent.

## 5. Tokens

All tokens are in `:root` in `app/views/layouts/application.html.erb`.

| Token | Value | Use |
|---|---|---|
| `--ink` | `#131921` | Text, borders, shadows, table headers, brand pill |
| `--paper` | `#f3f3f3` | Page background under the grid |
| `--surface` | `#ffffff` | Cards, inputs, secondary buttons |
| `--surface-soft` | `#f7f7f7` | Zebra rows, list items, alternate stat cards |
| `--surface-muted` | `#e3e6e6` | Neutral pills, callouts, flashes, hover rows |
| `--border` | `#131921` | Every border (same as ink) |
| `--primary` | `#ff9900` | Primary buttons, links, stat values, warn pills, focus outline, top bar |
| `--primary-dark` | `#e47911` | Primary button hover |
| `--primary-soft` | `#ffe2b3` | `.callout.warn`, connect-card corner |
| `--good` | `#c7f0d0` | Green pills: counted, done, connected, finished |
| `--bad` | `#f4b4b4` | Red pills: failed, needs reconnect; danger buttons |
| `--bad-dark` | `#ee8f8f` | Danger button hover |
| `--muted` | `#565959` | `.muted` labels, `.note` text |
| `--shadow` | `7px 7px 0 var(--ink)` | Cards, nav |
| `--small-shadow` | `4px 4px 0 var(--ink)` | Buttons, callouts, flashes, hover lift |

**Status colors.**

| Status | Color | Pill class | Means |
|---|---|---|---|
| good | green (`--good`) | `.pill.good` | Counted, done, connected, finished |
| warn | orange (`--primary`) | `.pill.warn` | Needs action or in progress |
| bad | red (`--bad`) | `.pill.bad` | Failed or needs reconnect |
| neutral | gray (`--surface-muted`) | `.pill` | Doesn't count or is informational |

The connect card fills its lower-right corner with a 135° gradient: white to 70%, then
`--primary-soft`.

New colors become tokens. Don't hardcode hex values in rules.

## 6. Typography

- **Display face:** `ui-serif, Georgia, "Times New Roman", serif` at weight 1000, line-height .95.
  It's used for:

  | Element | Size |
  |---|---|
  | h1 | `clamp(44px, 10vw, 86px)` |
  | auth-card h1 | `clamp(40px, 8vw, 64px)` |
  | gate h1 | `clamp(38px, 9vw, 54px)` |
  | h2 | `clamp(25px, 4vw, 38px)` |
  | `.value` (stat numbers, orange) | `clamp(28px, 7vw, 42px)` |
  | `.guide-step` numerals | — |

- **Body face:** system sans (`ui-sans-serif, system-ui, …`), 16px, weight 650.
  - Labels and links use weight 950. Buttons use weight 1000.
  - Guide-card h3s use the sans face at 19px.
- **Text styles:**
  - `.guide-copy` is the standard paragraph inside cards: 15px, weight 750, ink.
  - `.note` is a secondary hint under a component: 14px, muted.
  - `.muted` has two jobs:
    - an uppercase 12px micro-label, used for stat labels and metadata
    - inside `.page-header`, a sentence-case 15px ink subtitle

## 7. Layout

- **Shell.** `.shell` is centered with a max width of 1240px and 24px padding (16px under 720px).
- **Page header.** `.page-header` puts the h1 and its `.muted` subtitle on the left, and
  `.actions` (year switcher, then secondary links) on the right. It stacks under 720px.
- **Grids.**
  - `.cards`: auto-fit columns, at least 200px each
  - `.guide-grid`: at least 230px per column
  - `.dashboard-main`: 2fr / 1fr, one column under 720px
- **Spacing.**
  - 34px under the nav
  - 24px under the page header
  - 18px between cards (`.grid` gap and `.section` margin-top)
  - 14–18px inside cards
- **Card margins.** `.card > :first-child` and `.card > :last-child` lose their outer margins, so
  cards never need spacing hacks.

## 8. Components

**Nav.** Pill links. The brand link is an ink pill. Links 2–4 are muted, white, and orange, in
that order.
- The current page (`aria-current="page"`) sits lifted with the small shadow.
- `.nav-count` is an ink count bubble inside the Review link.

**Cards.**

| Card | Built from | Notes |
|---|---|---|
| Card | `.card` | White panel with a 4px ink border, 8px radius, and the big shadow. Scrolls wide tables horizontally. |
| Stat card | `.card` with a `.muted` label and a `.value` | Used in `.cards` grids. Labels on year-scoped pages start with the year. |
| Guide card | `.card.guide-card` with a `.guide-step` | Numbered steps for "How it works". The step is an ink circle with a serif numeral. |
| Connect card | `.card.connect-card` | The Amazon card on the dashboard and run details. `.connect-meta` holds its pills. |
| Auth card | `.card.auth-card` | Narrow (520px), tilted card for sign-in and sign-up. |
| Empty state | `.empty-state` | Says what's missing and offers the one next step. Can be a card or sit inside one. |

**Buttons.** Use `link_to … class: "button"` for navigation and `button_to` for anything that
changes state.

| Class | Use |
|---|---|
| `.button` | Primary: orange. Use at most one per area. |
| `.button.secondary` | White, for other actions. |
| `.button.small` | Inside tables, filters, and pagination. |
| `.button.danger` | Red. Destructive actions only, always behind `confirm()` or a confirmation page. |

**Pills** (`.pill`, `.good` / `.warn` / `.bad`).
- Always choose colors through the helpers: `review_pill(review_status)` and
  `sync_pill(batch)`.
- Sync runs: Queued and Syncing are orange, Finished is green, Failed is red. Uploads show a
  gray "Uploaded".
- Dashboard checklist: Done and Ready are green, To do and Syncing are orange, Failed is red,
  Waiting / Not yet / Upload are gray.
- Source pills (Amazon sync / Upload) are always gray.

**Callouts and flashes.**
- `.callout` is neutral: errors from Amazon, the sandbox notice.
- `.callout.warn` (orange-soft) needs attention: mixed sources, a sync in progress, rows not
  included yet, no rows for the year.
- `.callout .actions` adds spacing for buttons inside a callout.
- `.flash` is the notice after an action. `.flash.alert` is an error.

**Forms.**
- `.form-row` stacks a label over a field (max 520px). `.inline-form` puts controls in one row.
- `.row-form` is the per-row category form on Review. It doesn't wrap on desktop and wraps
  under 720px.
- Inputs and selects have a 3px ink border, a soft shadow, and a 4px orange focus outline.

**Tables (`.tight`).**
- Ink header row, 3px ink row rules, zebra striping, and hover highlight.
- Headers use `scope="col"`. Checklist row labels use `th scope="row"`.

**Shared partials.**

| Partial | Locals | What it does |
|---|---|---|
| `shared/_tax_year_switcher` | none | Year select plus a small "Switch" button, placed in `.page-header .actions` |
| `shared/_pagination` | `pagination:` | "Showing a–b of n" with Previous/Next (`rel` set) and a "Page x of y" pill |
| `shared/_mixed_source_warning` | `year_status:` | `.callout.warn` for a synced year that also has uploaded rows. Links to the sync confirmation, or to Sync history when the year can't be synced. |
| `amazon_syncs/_sync_action` | `year:` | The next-step button (see [Next-step order](#next-step-order)) |
| `dashboard/_amazon_connection` | `connection:`, `active_sync:`, `year_status:` | The connect card in each state: unavailable, not connected, needs reconnect, syncing, connected |

Pagination is 100 rows per page.

**Review controls.**
- `.tabs` are status filter links with `.tab-count`. The current tab is filled ink.
- `.filters` holds the `.review-search` form (search, category, amount range, sort), the
  amount hint, and the "Only rows from <sync or upload>" note. Bad amounts show a `.callout.warn`.
- `.row-details` is a `<details>` disclosure inside a table cell, with a `dl` of Amazon fields.

**"What needs attention" checklist.** A `.tight` table with four rows: Amazon sync, Review, Cost
of goods sold, Export. Each row has a pill and one sentence with a link.

## 9. Gate page

`app/views/layouts/gate.html.erb` is its own layout with a duplicated subset of the tokens.

- **Background.** An ink radial gradient with 10% orange diagonal stripes, plus a 10px fixed
  orange top bar.
- **Vault card.** White, with a 5px ink border and a double offset shadow (orange, then ink),
  rotated −1.2°.
- **Decoration.**
  - an orange "Private beta" sticker, rotated 8°
  - a CSS-only padlock (`.lock`)
  - a huge "AMAZON TAX PRO · PRIVATE BETA" ticker at 8% white, drifting on a 40s loop. It
    stops under `prefers-reduced-motion` and is `aria-hidden`.
- **Button.** It presses *in* on hover (translates 3px, shadow shrinks), unlike the app's lift.
- **Alert flash.** Red on the gate.

Keep the gate's token values in sync with the app's.

## 10. Motion and interaction

- **Hover lift.** Nav links and buttons hover with `translate(-2px, -2px) rotate(-1deg)` and the
  small shadow, `.12s ease`. The current nav page stays lifted without rotation.
- **No JavaScript.** No JS, no Turbo, no CSS framework. Full page loads and plain forms.
- **Destructive actions.**
  - `.button.danger` with `onsubmit="return confirm(…)"`: disconnect, delete upload, delete
    account.
  - A dedicated confirmation page when the consequences need explaining: removing uploaded rows
    before a sync. It lists what will be removed.
- **After actions.** Row actions return to the same filtered page. Starting a sync returns to the
  dashboard, which shows progress.

## 11. Responsive

**Under 720px:**
- The shell padding drops to 16px.
- The nav loses its tilt, and its links flex to fill rows.
- The page header stacks, and `.actions` go full width with buttons flexing.
- `.dashboard-main` and `.guide-grid` become one column.
- Tables get a 640px minimum width and scroll inside their card.
- Inline forms stretch, and row forms wrap.

**Under 460px:**
- Stat cards become one column.
- Every button is full width.

## 12. Content and voice

### Voice

- Plain, direct, second person, short sentences. Say what happened and what to do next.
- Use "we" for what the app does ("We categorize every Amazon transaction for you").
- Present Amazon's limits as Amazon's ("Amazon only allows this on a Professional selling plan").
- Tax caution: "Review with a tax professional before filing." Never give tax advice.
- Empty states say what's missing and offer one next step.

### Glossary

| Say | Meaning | Don't say (in the UI) |
|---|---|---|
| Amazon sync, sync | Pulling a tax year of transactions from Amazon | SP-API sync, auto-import, import |
| Connect / Reconnect Amazon | Approving the app in Seller Central | authorize SP-API, OAuth, LWA |
| Tax year | A calendar year (Amazon's boundaries are Pacific time) | period |
| Row | One categorized amount; one transaction can make several rows | settlement row, line item |
| Review | The per-year page, and the act of checking rows | Imports, queue |
| Needs review | A row we couldn't categorize | pending |
| Auto-categorized | A counted row no person has touched | auto-accepted |
| Accepted | A counted row a person accepted or changed | reviewed |
| Skipped | A row a person left out of totals | rejected, ignored |
| Counted rows | Auto-categorized plus Accepted | |
| Sync history | The list of sync runs and uploads | Imports, import batches |
| Upload, uploaded report | The fallback | Amazon file, import |
| Seller Central report, settlement report | Amazon's report names, used only on the upload page | |
| Cost of goods sold | Inventory costs entered on the export page ("COGS" only in tight headings) | |

### Formatting

- **Money.** Use `money(cents)`, which gives `$1,234.56` and `-$12.34`.
- **Counts.** Always use thousands separators: `pluralize(number_with_delimiter(n), "row")`.
- **Dates.** Posted dates in tables are ISO (`2025-03-01`). Timestamps use
  `l(time, format: :short)`.
- **Year ranges.** Use an en dash: `2023–2026` (`sync_year_range`).
- **Names.** Sync runs are "Amazon sync · 2025", with a middle dot. Uploads keep their filename.
- **Case.**
  - Title case for nav labels and the h1s that match them ("Tax Packet 2025").
  - Sentence case for everything else: other headings, buttons, labels, pills.
- **Buttons.** Start with a verb and be specific: "Sync 2025", "Connect Amazon",
  "Remove 6,580 uploaded rows and sync 2025", "Save cost of goods sold".
- **Flash messages.** Say what happened and what it means: "Skipped. That row won't count toward
  your totals." / "Accepted as Amazon fees."

### Amazon's requirements and limits

| Fact | How to say it, and where |
|---|---|
| Professional selling plan and primary user | Shown on sign-up, the connect card, and "How it works". Individual-plan sellers are pointed to upload. |
| Sync range | The current year and the 3 before it (`AmazonTransactionsSync::YEARS_OFFERED`). Name the range with `sync_year_range`. |
| Year boundaries and lag | Calendar year in Pacific time. Amazon can lag up to 48 hours. Re-syncing only adds new transactions and keeps reviews. |
| Rate limits | "A full year can take a few minutes." |
| Sandbox (development only) | A callout explains that sample data keeps Amazon's fixed dates whatever year is synced. |
| Sandbox seller (all environments) | A callout on the connect card says you're signed in as the sandbox seller and syncs use built-in sample transactions, not Amazon. Profile & settings replaces the password and delete forms with a note that it's a shared team login. |

## 13. Accessibility

- **Focus.** Inputs and selects get a 4px orange outline with a 2px offset.
- **Current page.** `aria-current="page"` marks the current nav link and filter tab, styled with
  the lift and an ink fill so color isn't the only cue.
- **Labels.**
  - Status is never shown by color alone: pills always have text.
  - The nav count has screen-reader text: "rows need review".
  - Row category selects have `aria-label="Tax category"` and unique ids.
  - Tab and pagination `nav`s have `aria-label`s.
- **Tables.** Every table header has a `scope`.
- **Motion.** The gate ticker is `aria-hidden` and stops for `prefers-reduced-motion`.

## 14. Implementation conventions

- **Where CSS lives.** App CSS is the `<style>` block in `app/views/layouts/application.html.erb`.
  Gate CSS is in `layouts/gate.html.erb`. There is no asset-pipeline CSS and no JS.
- **Adding CSS.** Reuse existing classes before adding new ones. New colors become tokens. No
  inline `style=""` attributes; none remain in `app/views`.
- **Nav order.** Nav link colors use `:first-child` and `:nth-child(2–4)`, so they depend on
  link order. Adding or reordering nav links means updating those rules. `.nav a:first-child`
  also matches the account email link (the first child of `.nav-account`).
- **Partials.** Shared partials declare strict locals (`<%# locals: (...) -%>`).
- **Helpers.** View helpers live in `ApplicationHelper`: `money`, `review_pill`, `sync_pill`,
  `nav_link`, `nav_review_count`, `page_path`, `sync_year_range`.
- **Year-scoped pages.** Controllers use `current_tax_year` and `TaxYearStatus` for year facts.
  Links between these pages pass `year:`.
- **Data scoping.** Every query on Amazon data goes through `Current.user`.

## 15. Known design debt

Recorded here, not yet fixed:

- **Link contrast.** Orange link text (`#ff9900`) on white is about 2:1, below WCAG AA (4.5:1).
  Consider ink links with an orange underline.
- **Focus.** Buttons and links use the browser's default focus ring, not a designed one.
- **Reduced motion.** The app layout has no `prefers-reduced-motion` rule for the hover lift and
  card tilts.
- **Unused CSS.** `.bars` / `.bar` and `turbo-frame.card`.
- **Hardcoded colors outside the tokens:**
  - `.flash.alert` `#d1d5db`
  - the fourth stat card `#f3f4f6`
  - the input shadow `rgba(17,24,39,.2)`, the old palette's ink
- **Alert flashes.** `.flash.alert` is gray in the app, so alerts barely differ from notices. On
  the gate it's red.
- **Account nav link.** The display name or email link inherits the brand's 20px ink pill style through
  `.nav a:first-child`.
- **Duplicated tokens.** The gate layout copies a subset of the tokens.
- **Favicon.** `public/favicon.png` is 1254×1254 and about 1.1 MB. It should be a small icon
  plus an apple-touch icon.
- **Stale branding.** The TXF header still names the program "Accounting Demo".

## 16. Decision log

| Date | Decision |
|---|---|
| 2026-05-08 | Started as a generic Rails + Hotwire accounting dashboard scaffold. |
| 2026-05-29 – 2026-05-30 | Rebranded as Amazon Tax Pro with a favicon, and refocused on the Amazon seller tax workflow: upload reports, categorize, then tax packet and TurboTax export. |
| 2026-06-08 | Replaced the multicolor palette with the Amazon palette, ink `#131921` plus a single orange `#ff9900` accent (`b4b2551`). |
| 2026-09-29 | Added email/password accounts and the shared-password gate with its own "vault" layout, connected Amazon through SP-API with tax-year sync (`1db4d88`), and added a development sandbox (`fa8cec8`). |
| 2026-10-01 | **Sync-first pivot.** Connect Amazon is the main path, and upload is a hidden fallback. |
| 2026-10-01 | Kept email/password accounts. Connect Amazon is the required next step after sign-up. No Login with Amazon. |
| 2026-10-01 | Syncing is manual only: no sync on connect and no scheduled sync. |
| 2026-10-01 | Tax-year centric IA: one shared year and switcher, one Review page per year across all syncs and uploads. "Imports" became Review and Sync history. |
| 2026-10-01 | Auto-accept: any row with a suggested category counts right away; only Uncategorized rows need review. `reviewed_at` separates auto-categorized rows from rows a person accepted. Existing rows get recategorized with `amazon:recategorize`. |
| 2026-10-01 | Outputs count accepted rows only. The TXF and audit CSV match the tax packet, and the readiness checks warn about rows not included yet. |
| 2026-10-01 | Sync wins over uploads. Uploads skip synced years, and syncing a year with uploads asks to remove them first. |
| 2026-10-01 | One year control per page. The connect card's **Sync YEAR** button syncs the selected year rather than having its own year select. |
| 2026-10-01 | Year-scoped h1s include the year ("Review 2025", "Tax Packet 2025", "TurboTax Export 2025"). |
| 2026-10-01 | Created this file as the design source of truth. |
| 2026-10-01 | Merged PR #4 into the sync-first design: signed totals through `AmazonYearActivity` (credits net, shipping charges are expenses), gross receipts plus an after-fee revenue reference, plain-language row labels with Amazon details, and search, amount, and sort filters on Review. Kept accepted-only outputs, the shared tax year, and sync-wins, so the PR's per-import review page, featured priorities list, and API-over-upload source preference were not adopted. Sync runs record `sandbox_sample`, and the tax packet flags sandbox totals. |
| 2026-10-01 | Merged PR #3 into the sync-first design. Added Profile & settings: display name, business name that prefills new TurboTax export years, a default tax year that `TaxYearContext` uses after an explicit or session year, and a password change that signs out other sessions. Not adopted: the review threshold preference, because Review's minimum amount filter covers it; the Featured review page; `User#effective_tax_year`; and the PR's guide copy. No data download card was added. |
| 2026-10-01 | Added the sandbox seller: a shared login (`sandbox@amazontaxpro.com`) in every environment, created on first sign-in and pre-connected. Its syncs use the real sync pipeline with a generated, deterministic Finances API client instead of Amazon, so the team can develop without real seller accounts. Its password and account are locked, and sign-up can't claim its email. |
