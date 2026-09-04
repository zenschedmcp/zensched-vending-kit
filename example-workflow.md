# Example Workflow: What the AI Does Behind Each Request

This shows the exact tool calls the agent makes for a first week of operation, following `SKILL.md`. The owner only types the quoted lines; everything else is the agent's work. Assumes setup from `QUICKSTART.md` is complete (both MCP servers configured, `schema.sql` loaded, `SKILL.md` given as instructions).

IDs and responses are illustrative. ZenSched IDs are integers.

Shop: **Gulf Coast Vending**, Tampa, Florida, Eastern time (`-04:00` in September). One route (North Loop), two host accounts (operator-owned Harbor pair + billed Bayshore combo), one technician, then coin log and invoice.

Access notes (badge, manager cell) and commission terms stay in SQLite. They are never sent to ZenSched.

## Session start (every session)

```
sqlite_execute: PRAGMA foreign_keys = ON;
sqlite_query:   SELECT key, value FROM settings;
  → business_name = My Vending Co, timezone_offset = -05:00,
    default_worker_id = NULL, default_shift_start = 08:00,
    default_shift_minutes = 15, invoice_due_days = 30, invoice_prefix = INV,
    restock_form_id = NULL, event_window_days = 60, default_checkin_radius_m = 150
sqlite_query:   SELECT * FROM sold_out_flags WHERE completed_date >= date('now', '-7 days');
  → (none)
```

## "My business is Gulf Coast Vending in Tampa, Florida, Eastern time. Set the check-in radius to 150 m."

```
sqlite_execute: UPDATE settings SET value = 'Gulf Coast Vending' WHERE key = 'business_name';
sqlite_execute: UPDATE settings SET value = '-04:00' WHERE key = 'timezone_offset';
sqlite_execute: UPDATE settings SET value = '150' WHERE key = 'default_checkin_radius_m';
```

> Saved. I'll schedule everything in Eastern time (-04:00). Indoor break-room machines sit far from a street pin, so 150 m is the right policy default. You don't have a Restock form yet; it's free to create and every stop will come back with coin, items, temp, sold-out, and up to 2 photos. No signature — this is an internal restock record, not a DEX file. Want me to set the form and the 150 m radius now?

Owner: *"yes"*

```
form_create:
  title: "Restock"
  idempotency_key: "form-restock"
  fields_json: (the JSON below, passed as one string)
```

```json
[
  {"type": "section", "label": "Restock", "identifier": "sec_restock",
   "text": "Fill this in before you leave. Photograph the machine. Coin is what you pulled from the box. This is an internal restock record, not a DEX file and not a warehouse inventory count."},
  {"type": "currency", "label": "Coin collected", "identifier": "coin_collected", "required": true},
  {"type": "textarea", "label": "Items restocked", "identifier": "items_restocked", "required": true},
  {"type": "select", "label": "Temperature OK", "identifier": "temp_ok", "required": true,
   "options": ["Yes", "No", "N/A"]},
  {"type": "select", "label": "Sold out", "identifier": "sold_out", "required": true,
   "options": ["None", "Partial", "Full"]},
  {"type": "photo", "label": "Machine photo", "identifier": "machine", "max_images": 2}
]
```

```
  → form_id: 501, fields: [ ...6 fields echoed with identifiers... ]

sqlite_execute: UPDATE settings SET value = '501' WHERE key = 'restock_form_id';

policy_get: policy_id 0
policy_update:
  policy_id: 0
  settings_json: '{"geofence_enabled": true, "require_on_site": true, "checkin_radius_m": 150}'
```

The radius is on the **policy**, not on any location.

> Restock form created. I'll attach it to every machine automatically. Snack, drink, combo, coffee, and micro-market all use this same form — snack boxes mark Temperature OK as N/A. There is no signature step. Check-in radius is 150 m account-wide.

## "Add a route called North Loop."

```
sqlite_execute: INSERT INTO routes (route_name) VALUES ('North Loop');
  → lastInsertRowid = 1
```

> North Loop is set up. Add machines to it and I'll schedule them in stop order.

## "Add Harbor Office Park, contact Priya Nair, priya@harborpark.example, 813-555-0140, 400 Channelside Dr, Tampa FL 33602. Two machines on North Loop, both weekly starting Monday 2026-09-08: snack (code VM-11) at 8:00 as stop 1, drink (code VM-12) at 8:15 as stop 2. We own both boxes, no host fee. Badge 4412 at the loading dock."

```
sqlite_execute:
  INSERT INTO accounts (account_name, contact_name, contact_email, contact_phone)
  VALUES ('Harbor Office Park', 'Priya Nair', 'priya@harborpark.example', '813-555-0140');
  → lastInsertRowid = 1

sqlite_query: SELECT route_id FROM routes WHERE route_name = 'North Loop';
  → 1

sqlite_execute:
  INSERT INTO machines (account_id, route_id, stop_order, machine_code, machine_label, machine_type,
                        site_label, address, city, state, zip, access_notes,
                        service_rate, service_frequency, next_service_date, preferred_start)
  VALUES (1, 1, 1, 'VM-11', 'Harbor snack', 'snack',
          'Harbor Office Park break room', '400 Channelside Dr', 'Tampa', 'FL', '33602',
          'Badge 4412 at the loading dock.',
          0, 'weekly', '2026-09-08', '08:00');
  → lastInsertRowid = 1

sqlite_execute:
  INSERT INTO machines (account_id, route_id, stop_order, machine_code, machine_label, machine_type,
                        site_label, address, city, state, zip, access_notes,
                        service_rate, service_frequency, next_service_date, preferred_start)
  VALUES (1, 1, 2, 'VM-12', 'Harbor drink', 'drink',
          'Harbor Office Park break room', '400 Channelside Dr', 'Tampa', 'FL', '33602',
          'Badge 4412 at the loading dock. Same dock as VM-11.',
          0, 'weekly', '2026-09-08', '08:15');
  → lastInsertRowid = 2
```

Agent (first metered call this session, rule 11):

> Creating Harbor's address on ZenSched costs $0.03 for geocoding. The drink machine is at the same street, so I'll reuse that pin and not charge a second geocode. If your account isn't funded yet you'll get a prompt for the $5 activation deposit. Go ahead?

Owner: *"yes"*

```
sqlite_query:
  SELECT zensched_location_id FROM machines
  WHERE address = '400 Channelside Dr' AND city = 'Tampa'
    AND zensched_location_id IS NOT NULL AND machine_id <> 1 LIMIT 1;
  → (none; first machine at this site)

location_create:
  name: "Harbor snack"
  street_address: "400 Channelside Dr, Tampa, FL 33602"
  checkin_radius_m: 150
  idempotency_key: "loc-machine-1"
  → location_id: 9201, lat: 27.9420, lng: -82.4460, pin_quality: "street"
    billing: { meter: "geocode", units: 1, price: 0.03 }
```

The badge code is **not** in `notes`. It lives only in `machines.access_notes`. `checkin_radius_m` on the location is informational; the enforced radius is the policy.

```
event_create:
  location_id: 9201
  title: "Restock - Harbor snack"
  start_date: "2026-09-08"
  end_date:   "2026-11-06"          ← start + 59 days (60-day cap)
  idempotency_key: "event-machine-1-20260908"
  → event_id: 8001

form_assign:
  form_id: 501
  event_id: 8001
  idempotency_key: "assign-restock-8001"

sqlite_execute:
  UPDATE machines SET zensched_location_id = 9201, zensched_event_id = 8001, event_valid_until = '2026-11-06'
  WHERE machine_id = 1;

sqlite_query:
  SELECT zensched_location_id FROM machines
  WHERE address = '400 Channelside Dr' AND city = 'Tampa'
    AND zensched_location_id IS NOT NULL AND machine_id <> 2 LIMIT 1;
  → 9201
```

No second `location_create`. Same site, same pin.

```
event_create:
  location_id: 9201
  title: "Restock - Harbor drink"
  start_date: "2026-09-08"
  end_date:   "2026-11-06"
  idempotency_key: "event-machine-2-20260908"
  → event_id: 8002

form_assign: form_id 501, event_id 8002, idempotency_key "assign-restock-8002"

sqlite_execute:
  UPDATE machines SET zensched_location_id = 9201, zensched_event_id = 8002, event_valid_until = '2026-11-06'
  WHERE machine_id = 2;
```

> Added Harbor Office Park at 400 Channelside Dr. Two weekly machines on North Loop, no host fee (you own the boxes): snack VM-11 Mon 8:00, drink VM-12 Mon 8:15. One GPS pin for the site; each machine has its own event through Nov 6. The badge code is saved on your computer only; give it to Luis directly.

## "Add Bayshore Clinic, contact Maya Chen, maya@bayshore.example, 813-555-0190, 410 Bayshore Blvd, Tampa FL 33606. One combo machine (code VM-21) on North Loop as stop 3, biweekly starting Wednesday 2026-09-10 at 10:00, $25 host restock fee. Manager cell is in the access notes: 813-555-0100."

Same pattern. The agent does not re-ask about the $0.03 (owner already approved geocoding this session). Frequency is `biweekly`. New site, so a new location.

```
sqlite_execute:
  INSERT INTO accounts (account_name, contact_name, contact_email, contact_phone)
  VALUES ('Bayshore Clinic', 'Maya Chen', 'maya@bayshore.example', '813-555-0190');
  → lastInsertRowid = 2

sqlite_execute:
  INSERT INTO machines (account_id, route_id, stop_order, machine_code, machine_label, machine_type,
                        site_label, address, city, state, zip, access_notes,
                        service_rate, service_frequency, next_service_date, preferred_start)
  VALUES (2, 1, 3, 'VM-21', 'Bayshore combo', 'combo',
          'Bayshore Clinic lobby', '410 Bayshore Blvd', 'Tampa', 'FL', '33606',
          'Manager cell 813-555-0100. Ask front desk for the break-room key.',
          25.00, 'biweekly', '2026-09-10', '10:00');
  → lastInsertRowid = 3

location_create:
  name: "Bayshore combo"
  street_address: "410 Bayshore Blvd, Tampa, FL 33606"
  checkin_radius_m: 150
  idempotency_key: "loc-machine-3"
  → location_id: 9202

event_create:
  location_id: 9202
  title: "Restock - Bayshore combo"
  start_date: "2026-09-10"
  end_date:   "2026-11-08"
  idempotency_key: "event-machine-3-20260910"
  → event_id: 8003

form_assign: form_id 501, event_id 8003, idempotency_key "assign-restock-8003"

sqlite_execute:
  UPDATE machines SET zensched_location_id = 9202, zensched_event_id = 8003, event_valid_until = '2026-11-08'
  WHERE machine_id = 3;
```

> Added Bayshore Clinic, 410 Bayshore Blvd. Combo VM-21, biweekly, $25 host fee, next stop Wed Sep 10 at 10:00, North Loop stop 3. Manager cell is local only.

## "Invite Luis Ortega, luis@example.com, make him the default, and put him on North Loop."

> Inviting a technician costs $0.25. OK?

Owner: *"yes"*

```
worker_invite:
  email: "luis@example.com"
  first_name: "Luis"
  last_name: "Ortega"
  idempotency_key: "worker-luis@example.com"
  → worker_id: 601, status: "invited", invitation_sent: true
    billing: { meter: "worker_invite", units: 1, price: 0.25 }

sqlite_execute:
  INSERT INTO technicians (technician_name, email, zensched_worker_id)
  VALUES ('Luis Ortega', 'luis@example.com', 601);
  → lastInsertRowid = 1

sqlite_execute: UPDATE settings SET value = '601' WHERE key = 'default_worker_id';
sqlite_execute: UPDATE routes SET zensched_worker_id = 601 WHERE route_id = 1;
```

> Invited Luis. He'll get an email with the app link and an activation code. He's the default tech and he's on North Loop. Remember to give him Harbor's badge 4412 and the Bayshore manager cell; I keep those off ZenSched on purpose.

## "Schedule North Loop this week for Luis."

```
sqlite_query: SELECT * FROM machines_due WHERE route_name = 'North Loop';
  → 2026-09-08 | Harbor snack  | weekly   | $0  | snack | stop 1 | evt 8001 | event_needs_roll 0
               | worker 601 Luis | start_iso 2026-09-08T08:00:00-04:00 | end_iso 2026-09-08T08:15:00-04:00
               | shift-machine-1-20260908
    2026-09-08 | Harbor drink  | weekly   | $0  | drink | stop 2 | evt 8002 | event_needs_roll 0
               | worker 601 Luis | start_iso 2026-09-08T08:15:00-04:00 | end_iso 2026-09-08T08:30:00-04:00
               | shift-machine-2-20260908
    2026-09-10 | Bayshore combo| biweekly | $25 | combo | stop 3 | evt 8003 | event_needs_roll 0
               | worker 601 Luis | start_iso 2026-09-10T10:00:00-04:00 | end_iso 2026-09-10T10:15:00-04:00
               | shift-machine-3-20260910
  (3 rows)

shift_create:
  event_id: 8001
  worker_id: 601
  start: "2026-09-08T08:00:00-04:00"
  end:   "2026-09-08T08:15:00-04:00"
  idempotency_key: "shift-machine-1-20260908"
  → shift_id: 89011, status: "scheduled", forms_installed: [501]

shift_create:
  event_id: 8002
  worker_id: 601
  start: "2026-09-08T08:15:00-04:00"
  end:   "2026-09-08T08:30:00-04:00"
  idempotency_key: "shift-machine-2-20260908"
  → shift_id: 89012, status: "scheduled", forms_installed: [501]

shift_create:
  event_id: 8003
  worker_id: 601
  start: "2026-09-10T10:00:00-04:00"
  end:   "2026-09-10T10:15:00-04:00"
  idempotency_key: "shift-machine-3-20260910"
  → shift_id: 89013, status: "scheduled", forms_installed: [501]
```

> Scheduled 3 restocks on North Loop for Luis this week:
> - Mon 9/8  8:00–8:15   Harbor snack (VM-11)
> - Mon 9/8  8:15–8:30   Harbor drink (VM-12) — same building, same pin
> - Wed 9/10 10:00–10:15 Bayshore combo (VM-21), $25 host fee
>
> Luis has been notified in the app and every stop has the Restock form attached. Each stop is about $0.35 once he punches in and out and you read the photo record ($0.10 + $0.10 + $0.15). Pass him the Harbor badge and the Bayshore manager cell yourself.

Nothing is written to SQLite here. If the owner asks "schedule this week" again, the identical idempotency keys make ZenSched return the same three shifts instead of creating duplicates.

## Luis does the work

Monday 7:58, at 400 Channelside Dr, in the ZenSched app: **Check in** (GPS: 22 m from the pin, verified, $0.10). Opens **Restock** on Harbor snack: Coin collected = 42.50; Items restocked = "Chips 8, candy 12, pastry 4"; Temperature OK = N/A; Sold out = None; one photo of the face. Submits (no signature). **Check out** 8:14 ($0.10).

Monday 8:16, still in the Harbor break room (same pin): check in on Harbor drink. Restock: Coin = 61.00; Items = "Coke 10, water 6"; Temperature OK = No; Sold out = Full; two photos (face + open cooler). Notes in items: "Compressor warm, top two rows empty." Check out 8:29.

Wednesday 9:57, 410 Bayshore Blvd: check in at the lobby. Restock: Coin = 18.00; Items = "Water 8, chips 4"; Temperature OK = Yes; Sold out = Partial; one photo. Check out 10:12.

## "Record this week's visits."

```
shift_list:
  date_from: "2026-09-08"
  date_to:   "2026-09-14"
  status:    "checked_out"
  → shifts: [
      { shift_id: 89011, event_id: 8001, worker_id: 601, date: "2026-09-08", start: "08:00", end: "08:15", status: "checked_out" },
      { shift_id: 89012, event_id: 8002, worker_id: 601, date: "2026-09-08", start: "08:15", end: "08:30", status: "checked_out" },
      { shift_id: 89013, event_id: 8003, worker_id: 601, date: "2026-09-10", start: "10:00", end: "10:15", status: "checked_out" }
    ], count: 3

sqlite_query: SELECT zensched_shift_id FROM visits WHERE zensched_shift_id IN (89011, 89012, 89013);
  → (none; not yet recorded)

sqlite_query: SELECT machine_id, account_id, service_rate FROM machines WHERE zensched_event_id = 8001;
  → 1, 1, 0
```

Agent (metered read, rule 11):

> There are 3 restock records to pull, all with photos, so about $0.45 ($0.15 each). I'll read them once and keep the summaries locally. That's the last piece of the ~$0.35/stop meter (punches already billed when Luis checked in and out). OK?

Owner: *"go"*

```
form_export:
  form_id: 501
  since: "2026-09-08"
  until: "2026-09-14"
  format: "json"
  → row_count: 3, rows: [
      { submission_id: 5501, worker_id: 601, event_id: 8001, submitted_at: "2026-09-08 08:12:04",
        data: { coin_collected: 42.50, items_restocked: "Chips 8, candy 12, pastry 4",
                temp_ok: "n_a", sold_out: "none" },
        media: [ { cdn_url: "https://cdn.zensched.com/m/.../s1.jpg" } ] },
      { submission_id: 5502, worker_id: 601, event_id: 8002, submitted_at: "2026-09-08 08:26:40",
        data: { coin_collected: 61.00, items_restocked: "Coke 10, water 6. Compressor warm, top two rows empty.",
                temp_ok: "no", sold_out: "full" },
        media: [ { cdn_url: "https://cdn.zensched.com/m/.../d1.jpg" },
                 { cdn_url: "https://cdn.zensched.com/m/.../d2.jpg" } ] },
      { submission_id: 5503, worker_id: 601, event_id: 8003, submitted_at: "2026-09-10 10:10:18",
        data: { coin_collected: 18.00, items_restocked: "Water 8, chips 4",
                temp_ok: "yes", sold_out: "partial" },
        media: [ { cdn_url: "https://cdn.zensched.com/m/.../b1.jpg" } ] }
    ]
    billing: { meter: "form_media", units: 3, price: 0.45 }

shift_status: shift_id 89011
  → status "checked_out", actual_in "2026-09-08T07:58:10-04:00", actual_out "2026-09-08T08:14:05-04:00",
    punches: [ { type: "in", gps_verified: true, distance_from_site_m: 22 },
               { type: "out", gps_verified: true, distance_from_site_m: 18 } ]
(free)

sqlite_execute:
  INSERT INTO visits (account_id, machine_id, completed_date, amount,
                      zensched_shift_id, zensched_event_id, zensched_worker_id,
                      actual_in, actual_out, gps_verified, report_dc_id,
                      coin_collected, items_restocked, temp_ok, sold_out, photo_urls)
  VALUES (1, 1, '2026-09-08', 0,
          89011, 8001, 601,
          '2026-09-08T07:58:10-04:00', '2026-09-08T08:14:05-04:00', 1, 5501,
          42.50, 'Chips 8, candy 12, pastry 4', 'N/A', 'None',
          '["https://cdn.zensched.com/m/.../s1.jpg"]');
  -- trigger: machines.next_service_date for Harbor snack → 2026-09-15 (+7)
  -- trigger: visits.technician_id → 1 (Luis)
  -- trigger: visits.duration_minutes → 16

sqlite_execute:
  INSERT INTO visits (account_id, machine_id, completed_date, amount,
                      zensched_shift_id, zensched_event_id, zensched_worker_id,
                      actual_in, actual_out, gps_verified, report_dc_id,
                      coin_collected, items_restocked, temp_ok, sold_out, photo_urls)
  VALUES (1, 2, '2026-09-08', 0,
          89012, 8002, 601,
          '2026-09-08T08:16:02-04:00', '2026-09-08T08:29:18-04:00', 1, 5502,
          61.00, 'Coke 10, water 6. Compressor warm, top two rows empty.', 'No', 'Full',
          '["https://cdn.zensched.com/m/.../d1.jpg","https://cdn.zensched.com/m/.../d2.jpg"]');
  -- trigger: Harbor drink → 2026-09-15 (+7)

sqlite_execute:
  INSERT INTO visits (account_id, machine_id, completed_date, amount,
                      zensched_shift_id, zensched_event_id, zensched_worker_id,
                      actual_in, actual_out, gps_verified, report_dc_id,
                      coin_collected, items_restocked, temp_ok, sold_out, photo_urls)
  VALUES (2, 3, '2026-09-10', 25.00,
          89013, 8003, 601,
          '2026-09-10T09:57:40-04:00', '2026-09-10T10:12:11-04:00', 1, 5503,
          18.00, 'Water 8, chips 4', 'Yes', 'Partial',
          '["https://cdn.zensched.com/m/.../b1.jpg"]');
  -- trigger: Bayshore combo → 2026-09-24 (+14)
```

> Recorded 3 restocks, all GPS-verified.
>
> **Flag — Monday, Harbor drink:** Luis marked **Full sold out** and **Temperature No** — *"Compressor warm, top two rows empty."* 2 photos. That's a service call, not just a restock.
>
> **Flag — Wednesday, Bayshore combo:** Partial sold out on water. Next due Sep 24. $25 host fee ready to invoice.
>
> Harbor snack: $42.50 coin, chips + candy + pastry, temp N/A, next due Sep 15.

## "Coin log for last week, and anything sold out."

```
sqlite_query: SELECT * FROM coin_log WHERE completed_date BETWEEN '2026-09-08' AND '2026-09-14';
  → 2026-09-10 | Bayshore combo | $18.00 | Water 8, chips 4 | Yes | Partial | Luis
    2026-09-08 | Harbor drink   | $61.00 | Coke 10, water 6... | No | Full | Luis
    2026-09-08 | Harbor snack   | $42.50 | Chips 8, candy 12, pastry 4 | N/A | None | Luis

sqlite_query: SELECT * FROM sold_out_flags WHERE completed_date BETWEEN '2026-09-08' AND '2026-09-14';
  → Full    | Harbor drink   | temp No
    Partial | Bayshore combo | temp Yes
```

> Your copy from the Restock form — not a DEX file. **$121.50 coin** across 3 boxes.
>
> Sold out: Harbor drink is Full (and the cooler is warm — send a tech). Bayshore combo is Partial (water). Harbor snack was fine.

## "Draft invoices for anyone with a host fee."

```
sqlite_query: SELECT * FROM visits_to_invoice;
  → Bayshore Clinic | 1 visit | 25.00 | 2026-09-10 .. 2026-09-10
  (Harbor's $0 visits are omitted)

sqlite_execute:
  INSERT INTO invoices (account_id, invoice_date, due_date, total_amount, line_items)
  SELECT v.account_id, date('now'),
         date('now', '+' || (SELECT value FROM settings WHERE key='invoice_due_days') || ' days'),
         SUM(v.amount),
         json_group_array(json_object('visit_id', v.visit_id, 'date', v.completed_date, 'machine', m.machine_label,
                                      'amount', v.amount, 'shift_id', v.zensched_shift_id, 'coin', v.coin_collected,
                                      'sold_out', v.sold_out))
  FROM visits v JOIN machines m ON m.machine_id = v.machine_id
  WHERE v.invoiced = 0 AND v.amount > 0 AND v.account_id = 2 GROUP BY v.account_id;

sqlite_execute: UPDATE visits SET invoiced = 1 WHERE invoiced = 0 AND amount > 0 AND account_id = 2;
sqlite_query:   SELECT invoice_number, invoice_date, due_date, total_amount FROM invoices WHERE invoice_id = last_insert_rowid();
  → INV-2026-0001 | 2026-09-10 | 2026-10-10 | 25.00     (number assigned by trigger)
```

The agent then writes the invoice out as text:

> Harbor's boxes have no host fee, so nothing to invoice there (the $103.50 coin is yours). One invoice for Bayshore. Paste it into an email.
>
> ```
> Gulf Coast Vending
> Invoice INV-2026-0001
> To: Bayshore Clinic (maya@bayshore.example)
> Date: Sep 10, 2026    Due: Oct 10, 2026
>
>   Sep 10    Restock, Bayshore combo, 410 Bayshore Blvd    $25.00
>
> Total due: $25.00
> Visit GPS-verified at the site.
> ```
>
> Say "sent" when it's out and I'll note the date. Want me to open a service call on the Harbor drink compressor?

## "Sent. Bayshore already paid."

```
sqlite_execute: UPDATE invoices SET sent_date = date('now') WHERE invoice_number = 'INV-2026-0001';
sqlite_execute: UPDATE invoices SET paid = 1, paid_date = date('now') WHERE invoice_number = 'INV-2026-0001';
```

> Marked INV-2026-0001 sent and paid.

## Eight weeks later: "Schedule this week."

US daylight saving time ended on Sunday 2026-11-01, so Tampa is now `-05:00`. The `machines_due` view stamps whatever `settings.timezone_offset` holds onto `start_iso` / `end_iso`, so the agent updates the setting first (SKILL.md rule 8); otherwise every November shift would land an hour late.

```
sqlite_execute: UPDATE settings SET value = '-05:00' WHERE key = 'timezone_offset';

sqlite_query: SELECT * FROM machines_due;
  → 2026-11-10 | Harbor snack | weekly | evt 8001 | event_valid_until 2026-11-06 | event_needs_roll 1
               | start_iso 2026-11-10T08:00:00-05:00 | end_iso 2026-11-10T08:15:00-05:00 | ...

event_create:
  location_id: 9201
  title: "Restock - Harbor snack"
  start_date: "2026-11-10"
  end_date:   "2027-01-08"
  idempotency_key: "event-machine-1-20261110"
  → event_id: 8101

form_assign: form_id 501, event_id 8101, idempotency_key "assign-restock-8101"
sqlite_execute: UPDATE machines SET zensched_event_id = 8101, event_valid_until = '2027-01-08' WHERE machine_id = 1;

shift_create: event_id 8101, worker_id 601, start "2026-11-10T08:00:00-05:00",
              end "2026-11-10T08:15:00-05:00", idempotency_key "shift-machine-1-20261110"
```

(Same roll for Harbor drink if its window has also expired. Bayshore's biweekly date may or may not fall in this week.)

> Scheduled Harbor snack for Tue Nov 10 8:00. Its ZenSched event was about to expire (Nov 6), so I renewed it through Jan 8. Same pin as Harbor drink. Clocks changed on Nov 1, so I switched your schedule offset to -05:00 first.

## Summary of who stored what

| Thing | Where | Why |
|---|---|---|
| Harbor + Bayshore contacts, cadence, $0 vs $25 host fee, route, stop order | SQLite | CRM; ZenSched does not model rates, routes, or recurrence |
| Badge 4412, Bayshore manager cell, commission notes | SQLite **only** | Privacy; never sent to ZenSched |
| Each site's GPS location (Harbor shared by two machines) | ZenSched (integer ID in `machines`) | Needed for geofenced check-in |
| Each machine's current ≤60-day event and its end date | ZenSched (integer ID + `event_valid_until` in `machines`) | Shifts hang off events; renewed by the agent |
| The Restock form | ZenSched (ID in `settings`) | Installed on the tech's phone per shift |
| Luis, his invite, his app | ZenSched (integer ID in `technicians` and `routes`) | Workforce and notifications |
| The week's three shifts | ZenSched only | Live schedule; never copied |
| GPS punches, actual times | ZenSched only | Verified record; queried via `shift_status` / `timesheet_export` |
| Three restock records with photos | ZenSched (originals); summary + photo URLs in `visits` | Read once (metered), then coin log / invoices from SQLite |
| Three `visits` rows referencing shift and submission IDs | SQLite | Coin extract + host billing |
| One invoice, paid | SQLite | Host fee only; coin is not an invoice line |
