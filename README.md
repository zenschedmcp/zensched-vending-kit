# ZenSched Vending-Route Reference Kit

A copy-pasteable setup for a 1–5 truck vending or micro-market route shop that wants an AI assistant to run route scheduling, GPS-verified restock records, a local coin-box extract, and host invoicing. ZenSched handles the live schedule, the technician's phone app, GPS check-ins at the site, and the photo-plus-checklist Restock form. A small local database on your computer holds your host accounts, machines, routes, cadence, visit summaries, and invoices.

**You do not need to know how to program or write SQL to use this.** You type plain English to your AI assistant ("schedule North Loop this week", "add a weekly drink machine", "what did Luis pull from Harbor snack", "who owes me money?") and the AI does the work using two tools you set up once. Setup takes about 15 minutes and is the only technical part.

If you *are* a developer, skip to [For developers](#for-developers).

## What this kit is not — read this first

**What it is:** GPS-verified proof that a tech was at the building, a Restock form (coin collected, items restocked, temperature OK, sold-out, up to 2 machine photos), a local extract of those records for your own files, and host invoices built from completed stops that have a service fee.

**What it is not:**

- **Not a DEX / MDB / telemetry pull.** `coin_log` is *your* copy of what the tech typed on the phone (date, machine, coin, items, temp, sold-out). It is not a machine audit file, not a cash-drawer reconciliation, and not a substitute for whatever your warehouse or accounting system already does. This kit does not talk to the vend mechanism.
- **Not a warehouse or planogram system.** "Items restocked" is a textarea. There is no SKU catalog, no pick list, and no spiral map.
- **Not proof the spirals were filled correctly.** GPS says the tech was within the check-in radius of the site pin. The photos say they pointed a camera at the box. The kit cannot tell you a facing count is made up.
- **Not a signed legal document.** The Restock form has no signature field. On ZenSched a signature field replaces the Submit button, so adding one would make every stop look like the tech had signed something. Submitting the form is just submitting the form.

If any of those is a deal-breaker, this kit is not for you. If you want route cadence, door-GPS, and a local extract you can file next to your real DEX or cash count, read on.

## What lives where

**ZenSched (source of truth for what happened, when, and where):**

- Locations (one GPS pin per machine **or** one pin per site when two machines share an address; the check-in radius is a **policy** setting)
- Workers (technicians with the mobile app)
- Events (one "Restock" job per machine, renewed every 60 days)
- Shifts (each scheduled restock, with push notifications to the tech)
- GPS punches (check-in/check-out with distance-from-the-pin verification)
- The Restock form (coin, items, temp, sold-out, up to 2 photos) and every submission
- Timesheets (verified hours worked)

**Local SQLite database (`vending-ops.db`, on your computer):**

- Host-account contact, commission notes (split %, who owns the box) that **never leave your computer**
- Machines: type (snack / drink / combo / coffee / micro-market), site label, address, access notes (badge, dock, manager cell) that **never leave your computer**, frequency (weekly / biweekly / monthly / quarterly / on-demand), next service date, host fee (`service_rate`; 0 if you own the box and just keep the coin)
- Routes and stop order
- Technicians
- Completed visits with a summary of each Restock form, the coin-log extract, sold-out flags, and host invoices
- Your settings (timezone, default tech, invoice prefix, Restock form id)

**Never duplicated:** the live schedule, punches, timesheets, and report photos stay in ZenSched. The local database only stores *references* to them plus a short per-visit summary so you can answer "what did we pull from Harbor snack" without paying to re-read reports.

### Privacy note

Badge codes, loading-dock hours, manager cell numbers, and commission splits are stored only in `machines.access_notes` and `accounts.commission_notes` in the local database. `SKILL.md` forbids the AI from putting them into any ZenSched field. Give them to your tech yourself, by whatever channel you trust. ZenSched only ever sees the machine label, the street address, and the GPS pin.

## How it works day to day

Your AI assistant has two sets of tools:

1. **ZenSched tools** (`location_create`, `shift_create`, `form_submissions`, `shift_list`, ...) that talk to ZenSched over the internet.
2. **A SQLite tool** (`sqlite_query`, `sqlite_execute`) that reads and writes `vending-ops.db` on your computer.

When you say "schedule North Loop this week," the AI reads which machines are due from the local database (`next_service_date` in the next 7 days), creates one shift per stop on ZenSched, and tells you what it did. Your tech sees the stops in the app, checks in at the site (GPS-verified), restocks, fills in the Restock form with photos, and checks out. Later you say "record this week's visits" and the AI pulls the completed shifts and records, saves a summary locally, advances each machine's next date (weekly +7, biweekly +14, monthly +1 month, quarterly +90 days, on-demand clears it), and leads with anything marked Partial / Full sold-out or temperature No. "Coin log for September" is a local query. You never run SQL yourself. `SKILL.md` in this repo is the instruction sheet that teaches the AI how to do all of this; you paste it into your AI tool once.

A typical stop costs about **$0.35** on ZenSched: GPS in $0.10 + GPS out $0.10 + reading a Restock form that has photos $0.15. Geocoding a new site is $0.03 once (a second machine at the same address reuses the pin). The AI states the cost before it spends.

## Setup

### 0. What you need

- **An AI tool that supports MCP.** These instructions use Claude Desktop (Windows or Mac). Cursor works too.
- **Node.js 20 or newer.** The SQLite tool runs on it. Download the LTS installer from [nodejs.org](https://nodejs.org/) and run it with the defaults. This is the only software install.
- You do **not** need the `sqlite3` command-line program, Python, or Git.

### 1. Make a folder for your data

Create a folder where the database will live and write down its full path. Examples:

- Windows: `C:\Users\YourName\vending-ops`
- Mac: `/Users/yourname/vending-ops`

The database file will be created automatically inside this folder the first time the AI uses it.

### 2. Add both tools to your AI's config file

Open the MCP configuration file for your AI tool:

- **Claude Desktop, Windows:** `%APPDATA%\Claude\claude_desktop_config.json` (paste that into the File Explorer address bar)
- **Claude Desktop, Mac:** `~/Library/Application Support/Claude/claude_desktop_config.json` (in Claude Desktop: Settings → Developer → Edit Config)
- **Cursor:** Settings → MCP → Add new global MCP server

Paste in the contents of `mcp.json.example` from this repo, then change one line, the `SQLITE_PATH`, to point at your folder from step 1 plus `\vending-ops.db` (Windows) or `/vending-ops.db` (Mac):

```json
{
  "mcpServers": {
    "zensched": {
      "url": "https://mcp.zensched.com/mcp",
      "headers": { "Authorization": "Bearer zsc_your_key_here" }
    },
    "vending-ops-db": {
      "command": "npx",
      "args": ["-y", "easy-sqlite-mcp"],
      "env": { "SQLITE_PATH": "/Users/yourname/vending-ops/vending-ops.db" }
    }
  }
}
```

**Windows path gotcha:** inside a JSON file every backslash must be doubled. Write `"C:\\Users\\YourName\\vending-ops\\vending-ops.db"`, not `"C:\Users\..."`. A single backslash will silently break the config.

**Leave `zsc_your_key_here` exactly as it is for now.** You do not have a key yet. The ZenSched tools that create your account work without one, and you will fill this in during step 3.

Save the file and **fully quit and reopen** your AI tool (on Mac, Cmd-Q; on Windows, right-click the tray icon → Quit). It only reads this file on startup.

### 3. Create your ZenSched account

In a new chat, type:

> Call `zensched_guide`, then call `account_create` with org_name "My Vending Co" (use my real business name if I told you one). Show me the `zsc_` key it returns.

Copy the `zsc_` key. Go back to the config file from step 2, replace `zsc_your_key_here` with your real key, save, and fully quit and reopen the AI tool again.

Some clients can adopt the key mid-session with `account_use_key`; you can ask the AI to try that to keep going immediately, but still update the config file so the key survives restarts. Keep the key private; it is the password to your account.

### 4. Create the database tables

Open `schema.sql` from this repo in any text editor, copy the whole thing, and paste it into the chat with this message in front of it:

> Create these tables in my vending-ops database. Run each statement one at a time using the SQLite tool, then list the tables to confirm.

The AI will run the statements one at a time and confirm the tables exist. The `vending-ops.db` file now exists in your folder.

If you happen to have the `sqlite3` command-line tool, `sqlite3 vending-ops.db < schema.sql` does the same thing, but it is not required.

### 5. Teach the AI the workflow

Paste the contents of `SKILL.md` into your AI tool as standing instructions. In Claude Desktop, create a Project and put it in the project instructions; in Cursor, save it as a rule. Then tell it your basics once:

> My business is Gulf Coast Vending in Tampa, Florida (Eastern time). Save that in settings, set the check-in radius to 150 m, and set up the Restock form.

It writes those to the `settings` table, widens the account policy (indoor break rooms sit far from a street pin), creates the Restock form on ZenSched (free), and saves the form id so every stop gets it automatically.

**Check-in radius.** The default pin uses `checkin_radius_m=150` on `location_create`, but ZenSched **enforces** the radius through the account's policy, not per machine. With geofencing on it raises anything under 100 m to about 91 m (300 ft), so a 75 m house-style radius is too tight for a lobby three floors up. Ask the AI to "set the check-in radius to 150 m" (`policy_update`) or to move the pin onto the building (`location_update`, free). Do not ask it to widen the radius "on that location" — that field is informational only.

### 6. Funding (only when asked)

The first 200 ZenSched tool calls per day are free. Some things are metered: creating a location (geocoding, $0.03, once per site if you reuse the pin), inviting a technician ($0.25), each GPS-verified check-in or check-out ($0.10), and reading a Restock form ($0.05, or $0.15 when it has photos). When a metered call happens without funds, the AI will get a `payment_required` response and tell you how to add the $5 activation deposit, which is credited to your balance. You will not be charged without seeing this first.

A typical stop is about $0.35 (in + out + photo record). A tech doing 40 stops a day is about $14 in meters that day, plus $0.03 the first time you add each site. The AI states the cost before it spends.

## Using it

Everything after setup is plain English. Examples:

- "Add a route called North Loop."
- "Add Harbor Office Park, priya@harborpark.example, 400 Channelside Dr, Tampa FL 33602. Two weekly machines starting Monday: snack VM-11 at 8:00 stop 1, drink VM-12 at 8:15 stop 2. We own both, no host fee. Badge 4412 at the dock."
- "Add a biweekly combo at Bayshore Clinic, 410 Bayshore Blvd, $25 host fee, Wednesday 10."
- "Invite Luis Ortega, luis@example.com, make him the default, and put him on North Loop."
- "Schedule North Loop this week for Luis."
- "Record this week's visits."
- "Coin log for last week, and anything sold out."
- "Draft invoices for anyone with a host fee."
- "Who still owes me money?"
- "Bayshore paid INV-2026-0001."
- "Pause the Harbor drink until the compressor is fixed."
- "Service the Harbor drink Thursday, it's empty — don't move the regular Monday."

See `QUICKSTART.md` for the first-week walkthrough and `example-workflow.md` for exactly which tools the AI calls behind each of these.

### What "invoice" means here

"Draft an invoice" records the invoice in your database (number, date, due date, amount, which visits) and the AI writes out a plain-text invoice you can paste into an email or text message, with a line per billed stop and a note that the visit was GPS-verified. It does **not** generate a PDF, email it for you, or collect payment. Only machines with a `service_rate` above 0 are invoiced — operator-owned boxes stay on the coin log. Invoices do not list coin totals or commission splits unless you ask. When the host pays, tell the AI ("Bayshore paid INV-2026-0001") and it marks it paid. If you outgrow this, the invoice records are simple enough to import into any accounting tool.

## Mobile app for technicians

- **Android:** [Google Play](https://play.google.com/store/apps/details?id=com.zensched.app)
- **iOS:** [TestFlight](https://testflight.apple.com/join/Wp51m5Yq)

When you invite a technician, they get an email, install the app, and can immediately see their stops, check in and out with GPS verification, and fill in the Restock form with photos. The form is attached to each stop automatically. There is no signature step — they tap Submit.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| AI says it has no ZenSched tools | Config file not saved, or the app was not fully restarted | Check the JSON is valid (paste it into [jsonlint.com](https://jsonlint.com)), then quit and reopen the app |
| AI says it has no SQLite / `vending-ops-db` tools | Node.js not installed, or bad `SQLITE_PATH` | Install Node.js LTS; on Windows check every backslash is doubled |
| `SQLITE_PATH` points nowhere / "unable to open database" | Folder from step 1 does not exist | Create the folder; the file is created automatically but the folder is not |
| ZenSched tools return an auth error | Key still says `zsc_your_key_here`, or was pasted with a space | Re-paste the key, restart |
| `payment_required` | Metered call with no balance | Follow the instructions in the response; $5 deposit |
| AI creates shifts at the wrong hour | Timezone not set | "Set my timezone offset to -04:00 in settings" (use your own offset) |
| Shift creation fails for dates a couple of months out | The machine's 60-day ZenSched event has expired | Say "renew the events"; the AI runs the roll-over in `SKILL.md` and retries |
| Tech's check-in not GPS-verified in a lobby / break room | Geocoded pin is on the street, tech is several floors up, or the radius is too tight | Ask the AI to widen `checkin_radius_m` with `policy_update` (not on the location) to 150–200 m, or run `location_update` / `location_refine` ($0.10). Do **not** ask for `remote_checkin` on policy 0 if you also have outdoor pads |
| Two machines at the same building each got a geocode charge | Address written differently | Say "these are the same site" and the AI will point the second machine at the first pin (one wasted $0.03) |
| Tech does not see the Restock form | Form not assigned to that machine's event | "Attach the Restock form to Harbor snack's event" (`form_assign`) |
| "Coin log" comes back empty | Visits not recorded yet, or the tech left coin blank | "Record this week's visits" first |
| AI asks you to run SQL yourself | It does not have `SKILL.md` loaded | Re-paste `SKILL.md` as project instructions |
| AI refuses to put a badge code in ZenSched | Working as intended | Give it to the tech directly |
| AI offers a DEX file or a warehouse pick | It shouldn't | This kit does not produce those; use your machine or warehouse tool |

If something is confusing or broken in ZenSched itself, ask the AI to call `feedback_submit` with a description. It is free, needs no account, and a human reads every submission.

## For developers

**Architecture.** Two MCP servers, no application code. The agent is the integration layer; `SKILL.md` is the spec it follows. ZenSched is authoritative for operations (schedule, punches, forms); SQLite is authoritative for CRM, routes, cadence, visit summaries, the coin-log extract, and host billing; each side stores only the other's **integer** IDs, plus a per-visit form summary cached locally because submission reads are metered.

**Data model decisions.**

- **One ZenSched location per machine or site.** Default: `location_create(name=<machine_label>, street_address=..., checkin_radius_m=150, idempotency_key="loc-machine-{machine_id}")`, stored on `machines.zensched_location_id` as an integer. A second machine at the same `address` + `city` reuses the first machine's location id (one geocode per site, $0.03). Each machine still gets its own rolling event. `checkin_radius_m` on `location_create` is informational; the enforced radius is `policy_update(0, '{"checkin_radius_m": N}')`, and with geofencing on the platform raises values under 100 m to 300 ft. Indoor break rooms need ~150 m.
- **Events are capped at 60 days by ZenSched**, so an event cannot be a permanent job template. Each machine holds its *current* event in `machines.zensched_event_id` and its last covered date in `machines.event_valid_until`. The agent creates a new event (`event_create(location_id, title="Restock - <machine_label>", start_date, end_date=start+59 days, idempotency_key="event-machine-{machine_id}-{YYYYMMDD}")`) whenever a shift date is later than `event_valid_until`, calls `form_assign(form_id, event_id=...)` on it, and updates the row. `machines_due` exposes `event_needs_roll` per row and `events_expiring` lists machines due for renewal within 14 days. Shifts already created on the old event remain valid. When recording a completed visit whose `event_id` no longer matches a machine, the agent falls back to `event_get(event_id).location_id` against `machines.zensched_location_id`, preferring the machine whose label is in the event title.
- **Cadence is next-service-date on the machine, not the account.** `machines.service_frequency` is `weekly | biweekly | monthly | quarterly | on-demand`. Two machines at the same host can restock on different weeks. `machines_due` is every active machine with `next_service_date <= today+7` joined to an active account, emitting `start_iso` / `end_iso` (preferred start or `settings.default_shift_start`, duration from `default_shift_minutes`) and the shift `idempotency_key`. Worker resolution is machine pin → route default → `settings.default_worker_id`.
- **The `advance_service_date_on_visit` trigger** sets `last_service_date` and `next_service_date` on every visit insert: +7 / +14 / +1 month / **+90 days** / NULL. Quarterly is +90 days, not `+3 months`, so the interval does not drift with month length. Recording a one-off on a recurring machine also moves the cadence; `SKILL.md` tells the agent to set the date back if the owner says so.
- **Host fee vs coin.** `machines.service_rate` is the optional host restock fee (0 if the operator owns the box). `visits.amount` snapshots it. `visits.coin_collected` is the box cash from the form and is **not** an invoice line. `visits_to_invoice` omits `amount = 0`.
- `visits.zensched_shift_id` and `technicians.zensched_worker_id` are integer `UNIQUE`. `visits.report_dc_id` holds the form `submission_id`. `temp_ok` and `sold_out` are `CHECK`-constrained to the form's option labels (`Yes`/`No`/`N/A`, `None`/`Partial`/`Full`).
- `fill_visit_technician` sets `technician_id` from `zensched_worker_id` when the agent leaves it NULL. `fill_visit_duration_insert` / `_update` set `duration_minutes` as `round((julianday(out) − julianday(in)) × 1440)` when it is NULL and both stamps exist; an explicit value is never overwritten.
- `invoices.invoice_number` is auto-assigned by trigger as `{prefix}-{YYYY}-{0001}`. `invoices_outstanding` adds `days_overdue` and an `aging_bucket` (`current | 1-30 | 31-60 | 61-90 | 90+`).
- **`coin_log`** is a view over visits that recorded coin. **`sold_out_flags`** is Partial / Full only (None omitted); Full sorts first. Neither transmits anything and neither is a DEX file.
- `machines.access_notes` and `accounts.commission_notes` are the columns that must never be sent to ZenSched; `SKILL.md` rule 6 enforces it. `machines_due` still *selects* `access_notes` so the agent can tell the owner to pass them to the tech.
- `PRAGMA foreign_keys = ON` is in `schema.sql` and `SKILL.md` tells the agent to run it per session; SQLite does not persist it. Deleting an account cascades to machines, visits, and invoices; deleting a technician sets `visits.technician_id` NULL; deleting a route sets `machines.route_id` NULL.

**Restock form.** Created once with `form_create(title, fields_json, idempotency_key="form-restock")`; the exact `fields_json` is in `SKILL.md` and `example-workflow.md` (byte-identical) and was validated against ZenSched's `_validate_fields`. Every field carries an explicit `identifier` so submission `data` keys are stable (`coin_collected`, `items_restocked`, `temp_ok`, `sold_out`, `machine`; section `sec_restock`). Option keys are derived by ZenSched from the labels (lowercase, non-alphanumerics → `_`, truncated at 30 characters): `N/A` → `n_a`, `Yes`/`No` → `yes`/`no`, `None`/`Partial`/`Full` → `none`/`partial`/`full`. Every option here is well under 30 characters. **No `signature` field** — the phone keeps a Submit button. Snack / drink / combo / coffee / micro-market all reuse this form (`temp_ok=n_a` on a snack box with no cooler). Attaching is `form_assign(form_id, event_id=...)`.

**Idempotency keys.** Deterministic, derived from local IDs:

- location: `loc-machine-{machine_id}`
- event: `event-machine-{machine_id}-{YYYYMMDD window start}`
- shift: `shift-machine-{machine_id}-{YYYYMMDD}`
- worker: `worker-{email}`
- form: `form-restock`; assignment: `assign-restock-{event_id}`

ZenSched caches idempotent responses for 24 hours. A second machine at a reused site does **not** call `location_create`.

**Timestamps.** `shift_create` takes `start` and `end` in ISO 8601 with an explicit offset. Always use the business's local offset from `settings.timezone_offset` (e.g. `2026-09-08T08:00:00-04:00`), never `Z`. The view builds these strings so the agent does not have to.

**Metered reads.** `form_submissions` and `form_export` bill $0.05 per submission read ($0.15 with media); `form_export` is preferred for a week at a time. The kit stores the summary and media URLs on `visits` on first read so later coin-log questions are answered from SQLite. `shift_list`, `shift_status`, `event_get`, and `timesheet_export(mode="hours"|"raw")` are free.

**SQLite MCP server.** `mcp.json.example` uses [`easy-sqlite-mcp`](https://github.com/chenkumi/easy-sqlite-mcp) (Node, `better-sqlite3`, `SQLITE_PATH` env var pointing at `vending-ops.db`). Its `sqlite_execute` calls `prepare()`, so it accepts **one statement per call**; `schema.sql` is written so every statement stands alone and is idempotent. Any SQLite MCP server with read and write tools will work; adjust the tool names in `SKILL.md`.

**Schema test.** The schema was verified by splitting the file into its 45 statements with `sqlite3.complete_statement` and executing each individually (as the MCP server does) twice for idempotency (seed rows not duplicated), then exercising: all 7 tables, 7 views, and 9 triggers present; every view on an empty database; the `advance_service_date_on_visit` trigger for weekly (+7), biweekly (+14), monthly (+1 month), **quarterly (+90 days, 2026-09-07 → 2026-12-06, not +3 months / Dec 7)**, and on-demand (NULL); `fill_visit_technician` from `zensched_worker_id`; duration trigger on insert and update, never overwriting an explicit value; `UNIQUE` on `zensched_shift_id`, `technicians.zensched_worker_id`, and `routes.route_name`; every `CHECK` (frequency, `preferred_start`, `machine_type`, `stop_order`, `temp_ok`, `sold_out`); `machines_due` `start_iso` / `end_iso` / `idempotency_key` / worker / minutes; `event_needs_roll` flipping exactly when `event_valid_until < next_service_date`; inactive and +20-day rows excluded; `events_expiring`; same-site machines sharing one `zensched_location_id`; `route_board` stop order; `coin_log`; `sold_out_flags` omitting `None` and sorting Full first; `visits_to_invoice` omitting `$0` restocks; invoice numbering (auto `INV-2026-0001`, explicit number kept, prefix honored); all five aging buckets and `days_overdue`; cascade delete from account and technician set-null; `updated_at`; integer types on ZenSched ID columns. Form payload validated against `_validate_fields` (6 fields, no signature, SKILL.md byte-identical to example-workflow.md, every option key ≤ 30 characters, `N/A` → `n_a`). 124 checks, all passing.

## Support

- ZenSched docs: <https://www.zensched.com/docs/>
- Tool reference: <https://www.zensched.com/docs/tools/>
- Feedback: ask your AI to call `feedback_submit` (categories: `bug`, `friction`, `missing_capability`, `docs`, `billing`, `feature`, `other`)

## License

MIT. See `LICENSE`.
