-- ZenSched Vending-Route Local Database Schema
-- SQLite database for host accounts, routes, machines, cadence, restock
-- visit summaries (coin, items, temp, sold-out), and host billing.
-- DO NOT duplicate live schedule data from ZenSched (shifts, punches, timesheets).
--
-- HOW TO LOAD THIS FILE
--   Normal path: paste this whole file into your AI chat and say
--   "Create these tables in my vending-ops database. Run each statement one at a time."
--   The AI runs each statement through the SQLite MCP tool (sqlite_execute).
--   Most SQLite MCP tools accept ONE statement per call, so every statement
--   below ends with a semicolon and stands alone.
--
--   Alternative (if you have the sqlite3 command-line tool):
--     sqlite3 vending-ops.db < schema.sql
--
-- Every statement is idempotent (IF NOT EXISTS / INSERT OR IGNORE), so it is
-- safe to run this file again on an existing database.
--
-- NOT A DEX / TELEMETRY / WAREHOUSE SYSTEM. coin_log is the owner's local
-- extract of what the tech typed on the Restock form (date, machine, coin,
-- items, temp, sold-out). It is not a DEX file, not an MDB pull, not a
-- warehouse pick list, and not cash-drawer reconciliation. GPS proves the
-- tech was at the building, not that every spiral was filled correctly.
--
-- PRIVACY: machines.access_notes (badge, loading dock, manager cell, gate)
-- and accounts.commission_notes (split %, who owns the machine) live ONLY
-- in this file on your computer. They are never sent to ZenSched. SKILL.md
-- forbids the agent from putting them in any ZenSched notes field.
--
-- ONE LOCATION PER MACHINE OR SITE. Default: one ZenSched location per
-- machine (loc-machine-{machine_id}). A second machine at the same
-- street + city reuses the first machine's zensched_location_id (one
-- geocode per site). Each machine still gets its own rolling <=60-day event.

-- Foreign keys are OFF by default in SQLite. This must be run once per
-- connection for ON DELETE CASCADE to work. SKILL.md tells the agent to run it
-- at the start of each session.
PRAGMA foreign_keys = ON;

-- Settings: small key/value store so the agent does not have to be re-told the
-- basics every session (timezone, default tech, business name, form id).
-- default_checkin_radius_m is informational: the radius ZenSched enforces is
-- the account POLICY's, set with policy_update(0, {"checkin_radius_m": N}).
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT
);

INSERT OR IGNORE INTO settings (key, value) VALUES ('business_name', 'My Vending Co');
INSERT OR IGNORE INTO settings (key, value) VALUES ('timezone_offset', '-05:00');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_worker_id', NULL);
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_shift_start', '08:00');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_shift_minutes', '15');
INSERT OR IGNORE INTO settings (key, value) VALUES ('invoice_due_days', '30');
INSERT OR IGNORE INTO settings (key, value) VALUES ('invoice_prefix', 'INV');
INSERT OR IGNORE INTO settings (key, value) VALUES ('restock_form_id', NULL);
INSERT OR IGNORE INTO settings (key, value) VALUES ('event_window_days', '60');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_checkin_radius_m', '150');

-- Accounts: the host businesses that own the site (office park, school,
-- clinic, factory). commission_notes are LOCAL ONLY.
-- Many operators own the machines and keep the coin (service_rate on each
-- machine is then 0). Some charge the host a per-stop restock fee.
CREATE TABLE IF NOT EXISTS accounts (
  account_id INTEGER PRIMARY KEY AUTOINCREMENT,
  account_name TEXT NOT NULL,
  contact_name TEXT,
  contact_email TEXT,
  contact_phone TEXT,
  billing_email TEXT,
  commission_notes TEXT,                            -- LOCAL ONLY: split %, who owns the box
  billing_notes TEXT,
  is_active INTEGER DEFAULT 1,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Routes: named loops the tech runs (North Loop, Downtown). Default tech
-- for every machine on the route unless the machine overrides it.
CREATE TABLE IF NOT EXISTS routes (
  route_id INTEGER PRIMARY KEY AUTOINCREMENT,
  route_name TEXT NOT NULL UNIQUE,
  zensched_worker_id INTEGER,                       -- default tech for this route
  notes TEXT,
  is_active INTEGER DEFAULT 1,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Machines: one restock unit. Cadence lives here (not on the account)
-- because a drink box and a snack box at the same site can restock on
-- different weeks.
-- One ZenSched LOCATION per machine, or shared with another machine at
-- the same site (reuse zensched_location_id). One rolling EVENT per
-- machine (zensched_event_id + event_valid_until, <=60 days).
CREATE TABLE IF NOT EXISTS machines (
  machine_id INTEGER PRIMARY KEY AUTOINCREMENT,
  account_id INTEGER NOT NULL,
  route_id INTEGER,
  stop_order INTEGER DEFAULT 1
    CHECK (stop_order IS NULL OR stop_order >= 1),
  machine_code TEXT,                                -- VM-12, Snack A
  machine_label TEXT NOT NULL,                      -- 'Harbor snack' — the name sent to ZenSched
  machine_type TEXT NOT NULL DEFAULT 'combo'
    CHECK (machine_type IN ('snack', 'drink', 'combo', 'coffee', 'micro-market', 'other')),
  site_label TEXT,                                  -- 'Harbor Office Park break room'
  address TEXT NOT NULL,
  address_line2 TEXT,
  city TEXT,
  state TEXT,
  zip TEXT,
  access_notes TEXT,                                -- LOCAL ONLY: badge, dock, manager cell
  service_rate REAL NOT NULL DEFAULT 0,             -- host restock fee; 0 = operator keeps coin only
  service_frequency TEXT NOT NULL
    CHECK (service_frequency IN ('weekly', 'biweekly', 'monthly', 'quarterly', 'on-demand')),
  next_service_date TEXT,                           -- ISO date: '2026-09-08'
  last_service_date TEXT,
  preferred_start TEXT
    CHECK (preferred_start IS NULL OR preferred_start GLOB '[0-2][0-9]:[0-5][0-9]'),
  zensched_worker_id INTEGER,                       -- pin this machine to a tech; else route; else default
  zensched_location_id INTEGER,                     -- from location_create (per machine, or reused per site)
  zensched_event_id INTEGER,                        -- current <=60-day window
  event_valid_until TEXT,                           -- last day the current event covers
  is_active INTEGER DEFAULT 1,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (account_id) REFERENCES accounts(account_id) ON DELETE CASCADE,
  FOREIGN KEY (route_id) REFERENCES routes(route_id) ON DELETE SET NULL
);

-- Technicians: your roster. zensched_worker_id comes from worker_invite.
CREATE TABLE IF NOT EXISTS technicians (
  technician_id INTEGER PRIMARY KEY AUTOINCREMENT,
  technician_name TEXT NOT NULL,
  email TEXT,
  phone TEXT,
  zensched_worker_id INTEGER UNIQUE,
  is_active INTEGER DEFAULT 1,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Visits: one row per COMPLETED restock, linked to the ZenSched shift and
-- the Restock form submission. This is the billing record plus a small
-- summary so coin_log / sold_out_flags are local queries.
-- temp_ok / sold_out are CHECK-constrained to the form's option labels.
CREATE TABLE IF NOT EXISTS visits (
  visit_id INTEGER PRIMARY KEY AUTOINCREMENT,
  account_id INTEGER NOT NULL,
  machine_id INTEGER NOT NULL,
  technician_id INTEGER,
  completed_date TEXT NOT NULL,                     -- ISO date: '2026-09-08'
  amount REAL NOT NULL DEFAULT 0,                   -- snapshot of machines.service_rate
  zensched_shift_id INTEGER UNIQUE,
  zensched_event_id INTEGER,
  zensched_worker_id INTEGER,
  actual_in TEXT,
  actual_out TEXT,
  duration_minutes INTEGER,
  gps_verified INTEGER,
  report_dc_id INTEGER,                             -- Restock form submission_id
  coin_collected REAL,                              -- currency from the form
  items_restocked TEXT,                             -- textarea from the form
  temp_ok TEXT CHECK (temp_ok IS NULL OR temp_ok IN ('Yes', 'No', 'N/A')),
  sold_out TEXT CHECK (sold_out IS NULL OR sold_out IN ('None', 'Partial', 'Full')),
  photo_urls TEXT,                                  -- JSON array of media URLs
  notes TEXT,
  invoiced INTEGER DEFAULT 0,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (account_id) REFERENCES accounts(account_id) ON DELETE CASCADE,
  FOREIGN KEY (machine_id) REFERENCES machines(machine_id) ON DELETE CASCADE,
  FOREIGN KEY (technician_id) REFERENCES technicians(technician_id) ON DELETE SET NULL
);

-- Invoices: host billing records (service_rate totals). Coin collected is
-- not an invoice line — it is the operator's cash, in coin_log.
-- invoice_number is filled in automatically by a trigger if left NULL.
CREATE TABLE IF NOT EXISTS invoices (
  invoice_id INTEGER PRIMARY KEY AUTOINCREMENT,
  account_id INTEGER NOT NULL,
  invoice_number TEXT UNIQUE,
  invoice_date TEXT NOT NULL,
  due_date TEXT,
  total_amount REAL NOT NULL,
  paid INTEGER DEFAULT 0,
  paid_date TEXT,
  sent_date TEXT,
  line_items TEXT,                                  -- JSON array of visit references
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (account_id) REFERENCES accounts(account_id) ON DELETE CASCADE
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_machines_next_service ON machines(next_service_date, is_active);
CREATE INDEX IF NOT EXISTS idx_machines_account ON machines(account_id);
CREATE INDEX IF NOT EXISTS idx_machines_route ON machines(route_id, stop_order);
CREATE INDEX IF NOT EXISTS idx_machines_zensched_location ON machines(zensched_location_id);
CREATE INDEX IF NOT EXISTS idx_machines_zensched_event ON machines(zensched_event_id);
CREATE INDEX IF NOT EXISTS idx_technicians_worker ON technicians(zensched_worker_id);
CREATE INDEX IF NOT EXISTS idx_visits_account ON visits(account_id, completed_date);
CREATE INDEX IF NOT EXISTS idx_visits_machine ON visits(machine_id, completed_date);
CREATE INDEX IF NOT EXISTS idx_visits_invoiced ON visits(invoiced);
CREATE INDEX IF NOT EXISTS idx_invoices_account ON invoices(account_id);
CREATE INDEX IF NOT EXISTS idx_invoices_paid ON invoices(paid);

-- Keep updated_at current
CREATE TRIGGER IF NOT EXISTS update_account_timestamp
AFTER UPDATE ON accounts
BEGIN
  UPDATE accounts SET updated_at = datetime('now') WHERE account_id = NEW.account_id;
END;

CREATE TRIGGER IF NOT EXISTS update_route_timestamp
AFTER UPDATE ON routes
BEGIN
  UPDATE routes SET updated_at = datetime('now') WHERE route_id = NEW.route_id;
END;

CREATE TRIGGER IF NOT EXISTS update_machine_timestamp
AFTER UPDATE ON machines
BEGIN
  UPDATE machines SET updated_at = datetime('now') WHERE machine_id = NEW.machine_id;
END;

CREATE TRIGGER IF NOT EXISTS update_technician_timestamp
AFTER UPDATE ON technicians
BEGIN
  UPDATE technicians SET updated_at = datetime('now') WHERE technician_id = NEW.technician_id;
END;

-- Fill technician_id from the roster when the agent only has the ZenSched worker id.
CREATE TRIGGER IF NOT EXISTS fill_visit_technician
AFTER INSERT ON visits
WHEN NEW.technician_id IS NULL AND NEW.zensched_worker_id IS NOT NULL
BEGIN
  UPDATE visits
  SET technician_id = (SELECT technician_id FROM technicians WHERE zensched_worker_id = NEW.zensched_worker_id)
  WHERE visit_id = NEW.visit_id;
END;

-- Fill duration_minutes from punches when the agent leaves it NULL.
CREATE TRIGGER IF NOT EXISTS fill_visit_duration_insert
AFTER INSERT ON visits
WHEN NEW.duration_minutes IS NULL AND NEW.actual_in IS NOT NULL AND NEW.actual_out IS NOT NULL
BEGIN
  UPDATE visits
  SET duration_minutes = CAST(round((julianday(NEW.actual_out) - julianday(NEW.actual_in)) * 1440) AS INTEGER)
  WHERE visit_id = NEW.visit_id;
END;

CREATE TRIGGER IF NOT EXISTS fill_visit_duration_update
AFTER UPDATE OF actual_in, actual_out ON visits
WHEN NEW.duration_minutes IS NULL AND NEW.actual_in IS NOT NULL AND NEW.actual_out IS NOT NULL
BEGIN
  UPDATE visits
  SET duration_minutes = CAST(round((julianday(NEW.actual_out) - julianday(NEW.actual_in)) * 1440) AS INTEGER)
  WHERE visit_id = NEW.visit_id;
END;

-- Recording a completed visit automatically advances that machine's cadence.
-- quarterly is +90 days (not +3 months). on-demand clears the next date.
-- The agent should NOT hand-maintain next_service_date after this.
-- A one-off recorded on a recurring machine also moves the cadence; if the
-- owner wants the regular stop kept, set next_service_date back explicitly.
CREATE TRIGGER IF NOT EXISTS advance_service_date_on_visit
AFTER INSERT ON visits
BEGIN
  UPDATE machines
  SET last_service_date = NEW.completed_date,
      next_service_date = CASE service_frequency
        WHEN 'weekly'    THEN date(NEW.completed_date, '+7 days')
        WHEN 'biweekly'  THEN date(NEW.completed_date, '+14 days')
        WHEN 'monthly'   THEN date(NEW.completed_date, '+1 month')
        WHEN 'quarterly' THEN date(NEW.completed_date, '+90 days')
        ELSE NULL
      END
  WHERE machine_id = NEW.machine_id;
END;

-- Auto-number invoices: INV-2026-0001, INV-2026-0002, ...
CREATE TRIGGER IF NOT EXISTS number_invoice
AFTER INSERT ON invoices
WHEN NEW.invoice_number IS NULL
BEGIN
  UPDATE invoices
  SET invoice_number = (SELECT COALESCE(value, 'INV') FROM settings WHERE key = 'invoice_prefix')
                       || '-' || strftime('%Y', NEW.invoice_date)
                       || '-' || printf('%04d', NEW.invoice_id)
  WHERE invoice_id = NEW.invoice_id;
END;

-- Who is due in the next 7 days (today + 6). The agent's weekly scheduling
-- query. One row = one shift_create call. Columns ending in _iso are ready
-- to pass as shift_create start/end; idempotency_key is ready too.
-- event_needs_roll = 1 means create a new ZenSched event first (see SKILL.md).
-- access_notes is included so the agent can tell the owner to pass it to the
-- tech; it must never go into a ZenSched field.
-- Worker: machine pin, else route default, else settings.default_worker_id.
CREATE VIEW IF NOT EXISTS machines_due AS
SELECT
  m.machine_id,
  m.machine_code,
  m.machine_label,
  m.machine_type,
  m.site_label,
  m.address,
  m.city,
  m.state,
  m.zip,
  m.access_notes,
  m.service_rate,
  m.service_frequency,
  m.next_service_date,
  m.stop_order,
  m.zensched_location_id,
  m.zensched_event_id,
  m.event_valid_until,
  CASE WHEN m.event_valid_until IS NULL OR m.event_valid_until < m.next_service_date THEN 1 ELSE 0 END AS event_needs_roll,
  COALESCE(m.preferred_start, (SELECT value FROM settings WHERE key = 'default_shift_start')) AS start_time,
  CAST(COALESCE((SELECT value FROM settings WHERE key = 'default_shift_minutes'), '15') AS INTEGER) AS default_minutes,
  a.account_id,
  a.account_name,
  r.route_id,
  r.route_name,
  COALESCE(m.zensched_worker_id, r.zensched_worker_id,
           (SELECT CAST(value AS INTEGER) FROM settings WHERE key = 'default_worker_id')) AS worker_id,
  (SELECT t.technician_name FROM technicians t
    WHERE t.zensched_worker_id = COALESCE(m.zensched_worker_id, r.zensched_worker_id,
           (SELECT CAST(value AS INTEGER) FROM settings WHERE key = 'default_worker_id'))) AS technician_name,
  m.next_service_date || 'T'
    || COALESCE(m.preferred_start, (SELECT value FROM settings WHERE key = 'default_shift_start'))
    || ':00' || (SELECT value FROM settings WHERE key = 'timezone_offset') AS start_iso,
  strftime('%Y-%m-%dT%H:%M:%S', datetime(
      m.next_service_date || ' '
      || COALESCE(m.preferred_start, (SELECT value FROM settings WHERE key = 'default_shift_start'))
      || ':00',
      '+' || CAST(COALESCE((SELECT value FROM settings WHERE key = 'default_shift_minutes'), '15') AS INTEGER) || ' minutes'))
    || (SELECT value FROM settings WHERE key = 'timezone_offset') AS end_iso,
  'shift-machine-' || m.machine_id || '-' || strftime('%Y%m%d', m.next_service_date) AS idempotency_key
FROM machines m
JOIN accounts a ON a.account_id = m.account_id AND a.is_active = 1
LEFT JOIN routes r ON r.route_id = m.route_id AND r.is_active = 1
WHERE m.is_active = 1
  AND m.next_service_date IS NOT NULL
  AND m.next_service_date <= date('now', '+7 days')
ORDER BY m.next_service_date,
         COALESCE(r.route_name, ''),
         COALESCE(m.stop_order, 1),
         COALESCE(m.preferred_start, (SELECT value FROM settings WHERE key = 'default_shift_start')),
         m.machine_label;

-- Machines whose current ZenSched event expires within 14 days (or has none)
-- and that belong to an active account. Roll these proactively.
CREATE VIEW IF NOT EXISTS events_expiring AS
SELECT
  m.machine_id,
  m.machine_label,
  m.site_label,
  m.address,
  a.account_name,
  m.zensched_location_id,
  m.zensched_event_id,
  m.event_valid_until
FROM machines m
JOIN accounts a ON a.account_id = m.account_id AND a.is_active = 1
WHERE m.is_active = 1
  AND (m.event_valid_until IS NULL OR m.event_valid_until <= date('now', '+14 days'))
ORDER BY m.event_valid_until;

-- Route overview: every active machine on an active route, with next date.
CREATE VIEW IF NOT EXISTS route_board AS
SELECT
  r.route_id,
  r.route_name,
  r.zensched_worker_id AS route_worker_id,
  (SELECT t.technician_name FROM technicians t
    WHERE t.zensched_worker_id = r.zensched_worker_id) AS route_technician,
  m.machine_id,
  m.machine_code,
  m.machine_label,
  m.machine_type,
  m.site_label,
  m.address,
  m.city,
  m.stop_order,
  m.service_frequency,
  m.next_service_date,
  m.service_rate,
  m.zensched_location_id,
  m.zensched_event_id,
  a.account_name
FROM routes r
JOIN machines m ON m.route_id = r.route_id AND m.is_active = 1
JOIN accounts a ON a.account_id = m.account_id AND a.is_active = 1
WHERE r.is_active = 1
ORDER BY r.route_name, COALESCE(m.stop_order, 1), m.machine_label;

-- Completed restocks that have a host fee and have not been invoiced yet.
-- amount = 0 visits (operator-owned boxes) are omitted — they are not billed.
CREATE VIEW IF NOT EXISTS visits_to_invoice AS
SELECT
  a.account_id,
  a.account_name,
  a.contact_email,
  a.billing_email,
  a.billing_notes,
  COUNT(v.visit_id)       AS visit_count,
  SUM(v.amount)           AS total_amount,
  MIN(v.completed_date)   AS first_visit_date,
  MAX(v.completed_date)   AS last_visit_date
FROM visits v
JOIN accounts a ON a.account_id = v.account_id
WHERE v.invoiced = 0
  AND v.amount > 0
GROUP BY a.account_id
ORDER BY a.account_name;

-- Unpaid invoices, oldest first, with aging buckets.
CREATE VIEW IF NOT EXISTS invoices_outstanding AS
SELECT
  i.invoice_id,
  i.invoice_number,
  a.account_name,
  a.billing_email,
  a.contact_email,
  i.invoice_date,
  i.due_date,
  i.total_amount,
  i.sent_date,
  CASE WHEN i.due_date < date('now') THEN 1 ELSE 0 END AS overdue,
  CASE WHEN i.due_date >= date('now') THEN 0
       ELSE CAST(julianday(date('now')) - julianday(i.due_date) AS INTEGER) END AS days_overdue,
  CASE WHEN i.due_date >= date('now') THEN 'current'
       WHEN julianday(date('now')) - julianday(i.due_date) <= 30 THEN '1-30'
       WHEN julianday(date('now')) - julianday(i.due_date) <= 60 THEN '31-60'
       WHEN julianday(date('now')) - julianday(i.due_date) <= 90 THEN '61-90'
       ELSE '90+' END AS aging_bucket
FROM invoices i
JOIN accounts a ON a.account_id = i.account_id
WHERE i.paid = 0
ORDER BY i.due_date;

-- Owner's local coin-box extract: one row per restock that recorded coin.
-- This is the owner's copy, not a DEX file and not cash-drawer accounting.
CREATE VIEW IF NOT EXISTS coin_log AS
SELECT
  v.visit_id,
  v.completed_date,
  m.machine_label,
  m.machine_code,
  m.site_label,
  m.address,
  a.account_name,
  v.coin_collected,
  v.items_restocked,
  v.temp_ok,
  v.sold_out,
  COALESCE(t.technician_name, 'tech ' || v.zensched_worker_id) AS technician,
  v.zensched_shift_id,
  v.report_dc_id
FROM visits v
JOIN machines m ON m.machine_id = v.machine_id
JOIN accounts a ON a.account_id = v.account_id
LEFT JOIN technicians t ON t.technician_id = v.technician_id
WHERE v.coin_collected IS NOT NULL
ORDER BY v.completed_date DESC, a.account_name, m.machine_label;

-- Restocks where the tech marked the machine partial or fully sold out.
-- Lead with these when the owner asks how the route went.
CREATE VIEW IF NOT EXISTS sold_out_flags AS
SELECT
  v.visit_id,
  v.completed_date,
  m.machine_label,
  m.machine_code,
  m.site_label,
  a.account_name,
  v.sold_out,
  v.temp_ok,
  v.items_restocked,
  v.coin_collected,
  COALESCE(t.technician_name, 'tech ' || v.zensched_worker_id) AS technician,
  r.route_name
FROM visits v
JOIN machines m ON m.machine_id = v.machine_id
JOIN accounts a ON a.account_id = v.account_id
LEFT JOIN technicians t ON t.technician_id = v.technician_id
LEFT JOIN routes r ON r.route_id = m.route_id
WHERE v.sold_out IN ('Partial', 'Full')
ORDER BY CASE v.sold_out WHEN 'Full' THEN 0 ELSE 1 END, v.completed_date DESC;
