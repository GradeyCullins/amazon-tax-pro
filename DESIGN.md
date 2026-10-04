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

The app bar shows, in order: the brand (links to the dashboard) · **Dashboard** · **Review** ·
**Tax Packet** · **TurboTax Export**, then on the right the display name or email (links to
Profile & settings) · Sign out.

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
export. The dashboard's "What needs attention" checklist shows these steps, with links to the
matching pages. The Review count is also visible in navigation and Data coverage, so the
dashboard does not repeat it in a separate next-step prompt.

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
- **Gross receipts vs revenue.** Gross receipts (sales + shipping credits) is the Schedule C
  figure. The planning revenue subtotal (gross receipts minus refunds, Amazon and FBA fees, ads,
  and shipping charges) appears as "Revenue" in the Tax Packet and "Revenue (reference only)" in
  the Schedule C preview. Notes explain the calculation and that it is not a Schedule C line or
  a TurboTax export amount.
- The dashboard groups the selected year's summary into **Revenue** and **Data coverage** cards.
  Revenue leads with the planning subtotal and itemizes gross sales, buyer-paid shipping, refunds,
  Amazon and FBA fees, advertising, and shipping charges so the amount can be reconciled. Data
  coverage shows counted, excluded-from-Schedule-C, needs-review, and skipped row counts. The
  excluded count is a subset of counted rows; needs-review and skipped rows do not count. Cost of
  goods sold remains in the readiness checklist because it is not part of the revenue subtotal.
- Dashboard coverage labels link to the matching Tax Packet, TurboTax Export, or filtered Review
  section. The excluded count names transfers, withheld sales tax, and reserves beside the number.
  Zero-dollar revenue components remain visible in the demo so the full calculation can be checked.
- The connected Amazon card keeps its status, last sync, and sync action in view. Sync behavior and
  Disconnect sit in a disclosure below; the sandbox sample-data notice is brief. Dashboard sync
  timestamps display in the viewer's browser time zone with an explicit abbreviation, falling back
  to a labeled UTC time when browser scripting is unavailable.
- Transfers, marketplace-withheld tax, and reserves are counted rows, but they're left out of
  Schedule C lines ("not on Schedule C").
- The Tax Packet keeps Gross receipts first and Revenue second in a prominent two-card summary.
  Remaining totals sit in Sales and adjustments, Costs and expenses, and Other activity groups;
  the last group is explicitly outside Schedule C. A disclosure explains the calculation and
  display signs. Short review and sandbox notices wrap above the summary. The audit trail filters
  counted rows by category, shows plain-language labels first, and keeps Amazon fields and source
  links in an expandable detail. Filtering preserves the selected tax year and pagination; the
  cost-of-goods-sold empty state explains that its value comes from TurboTax export inputs.
- Buyer-paid shipping and shipping charges are separate Tax Packet figures: the former adds to
  gross receipts, while the latter is a selling cost. Both come from the Shipping audit category.
  Amazon's `Shipment > Expenses > AmazonFees > ShippingChargeback` leaf is a shipping charge,
  even though Amazon nests it under fees. Negative shipping rows map to other business expenses
  in the Schedule C export. The Tax Packet method note explains that the TurboTax Other business
  expenses line combines FBA fees, shipping charges, and the other-business-expenses category.
  Revenue is explicitly a planning subtotal rather than profit; it excludes reimbursements,
  cost of goods sold, and other business expenses.
- Category rule fixes reach existing rows through `bin/rails amazon:recategorize`. It's a dry run
  unless `APPLY=1`, and it only touches rows no person has reviewed.

## 4. Visual language

"Seller Central professional": calm, dense, and trustworthy, like the tools sellers already use.

- **Palette.** Mostly neutral: white cards on a light gray page, gray borders, and near-black
  text. Ink `#131921` (Amazon's header navy-black) is the app bar. Amazon orange `#ff9900` is
  reserved for primary buttons, the current-page marker in the app bar, and the Review count.
  Links are teal `#007185`. Status colors are soft tints with dark text.
- **Page.** A flat `#f3f3f3` background under a full-width ink app bar.
- **Edges.** 1px gray borders, an 8px radius, and a barely-there shadow on cards. No offset
  shadows, no tilts, no hover lift.
- **Type.** One sans-serif family throughout. Headings and numbers are bold, not oversized.

History: before 2026-06-08 the app used a multicolor palette; commit `b4b2551` moved it to the
Amazon palette. On 2026-10-01 the "Amazon-flavored neo-brutalism" look (grid paper, thick ink
borders, hard offset shadows, tilted cards, giant serif headlines, orange stat values) was
replaced with this quieter style, and the site gate followed (see section 9).

## 5. Tokens

All tokens are in `:root` in `app/views/layouts/application.html.erb`.

| Token | Value | Use |
|---|---|---|
| `--ink` | `#131921` | App bar, current tab, brand |
| `--text` | `#0f1111` | Body text and headings |
| `--paper` | `#f3f3f3` | Page background |
| `--surface` | `#ffffff` | Cards, inputs, secondary buttons |
| `--surface-soft` | `#f7f8f8` | Table headers, callouts, hover rows, list items |
| `--surface-muted` | `#eaeded` | Neutral pills, inline `code` |
| `--border` | `#d5d9d9` | Card, table, pill, and callout borders |
| `--border-strong` | `#888c8c` | Input and secondary button borders |
| `--primary` | `#ff9900` | Primary buttons, current app-bar link marker, Review count |
| `--primary-dark` | `#e47911` | Primary button border and hover |
| `--primary-soft` | `#fff4e0` | Warn pills, `.callout.warn`, guide steps |
| `--primary-line` | `#f3c27a` | Borders for the `--primary-soft` surfaces |
| `--link` | `#007185` | Links, focus outlines, focused input border |
| `--link-hover` | `#c7511f` | Link hover |
| `--good` / `--good-line` / `--good-text` | `#e6f4ea` / `#a8d5b5` / `#0d6b2f` | Green pills and notice flashes |
| `--warn-text` | `#8a4b00` | Text on warn pills and guide steps |
| `--bad` / `--bad-line` | `#fdecea` / `#f0b4ad` | Red pills and alert flashes |
| `--bad-dark` / `--bad-darker` | `#b12704` / `#8f1f03` | Red pill text; danger button and its hover |
| `--muted` | `#565959` | `.muted` labels, `.note` text, page subtitles, table header text |
| `--radius` | `8px` | Cards, buttons, callouts, flashes |
| `--shadow` | `0 1px 2px rgba(15,17,17,.08)` | Cards only |

**Status colors.**

| Status | Look | Pill class | Means |
|---|---|---|---|
| good | green tint, dark green text | `.pill.good` | Counted, done, connected, finished |
| warn | orange tint, brown text | `.pill.warn` | Needs action or in progress |
| bad | red tint, red text | `.pill.bad` | Failed or needs reconnect |
| neutral | gray | `.pill` | Doesn't count or is informational |

New colors become tokens. Don't hardcode hex values in rules. The exceptions are `#fff` text on
dark fills and the app bar's own grays (`#d5d9d9` link text, `#5a6370` Sign out border,
`#232f3e` Sign out hover).

## 6. Typography

- **Family:** system sans (`ui-sans-serif, system-ui, …`) everywhere, 15px body at weight 400,
  line-height 1.5. There is no display serif.
- **Sizes:**

  | Element | Size / weight |
  |---|---|
  | h1 | 28px / 700 |
  | auth-card h1 | 24px / 700 |
  | h2 | 19px / 700 |
  | h3 | 16px / 600 |
  | `.value` (stat numbers, ink, tabular) | `clamp(22px, 3vw, 28px)` / 700 |
  | Buttons, labels, row headers | 600 |
  | Links | 500, teal, 1px underline |

- **Text styles:**
  - `.guide-copy` is the standard paragraph inside cards: 15px, text color.
  - `.note` is a secondary hint under a component: 13px, muted.
  - `.muted` has two jobs:
    - an uppercase 12px micro-label (weight 600, slight tracking), used for stat labels and
      metadata; table headers use the same style
    - inside `.page-header`, a sentence-case 15px muted subtitle

## 7. Layout

- **App bar.** `.app-bar` spans the full window width with 32px side padding (16px under
  720px), 56px tall.
- **Shell.** `.shell` fills the width up to 1920px with 32px side padding (16px under 720px), so
  content lines up with the app bar on normal screens.
- **Page header.** `.page-header` puts the h1 and its `.muted` subtitle on the left, and
  `.actions` (year switcher, then secondary links) on the right. It stacks under 720px.
- **Grids.**
  - `.cards`: auto-fit columns, at least 200px each
  - `.guide-grid`: at least 230px per column
  - `.dashboard-main`: 2fr / 1fr (min 300px), one column under 720px
- **Spacing.**
  - 28px under the app bar
  - 20px under the page header
  - 16px between cards (`.grid` gap and `.section` margin-top)
  - 20px inside cards (14px under 720px)
- **Card margins.** `.card > :first-child` and `.card > :last-child` lose their outer margins, so
  cards never need spacing hacks.

## 8. Components

**App bar.** `header.app-bar` holds `.brand`, `nav.nav` (`aria-label="Main"`), and `.nav-account`.
- Nav links are light gray text on ink. The current page (`aria-current="page"`) is white,
  semibold, with a 3px orange underline.
- `.nav-count` is a small orange count badge with ink text inside the Review link.
- `.nav-account` shows the display name or email (underlined when current) and a ghost Sign
  out button.

**Cards.**

| Card | Built from | Notes |
|---|---|---|
| Card | `.card` | White panel with a 1px gray border, 8px radius, and the subtle shadow. Scrolls wide tables horizontally. |
| Stat card | `.card` with a `.muted` label and a `.value` | Used in `.cards` grids. Labels on year-scoped pages start with the year. |
| Guide card | `.card.guide-card` with a `.guide-step` | Numbered steps for "How it works". The step is a small orange-tint circle. |
| Connect card | `.card.connect-card` | The Amazon card on the dashboard and run details. See below. |
| Auth card | `.card.auth-card` | Narrow (440px) centered card for sign-in and sign-up. |
| Empty state | `.empty-state` | Says what's missing and offers the one next step. Can be a card or sit inside one. |

**Connect card layout.** Every state uses the same structure:
- an optional sandbox `.callout` at the top
- `.connect-header`: the h2 and `.connect-meta` (status pills, seller ID, last-sync note) on the
  left; `.actions` on the right with secondary actions first and the one primary action last
  (e.g. Sync history, then **Sync 2025**)
- body copy or an error `.callout`
- `.connect-footer`: a top-ruled row with the `.note` on the left and **Disconnect Amazon**
  (small secondary) on the right, shown whenever a connection exists

**Build ID footer.** `.build-info` at the bottom of every page, including the gate, shows
"Build" and the first 8 characters of the running commit from `BuildInfo.id`, in small muted text.

**Buttons.** Use `link_to … class: "button"` for navigation and `button_to` for anything that
changes state.

| Class | Use |
|---|---|
| `.button` | Primary: orange with a darker orange border. Use at most one per area. |
| `.button.secondary` | White with a gray border, for other actions. |
| `.button.small` | Inside tables, filters, and pagination. |
| `.button.danger` | Solid red with white text. Destructive actions only, always behind `confirm()` or a confirmation page. |

All buttons have an 8px radius, a 1px border, and change background on hover (no lift). In
Review rows only **Accept** (rows that need review) is primary; Save, Skip, and Restore are
secondary, so a page of rows isn't a wall of orange.

**Pills** (`.pill`, `.good` / `.warn` / `.bad`).
- Always choose colors through the helpers: `review_pill(review_status)` and
  `sync_pill(batch)`.
- Sync runs: Queued and Syncing are orange, Finished is green, Failed is red. Uploads show a
  gray "Uploaded".
- Dashboard checklist: Done and Ready are green, To do and Syncing are orange, Failed is red,
  Waiting / Not yet / Upload are gray.
- Source pills (Amazon sync / Upload) are always gray.

**Callouts and flashes.**
- Callouts and flashes have a 1px border, 8px radius, and no shadow.
- `.callout` is neutral (soft gray): errors from Amazon, the sandbox notice.
- `.callout.warn` (orange tint) needs attention: mixed sources, a sync in progress, rows not
  included yet, no rows for the year.
- `.callout .actions` adds spacing for buttons inside a callout.
- `.flash` is the notice after an action (green tint). `.flash.alert` is an error (red tint).

**Forms.**
- `.form-row` stacks a label over a field (max 520px). `.inline-form` puts controls in one row.
- `.row-form` is the per-row category form on Review. It doesn't wrap on desktop and wraps
  under 720px.
- Inputs and selects have a 1px `--border-strong` border, a faint inset shadow, and a 2px teal
  focus outline.

**Tables (`.tight`).**
- Soft gray header row with uppercase muted labels, 1px gray row rules, and a soft hover
  highlight. No zebra striping. Row headers (`th scope="row"`) are semibold.
- Headers use `scope="col"`. Checklist row labels use `th scope="row"`.

**Shared partials.**

| Partial | Locals | What it does |
|---|---|---|
| `shared/_tax_year_switcher` | none | Year select plus a full-size "Switch" button, placed in `.page-header .actions` |
| `shared/_pagination` | `pagination:` | "Showing a–b of n" with Previous/Next (`rel` set) and a "Page x of y" pill |
| `shared/_mixed_source_warning` | `year_status:` | `.callout.warn` for a synced year that also has uploaded rows. Links to the sync confirmation, or to Sync history when the year can't be synced. |
| `amazon_syncs/_sync_action` | `year:` | The next-step button (see [Next-step order](#next-step-order)) |
| `dashboard/_amazon_connection` | `connection:`, `active_sync:`, `year_status:` | The connect card in each state: unavailable, not connected, needs reconnect, syncing, connected |

Pagination is 100 rows per page.

**Review controls.**
- `.tabs` are 1px-bordered pill links with `.tab-count`. The current tab is filled ink.
- `.filters` holds the `.review-search` form (search, category, amount range, sort), the
  amount hint, and the "Only rows from <sync or upload>" note. Bad amounts show a `.callout.warn`.
- `.row-details` is a `<details>` disclosure inside a table cell, with a `dl` of Amazon fields.

**"What needs attention" checklist.** A `.tight` table with four rows: Amazon sync, Review, Cost
of goods sold, Export. Each row has a pill and one sentence with a link.

## 9. Gate page

`app/views/layouts/gate.html.erb` is its own layout (the app layout needs a signed-in context),
but it looks like the sign-in page:

- The ink app bar with the brand only (no nav or account links).
- A centered 440px `.gate-card` with the same border, radius, and shadow as `.card`.
- A `.pill` "Private beta" (warn tint), the h1 "Enter the access password", and one sentence
  saying the device stays unlocked for 30 days.
- The red-tinted `.flash` for a wrong password (`role="alert"`), the standard input and orange
  primary **Unlock** button, a muted `.fine` line, and the build ID footer.

The gate copies the tokens it uses. Keep their values identical to the app's `:root`.

## 10. Motion and interaction

- **Hover.** Buttons and links change color only (`.12s ease` on buttons). Nothing lifts,
  rotates, or moves.
- **No JavaScript.** No JS, no Turbo, no CSS framework. Full page loads and plain forms.
- **Destructive actions.**
  - `.button.danger` with `onsubmit="return confirm(…)"`: delete upload, delete account.
    Disconnect uses a small secondary button with the same `confirm()`.
  - A dedicated confirmation page when the consequences need explaining: removing uploaded rows
    before a sync. It lists what will be removed.
- **After actions.** Row actions return to the same filtered page. Starting a sync returns to the
  dashboard, which shows progress.

## 11. Responsive

**Under 820px:**
- The Tax Packet audit switches to readable row cards before the desktop table columns become cramped. Table headers remain available to assistive technology, and row details and pagination have 44px touch targets.

**Under 720px:**
- The app bar and shell padding drop to 16px.
- The nav moves to its own row under the brand and account, and scrolls sideways if needed.
- The page header stacks, and `.actions` go full width with buttons flexing (the connect card's
  actions too).
- `.dashboard-main`, `.profile-grid`, and `.guide-grid` become one column.
- Tables get a 640px minimum width and scroll inside their card.
- The Tax Packet keeps its year selector and actions in a compact two-column header, with 44px touch targets.
- Inline forms stretch, and row forms wrap.

**Under 460px:**
- Stat cards become one column, and buttons go full width (except Sign out).

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

- **Focus.** Inputs and selects get a 2px teal outline and border. Links, buttons, and
  `summary` get a 2px teal `:focus-visible` outline with a 2px offset.
- **Current page.** `aria-current="page"` marks the current nav link (white, semibold, orange
  underline), the account link (underlined), and the filter tab (ink fill), so color isn't the
  only cue.
- **Contrast.** Teal links (`#007185`) and muted text (`#565959`) meet WCAG AA on white.
- **Labels.**
  - Status is never shown by color alone: pills always have text.
  - The nav count has screen-reader text: "rows need review".
  - Row category selects have `aria-label="Tax category"` and unique ids.
  - Tab and pagination `nav`s have `aria-label`s.
- **Tables.** Every table header has a `scope`.
- **Motion.** Nothing animates beyond short color transitions, so no reduced-motion rule is needed.

## 14. Implementation conventions

- **Where CSS lives.** App CSS is the `<style>` block in `app/views/layouts/application.html.erb`.
  Gate CSS is in `layouts/gate.html.erb`. There is no asset-pipeline CSS and no JS.
- **Adding CSS.** Reuse existing classes before adding new ones. New colors become tokens. No
  inline `style=""` attributes; none remain in `app/views`.
- **Nav.** Nav links are styled uniformly, so adding or reordering them needs no CSS changes.
- **Partials.** Shared partials declare strict locals (`<%# locals: (...) -%>`).
- **Helpers.** View helpers live in `ApplicationHelper`: `money`, `review_pill`, `sync_pill`,
  `nav_link`, `nav_review_count`, `page_path`, `sync_year_range`.
- **Year-scoped pages.** Controllers use `current_tax_year` and `TaxYearStatus` for year facts.
  Links between these pages pass `year:`.
- **Data scoping.** Every query on Amazon data goes through `Current.user`.

## 15. Known design debt

Recorded here, not yet fixed:

- **Duplicated tokens.** The gate layout copies the tokens and base styles it uses from the app
  layout. Changing a shared token means editing both files.
- **Favicon.** `public/favicon.png` is 1254×1254 and about 1.1 MB. It should be a small icon
  plus an apple-touch icon.
- **Stale branding.** The TXF header still names the program "Accounting Demo".

Fixed in the 2026-10-01 visual refresh: orange link contrast, the default button focus ring,
hover lift and tilts without a reduced-motion rule, unused `.bars`/`.bar`/`turbo-frame.card`
CSS, hardcoded stat-card and alert colors, gray alert flashes, and the account link inheriting
the brand pill style.

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
| 2026-10-01 | Added a build ID footer to the app layout: the first 8 characters of the running commit (Kamal's `KAMAL_VERSION` in production, git `HEAD` locally) so the team can tell which build is live. |
| 2026-10-01 | **Visual refresh.** Replaced the neo-brutalist look with a quieter Seller Central style: full-width ink app bar with a Dashboard link and orange current-page underline, content up to 1920px wide, 1px gray borders, subtle card shadow, no tilts/grid paper/hover lift, sans-serif headings, ink stat values, teal links, tinted status pills and flashes. The connect card now uses a header (title and status left, actions right) and a footer (note and Disconnect). Review row Save/Restore became secondary buttons. The site gate dropped its "vault" look (ticker, tilt, sticker, padlock) and now matches the sign-in page with the app bar and build ID footer. |
| 2026-10-03 | In the TurboTax Schedule C preview, shortened the planning subtotal label to "Revenue (reference only)" and explained its deductions and exclusion from the export in the note below. |
| 2026-10-03 | Grouped the dashboard's summary into a reconciled Revenue card and a separate Data coverage card; kept cost of goods sold with tax readiness. |
| 2026-10-03 | Added a context-aware next-step prompt, linked coverage counts and explained excluded rows, compacted the connected Amazon card, and displayed dashboard sync times in the viewer's time zone. Kept zero-dollar revenue lines visible for the demo. |
| 2026-10-03 | Reduced the next-step prompt to a compact strip so its action stays visible without repeating the full checklist at card scale. |
| 2026-10-03 | Removed the next-step strip after finding its Review action duplicated navigation, Data coverage, and the "What needs attention" checklist. |
| 2026-10-03 | Renamed the Tax Packet's planning subtotal from "After-fee revenue" to "Revenue" while retaining the calculation and Schedule C distinction in its note. |
| 2026-10-03 | Gave the Tax Packet a two-figure summary, grouped the remaining category totals, compacted its notices, and made its accepted-row audit trail filterable by category with plain-language labels and expandable Amazon details. |
| 2026-10-03 | Audited the Tax Packet totals against both sandbox years and the Schedule C export. Split shipping credits and charges in the display, clarified that Revenue excludes COGS and other income/expenses, and refined the summary and audit-trail copy. |
| 2026-10-03 | Corrected Shipment ShippingChargeback categorization from Amazon fees to Shipping, then recategorized only the local sandbox seller's unreviewed rows. Gross receipts and Revenue stayed the same; the fee and shipping breakdown, audit labels, and Schedule C expense lines now reconcile. |
| 2026-10-03 | Aligned the TurboTax Revenue reference note with its full formula, including FBA fees, and explained why the Tax Packet's separate expense categories combine into one TurboTax Other business expenses line. |
| 2026-10-04 | Made the shared tax-year Switch control full height. On narrow screens, the Tax Packet uses touch-sized actions and a readable audit card layout instead of horizontal table scrolling. |
