# Quickstart

Setup is about 15 minutes, once. After that everything is plain English to your AI. Each step below tells you what to do and, where relevant, exactly what to type to the AI.

You need: Claude Desktop (or Cursor) and [Node.js LTS](https://nodejs.org/) installed. Nothing else.

Before you start, read the "What this kit is not" section of `README.md`. Short version: this is GPS-verified route proof plus a local extract of the Restock form. It is **not** a DEX file, **not** machine telemetry, **not** a warehouse inventory system, and **not** your official health-department / HACCP temperature log (the form's "Temperature OK" is a field note, not the regulatory record).

## 1. Make a data folder

Create a folder such as `C:\Users\YourName\vending-ops` (Windows) or `/Users/yourname/vending-ops` (Mac). Note the full path.

## 2. Add the two tools to your AI's config

Open the config file:

- **Claude Desktop, Windows:** `%APPDATA%\Claude\claude_desktop_config.json`
- **Claude Desktop, Mac:** `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Cursor:** Settings → MCP → Add new global MCP server

Paste this in and fix only the `SQLITE_PATH` line to match your folder from step 1:

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

- On Windows, double every backslash: `"C:\\Users\\YourName\\vending-ops\\vending-ops.db"`.
- Leave `zsc_your_key_here` as it is. You get the real key in the next step.

Save, then **fully quit and reopen** the AI app.

## 3. Create your ZenSched account

Type to the AI:

> Call zensched_guide, then account_create with org_name "Gulf Coast Vending". Show me the zsc_ key.

Copy the key into the config file in place of `zsc_your_key_here`. Save. Quit and reopen the app once more. (You can also ask the AI to call `account_use_key` with the key to continue right away, but update the file anyway so it sticks.)

## 4. Create the database tables

Copy the full contents of `schema.sql` and paste it into the chat with this line above it:

> Create these tables in my vending-ops database. Run each statement one at a time with the SQLite tool, then list the tables to confirm.

## 5. Give the AI its instructions

Paste `SKILL.md` into the AI as standing instructions (Claude Desktop: a Project's instructions; Cursor: a rule). Then:

> My business is Gulf Coast Vending in Tampa, Florida, Eastern time. Save that to settings, set the check-in radius to 150 m, and create the Restock form.

The AI saves your settings, widens the policy radius (indoor break rooms sit far from a street pin), and calls `form_create` once (free) to build the Restock form your techs fill in: coin collected, items restocked, temperature OK, sold out, up to 2 machine photos. No signature. It stores the form id so every stop gets it.

## 6. Add a route and your first machines

> Add a route called North Loop.

> Add Harbor Office Park, contact Priya Nair, priya@harborpark.example, 813-555-0140, 400 Channelside Dr, Tampa FL 33602. Two machines on North Loop, both weekly starting Monday 2026-09-08: snack (code VM-11) at 8:00 as stop 1, drink (code VM-12) at 8:15 as stop 2. We own both boxes, no host fee. Badge 4412 at the loading dock.

> Add Bayshore Clinic, contact Maya Chen, maya@bayshore.example, 813-555-0190, 410 Bayshore Blvd, Tampa FL 33606. One combo machine (code VM-21) on North Loop as stop 3, biweekly starting Wednesday 2026-09-10 at 10:00, $25 host restock fee. Manager cell is in the access notes: 813-555-0100.

Behind the scenes the AI inserts the accounts, route, and machines, calls `location_create` once for Harbor (reuses that pin for the second Harbor machine) and once for Bayshore ($0.03 each new site), creates a 60-day `event_create` per machine, attaches the Restock form with `form_assign`, and saves the IDs. Badge / manager notes go only into the local database. You just see a confirmation.

## 7. Invite your technician

> Invite Luis Ortega at luis@example.com as a tech, make him the default, and put him on North Loop.

Luis gets an email ($0.25), installs the app ([Android](https://play.google.com/store/apps/details?id=com.zensched.app) / [iOS TestFlight](https://testflight.apple.com/join/Wp51m5Yq)), and activates. Give him the Harbor badge and the Bayshore manager cell yourself; the AI will not put them in ZenSched.

## 8. Schedule the week

> Schedule North Loop this week for Luis.

The AI reads `machines_due`, creates one shift per stop on ZenSched, and summarizes by day. Luis gets a push notification for each, with the Restock form attached. It will confirm each stop is about $0.35 once he punches and you read the photo record.

## 9. After the work is done

> Record this week's visits, show me the coin log and anything sold out, then draft invoices for anyone with a host fee.

The AI pulls the completed, GPS-verified shifts and the Restock forms from ZenSched (reading records is metered, so it tells you the cost first), saves a per-visit summary, advances Harbor both machines +7 days and Bayshore +14, shows the coin-log extract (your copy, not a DEX file), flags anything Partial / Full or temp No, creates an invoice only for Bayshore's $25, and writes it out as text you can paste into an email.

> Bayshore paid INV-2026-0001.

Marks it paid.

## What next

- `README.md` for the full explanation, the telemetry boundary, troubleshooting table, and developer notes
- `example-workflow.md` to see the exact tool calls behind each step above
