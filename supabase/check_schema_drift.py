#!/usr/bin/env python3
"""
DrsListing — Schema-drift checker.

Compares the object inventory DECLARED in the local `supabase/migrations/`
SQL files against the LIVE Supabase database, and reports anything the live
DB is missing (or has with a different type).

What it checks, per migration file:
  - Tables         (CREATE TABLE ...)  and every column named inside them
  - Added columns  (ALTER TABLE ... ADD COLUMN [IF NOT EXISTS] ...)
  - Functions      (CREATE [OR REPLACE] FUNCTION name(args))
  - Indexes        (CREATE [UNIQUE] INDEX [IF NOT EXISTS] name ON ...)
  - RLS policies   (CREATE POLICY "name" ON [schema.]table)
  - Triggers       (CREATE TRIGGER name ... ON [public.]table)
  - Storage buckets (INSERT INTO storage.buckets VALUES ('id', ...))

It does NOT try to be a full SQL parser — it uses targeted regexes matched
against the exact dialect this repo's migrations use. Objects are matched by
name (functions also by normalized identity-argument signature). Column
TYPES are compared with a tolerant normalizer (VARCHAR(255) == character
varying, TEXT[] == array-of-text, etc.); NULLABILITY / DEFAULTS / lengths
are intentionally not compared.

Usage:
    python supabase/check_schema_drift.py                 # human report
    python supabase/check_schema_drift.py --json          # machine-readable
    python supabase/check_schema_drift.py --migrations-dir <path>
    python supabase/check_schema_drift.py --exit-zero     # always exit 0
    python supabase/check_schema_drift.py --reconcile     # apply missing
                                                          # objects to live DB
    python supabase/check_schema_drift.py --reconcile --dry-run  # preview only
    python supabase/check_schema_drift.py --project-ref <ref>   # check a
                                                          # different project
                                                          # (e.g. a scratch
                                                          # project)

--reconcile: generates idempotent SQL for every MISSING object (tables,
columns, functions, indexes, policies, triggers, buckets) from the defining
statements in the migration files and applies them to the live DB in
dependency order, then re-checks. DROP + CREATE wrappers are used for
policies and triggers (which have no IF NOT EXISTS); buckets get
ON CONFLICT (id) DO NOTHING. COLUMN TYPE mismatches are reported but never
auto-altered (data risk) — fix those by hand.

Exit code is 1 when drift remains, 0 otherwise (unless --exit-zero).

The SUPABASE_ACCESS_TOKEN is read from .env.deploy (recommended) or the
environment, exactly like the other verify/deploy scripts.
"""

import json
import os
import re
import sys
import urllib.error
import urllib.request

PROJECT_REF = "qxukzqdsmlurollltrjp"
BASE_URL = f"https://api.supabase.com/v1/projects/{PROJECT_REF}"
DEPLOY_ENV_FILE = ".env.deploy"
DEFAULT_MIGRATIONS_DIR = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "migrations"
)

# ─────────────────────────────────────────────────────────────────────
# Type normalisation
# ─────────────────────────────────────────────────────────────────────

# Migration-side shorthand -> canonical information_schema.data_type value.
TYPE_MAP = {
    "text": "text",
    "varchar": "character varying",
    "char": "character",
    "timestamp": "timestamp without time zone",
    "timestamptz": "timestamp with time zone",
    "date": "date",
    "time": "time without time zone",
    "timetz": "time with time zone",
    "boolean": "boolean",
    "bool": "boolean",
    "jsonb": "jsonb",
    "json": "json",
    "uuid": "uuid",
    "integer": "integer",
    "int": "integer",
    "int4": "integer",
    "serial": "integer",
    "bigint": "bigint",
    "int8": "bigint",
    "bigserial": "bigint",
    "smallint": "smallint",
    "int2": "smallint",
    "numeric": "numeric",
    "decimal": "numeric",
    "real": "real",
    "float4": "real",
    "double precision": "double precision",
    "float8": "double precision",
    "bytea": "bytea",
    "money": "money",
}

# storage udt_name (drops the leading '_' of the array type) -> canonical.
ARRAY_ELEMENT_MAP = {
    "text": "text",
    "varchar": "character varying",
    "int2": "smallint",
    "int4": "integer",
    "int8": "bigint",
    "bool": "boolean",
    "float4": "real",
    "float8": "double precision",
    "numeric": "numeric",
    "jsonb": "jsonb",
    "json": "json",
    "uuid": "uuid",
    "timestamp": "timestamp without time zone",
    "timestamptz": "timestamp with time zone",
}


def canonical_migration_type(raw: str) -> str:
    """Normalize a migration-side SQL type token to a canonical form."""
    t = (raw or "").strip().lower()
    # Strip length/precision params: varchar(255) -> varchar
    t = re.sub(r"\(.*\)", "", t).strip()
    is_array = t.endswith("[]")
    if is_array:
        t = t[:-2].strip()
    canon = TYPE_MAP.get(t, t)
    return f"{canon}[]" if is_array else canon


def canonical_live_type(data_type: str, udt_name: str) -> str:
    """Normalize an information_schema.columns row to the same canonical form."""
    dt = (data_type or "").lower()
    if dt == "array":
        elem = (udt_name or "").lstrip("_").lower()
        return f"{ARRAY_ELEMENT_MAP.get(elem, elem)}[]"
    return dt


def normalize_function_args(raw: str) -> str:
    """Normalize a function's argument list to match
    pg_get_function_identity_arguments() output.

    Collapses whitespace, strips IN/OUT/INOUT/VARIADIC modifiers and any
    DEFAULT clauses (which pg_get_function_identity_arguments() never
    includes).
    """
    args = re.sub(r"\s+", " ", raw or "").strip().lower()
    args = re.sub(r"\b(in|out|inout|variadic)\b\s+", "", args)
    args = re.sub(r"\bdefault\b.*$", "", args).rstrip(", ").strip()
    return args


# ─────────────────────────────────────────────────────────────────────
# Migration parsing
# ─────────────────────────────────────────────────────────────────────

def parse_migrations(migrations_dir: str) -> dict:
    """Parse every *.sql file and return the declared object inventory.

    Returns a dict of category -> list of dicts:
      tables:    [{'table': str, 'columns': [(name, canonical_type)]}]
      columns:   [{'table': str, 'column': str, 'type': str|None}]
      functions: [{'name': str, 'args': str}]
      indexes:   [{'schema': str, 'table': str, 'name': str}]
      policies:  [{'schema': str, 'table': str, 'name': str}]
      triggers:  [{'table': str, 'name': str}]
      buckets:   [{'id': str}]
    """
    inventory = {
        "tables": [],
        "columns": [],
        "functions": [],
        "indexes": [],
        "policies": [],
        "triggers": [],
        "buckets": [],
    }
    table_columns = {}  # table -> list of (column, canonical_type)

    # Objects dropped by later migrations (renames / replacements).
    dropped_policies = []   # (schema, table, name)
    dropped_functions = []  # [name]
    dropped_indexes = []    # [name]
    dropped_triggers = []   # [name]

    sql_files = sorted(
        f for f in os.listdir(migrations_dir) if f.endswith(".sql")
    )
    if not sql_files:
        sys.exit(f"ERROR: no .sql files found in {migrations_dir}")

    for fname in sql_files:
        # The consolidated full-schema migration is a duplicate of every
        # incremental migration rolled into one file, used ONLY to bootstrap
        # a fresh project (deploy_booking.py --fresh). Including it here
        # double-declares every object and produces false drift when its
        # older names differ from the incremental migrations actually
        # applied to the live DB.
        if "full_schema" in fname:
            continue
        with open(
            os.path.join(migrations_dir, fname), encoding="utf-8"
        ) as f:
            sql = f.read()

        # ── DROP statements: a later migration may rename/replace an
        #    object (e.g. tighten_users_rls drops the old anon_can_*
        #    policies). Model them so renamed objects are not reported
        #    as drift. ────────────────────────────────────────────────
        for m in re.finditer(
            r"DROP\s+(?:POLICY\s+IF\s+EXISTS\s+|POLICY\s+)?"
            r"\"?([\w_]+)\"?\s+ON\s+(?:(\w+)\.)?(\w+)",
            sql,
            re.IGNORECASE,
        ):
            schema = (m.group(2) or "public").lower()
            dropped_policies.append(
                (schema, m.group(3).lower(), m.group(1).lower())
            )
        for m in re.finditer(
            r"DROP\s+(?:FUNCTION\s+IF\s+EXISTS\s+|FUNCTION\s+)?"
            r"(?:(?:public|pg_catalog)\.)?(\w+)",
            sql,
            re.IGNORECASE,
        ):
            dropped_functions.append(m.group(1).lower())
        for m in re.finditer(
            r"DROP\s+(?:INDEX\s+IF\s+EXISTS\s+|INDEX\s+)?"
            r"(?:IF\s+EXISTS\s+)?([\w]+)",
            sql,
            re.IGNORECASE,
        ):
            dropped_indexes.append(m.group(1).lower())
        for m in re.finditer(
            r"DROP\s+TRIGGER\s+(?:IF\s+EXISTS\s+)?([\w]+)",
            sql,
            re.IGNORECASE,
        ):
            dropped_triggers.append(m.group(1).lower())

        # ── Tables (with inline columns) ──────────────────────────
        for m in re.finditer(
            r"CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?"
            r"(?:public\.)?(\w+)\s*\(",
            sql,
            re.IGNORECASE,
        ):
            table = m.group(1).lower()
            start = m.end()
            # Find the matching close paren (nested parens for CHECK, etc.).
            depth = 1
            i = start
            while i < len(sql) and depth > 0:
                if sql[i] == "(":
                    depth += 1
                elif sql[i] == ")":
                    depth -= 1
                i += 1
            body = sql[start : i - 1]
            cols = parse_column_defs(body)
            table_columns[table] = cols
            inventory["tables"].append(
                {"table": table, "columns": list(cols)}
            )

        # ── ALTER TABLE ... ADD COLUMN ────────────────────────────
        for m in re.finditer(
            r"ALTER\s+TABLE\s+(?:ONLY\s+)?(?:IF\s+EXISTS\s+)?"
            r"(?:public\.)?(\w+)\s+ADD\s+(?:COLUMN\s+)?"
            r"(?:IF\s+NOT\s+EXISTS\s+)?"
            r"([\"\w]+)\s+([A-Za-z_][A-Za-z0-9_]*)",
            sql,
            re.IGNORECASE,
        ):
            table = m.group(1).lower()
            column = m.group(2).strip('"').lower()
            # ALTER TABLE ... ADD CONSTRAINT is not a column addition;
            # the generic regex would otherwise misread it as a column
            # literally named "constraint".
            if column == "constraint":
                continue
            # Preserve an array suffix the regex misses: the column type
            # capture stops at the first non-word char, so "TEXT[]" is
            # captured as "TEXT" and would falsely drift against live text[].
            rest = sql[m.end():m.end() + 4].lstrip()
            type_token = m.group(3)
            if rest.startswith("[]"):
                type_token += "[]"
            col_type = canonical_migration_type(type_token)
            inventory["columns"].append(
                {"table": table, "column": column, "type": col_type}
            )
            table_columns.setdefault(table, [])
            table_columns[table].append((column, col_type))

        # ── Functions ─────────────────────────────────────────────
        for m in re.finditer(
            r"CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+"
            r"(?:(?:public|pg_catalog)\.)?(\w+)\s*\(([^)]*)\)",
            sql,
            re.IGNORECASE,
        ):
            name = m.group(1).lower()
            args = normalize_function_args(m.group(2))
            inventory["functions"].append({"name": name, "args": args})

        # ── Indexes ───────────────────────────────────────────────
        for m in re.finditer(
            r"CREATE\s+(?:UNIQUE\s+)?INDEX\s+(?:IF\s+NOT\s+EXISTS\s+)?"
            r"([\w]+)\s+ON\s+(?:(?:public)\.)?(\w+)",
            sql,
            re.IGNORECASE,
        ):
            inventory["indexes"].append(
                {
                    "schema": "public",
                    "table": m.group(2).lower(),
                    "name": m.group(1).lower(),
                }
            )

        # ── Policies ──────────────────────────────────────────────
        for m in re.finditer(
            r"CREATE\s+POLICY\s+\"?([\w_]+)\"?\s+ON\s+"
            r"(?:(\w+)\.)?(\w+)",
            sql,
            re.IGNORECASE,
        ):
            schema = (m.group(2) or "public").lower()
            inventory["policies"].append(
                {
                    "schema": schema,
                    "table": m.group(3).lower(),
                    "name": m.group(1).lower(),
                }
            )

        # ── Triggers ──────────────────────────────────────────────
        for m in re.finditer(
            r"CREATE\s+TRIGGER\s+([\w]+)\s+.*?\bON\s+(?:public\.)?(\w+)",
            sql,
            re.IGNORECASE,
        ):
            inventory["triggers"].append(
                {"table": m.group(2).lower(), "name": m.group(1).lower()}
            )

        # ── Storage buckets ───────────────────────────────────────
        for m in re.finditer(
            r"INSERT\s+INTO\s+storage\.buckets\s*\([^)]*\)\s*VALUES"
            r"\s*\(\s*'([\w-]+)'",
            sql,
            re.IGNORECASE,
        ):
            inventory["buckets"].append({"id": m.group(1).lower()})

    return inventory, {
        "policies": dropped_policies,
        "functions": dropped_functions,
        "indexes": dropped_indexes,
        "triggers": dropped_triggers,
    }


def parse_column_defs(body: str) -> list:
    """Split a CREATE TABLE body into (name, canonical_type) per column.

    Skips table-level constraints (CONSTRAINT / PRIMARY KEY / UNIQUE /
    CHECK / FOREIGN KEY / REFERENCES / EXCLUDE).
    """
    cols = []
    # Split on top-level commas (not inside parens/quotes).
    parts = []
    depth = 0
    quote = None
    cur = []
    for ch in body:
        if quote:
            cur.append(ch)
            if ch == quote:
                quote = None
        elif ch in ("'", '"'):
            quote = ch
            cur.append(ch)
        elif ch == "(":
            depth += 1
            cur.append(ch)
        elif ch == ")":
            depth -= 1
            cur.append(ch)
        elif ch == "," and depth == 0:
            parts.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    parts.append("".join(cur))

    for part in parts:
        part = part.strip()
        if not part:
            continue
        # Table-level constraints (may span the first token line).
        first = part.split(None, 1)[0].upper() if part.split() else ""
        if first in {
            "CONSTRAINT",
            "PRIMARY",
            "UNIQUE",
            "CHECK",
            "FOREIGN",
            "EXCLUDE",
            "REFERENCES",
        }:
            continue
        tokens = part.split(None, 2)
        if len(tokens) < 2:
            continue
        name = tokens[0].strip('"').lower()
        cols.append((name, canonical_migration_type(tokens[1])))
    return cols


# ─────────────────────────────────────────────────────────────────────
# Live DB queries
# ─────────────────────────────────────────────────────────────────────

def load_deploy_env() -> None:
    env_path = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", DEPLOY_ENV_FILE
    )
    try:
        with open(env_path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, _, value = line.partition("=")
                key = key.strip()
                if not key or key in os.environ:
                    continue
                value = value.strip()
                if " #" in value:
                    value = value.split(" #", 1)[0].rstrip()
                if (value.startswith('"') and value.endswith('"')) or (
                    value.startswith("'") and value.endswith("'")
                ):
                    value = value[1:-1]
                os.environ[key] = value
    except OSError:
        pass


def management_api(method: str, path: str, body=None):
    token = os.environ.get("SUPABASE_ACCESS_TOKEN", "").strip()
    if not token:
        sys.exit(
            "ERROR: SUPABASE_ACCESS_TOKEN is not set.\n"
            f"Save it in {DEPLOY_ENV_FILE} or export it and re-run."
        )
    url = BASE_URL + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            # Cloudflare in front of api.supabase.com returns 403 for the
            # default Python-urllib user agent.
            "User-Agent": "curl/8.5.0 (DrsListing schema-drift)",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode()
            if not raw.strip():
                return resp.status, None
            try:
                return resp.status, json.loads(raw)
            except json.JSONDecodeError:
                return resp.status, raw
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except json.JSONDecodeError:
            return e.code, raw


def run_query(sql: str):
    status, resp = management_api("POST", "/database/query", {"query": sql})
    if status not in (200, 201):
        sys.exit(f"  ! Query failed ({status}): {resp}")
    return resp if isinstance(resp, list) else []


def fetch_live() -> dict:
    """Return the live DB inventory in the same shape as parse_migrations."""
    live = {
        "tables": {},
        "functions": {},
        "indexes": set(),
        "policies": set(),
        "triggers": set(),
        "buckets": set(),
    }
    # Columns: table -> {column: canonical_type}
    rows = run_query(
        "SELECT table_name, column_name, data_type, udt_name "
        "FROM information_schema.columns "
        "WHERE table_schema = 'public' ORDER BY table_name, ordinal_position"
    )
    for r in rows:
        t = (r.get("table_name") or "").lower()
        live["tables"].setdefault(t, {})
        live["tables"][t][(r.get("column_name") or "").lower()] = (
            canonical_live_type(
                r.get("data_type") or "", r.get("udt_name") or ""
            )
        )

    rows = run_query(
        "SELECT proname, pg_get_function_identity_arguments(oid) AS args "
        "FROM pg_proc WHERE pronamespace = 'public'::regnamespace "
        "AND prokind = 'f' ORDER BY proname"
    )
    for r in rows:
        name = (r.get("proname") or "").lower()
        args = re.sub(r"\s+", " ", (r.get("args") or "")).strip().lower()
        live["functions"].setdefault(name, set()).add(args)

    rows = run_query(
        "SELECT tablename, indexname FROM pg_indexes "
        "WHERE schemaname = 'public'"
    )
    for r in rows:
        live["indexes"].add(
            ((r.get("tablename") or "").lower(), (r.get("indexname") or "").lower())
        )

    rows = run_query(
        "SELECT schemaname, tablename, policyname FROM pg_policies "
        "WHERE schemaname IN ('public', 'storage')"
    )
    for r in rows:
        live["policies"].add(
            (
                (r.get("schemaname") or "").lower(),
                (r.get("tablename") or "").lower(),
                (r.get("policyname") or "").lower(),
            )
        )

    rows = run_query(
        "SELECT event_object_table, trigger_name FROM information_schema.triggers "
        "WHERE trigger_schema = 'public'"
    )
    for r in rows:
        live["triggers"].add(
            (
                (r.get("event_object_table") or "").lower(),
                (r.get("trigger_name") or "").lower(),
            )
        )

    rows = run_query("SELECT id, name FROM storage.buckets")
    for r in rows:
        bid = (r.get("id") or "").lower()
        live["buckets"].add(bid)

    return live


# ─────────────────────────────────────────────────────────────────────
# Diffing
# ─────────────────────────────────────────────────────────────────────

def compute_missing(declared: dict, live: dict) -> dict:
    """Structured view of what the live DB is missing, per category.

    Returns:
      tables:    [name]
      columns:   [(table, column)]  — missing only (not type-drift)
      functions: [(name, args)]
      indexes:   [(table, name)]
      policies:  [(schema, table, name)]
      triggers:  [(table, name)]
      buckets:   [id]

    Objects dropped by later migrations are excluded (same rules as
    compute_drift). COLUMN TYPE mismatches are NOT included here — they
    are reported separately and never auto-altered.
    """
    missing = {k: [] for k in (
        "tables", "columns", "functions", "indexes",
        "policies", "triggers", "buckets",
    )}
    live_tables = live["tables"]

    for tbl in declared["tables"]:
        if tbl["table"] not in live_tables:
            missing["tables"].append(tbl["table"])

    seen_cols = set()
    for entry in declared["columns"]:
        t, c = entry["table"], entry["column"]
        key = (t, c)
        if key in seen_cols:
            continue
        seen_cols.add(key)
        if t in live_tables and c not in live_tables[t]:
            missing["columns"].append(key)

    dropped_fns = set(declared["dropped"]["functions"])
    for fn in declared["functions"]:
        name = fn["name"]
        if name in dropped_fns:
            continue
        live_sigs = live["functions"].get(name)
        if live_sigs is None or fn["args"] not in live_sigs:
            missing["functions"].append((name, fn["args"]))

    dropped_idx = set(declared["dropped"]["indexes"])
    for idx in declared["indexes"]:
        key = (idx["table"], idx["name"])
        if idx["name"] in dropped_idx:
            continue
        if key not in live["indexes"]:
            missing["indexes"].append(key)

    dropped_pol = set(declared["dropped"]["policies"])
    for pol in declared["policies"]:
        key = (pol["schema"], pol["table"], pol["name"])
        if key in dropped_pol:
            continue
        if key not in live["policies"]:
            missing["policies"].append(key)

    dropped_trg = set(declared["dropped"]["triggers"])
    for trg in declared["triggers"]:
        key = (trg["table"], trg["name"])
        if trg["name"] in dropped_trg:
            continue
        if key not in live["triggers"]:
            missing["triggers"].append(key)

    for b in declared["buckets"]:
        if b["id"] not in live["buckets"]:
            missing["buckets"].append(b["id"])

    return missing


def compute_drift(declared: dict, live: dict) -> list:
    """Compare declared vs live and return a list of drift findings."""
    drift = []
    live_tables = live["tables"]

    # Missing objects (structured diff drives the human report).
    missing = compute_missing(declared, live)
    for name in missing["tables"]:
        drift.append(f"TABLE {name}  (missing on live DB)")
    for t, c in missing["columns"]:
        drift.append(f"COLUMN {t}.{c}  (missing on live DB)")
    for name, args in missing["functions"]:
        live_sigs = live["functions"].get(name)
        if live_sigs is None:
            drift.append(f"FUNCTION {name}({args})  (missing on live DB)")
        else:
            drift.append(
                f"FUNCTION {name}({args})  live signatures: "
                f"{', '.join(sorted(live_sigs))}"
            )
    for t, n in missing["indexes"]:
        drift.append(f"INDEX {n} on {t}  (missing on live DB)")
    for s, t, n in missing["policies"]:
        drift.append(
            f"POLICY {n} on {s}.{t}  (missing on live DB)"
        )
    for t, n in missing["triggers"]:
        drift.append(f"TRIGGER {n} on {t}  (missing on live DB)")
    for b in missing["buckets"]:
        drift.append(f"STORAGE BUCKET {b}  (missing on live DB)")

    # Column TYPE mismatches: report-only (never auto-altered).
    seen_cols = set()
    for entry in declared["columns"]:
        t, c = entry["table"], entry["column"]
        key = (t, c)
        if key in seen_cols:
            continue
        seen_cols.add(key)
        if t not in live_tables:
            continue  # table already reported missing
        if c not in live_tables[t]:
            continue  # column already reported missing
        declared_type = entry.get("type")
        live_type = live_tables[t][c]
        if declared_type and live_type != declared_type:
            drift.append(
                f"COLUMN TYPE {t}.{c}  declared {declared_type} "
                f"but live is {live_type}"
            )

    return sorted(set(drift))


# ─────────────────────────────────────────────────────────────────────
# Reconcile: extract defining statements + apply idempotent SQL
# ─────────────────────────────────────────────────────────────────────

def split_sql_statements(sql: str) -> list:
    """Split SQL text into top-level statements.

    Handles single-quoted strings ('' escapes), double-quoted identifiers,
    $tag$ dollar-quoting (used by plpgsql bodies), line/block comments,
    and paren depth — so a semicolon inside a function body does not
    split the statement.
    """
    statements = []
    buf = []
    i = 0
    n = len(sql)
    depth = 0
    while i < n:
        ch = sql[i]
        # -- line comment
        if ch == "-" and i + 1 < n and sql[i + 1] == "-":
            j = sql.find("\n", i)
            i = n if j == -1 else j + 1
            continue
        # /* block comment */
        if ch == "/" and i + 1 < n and sql[i + 1] == "*":
            j = sql.find("*/", i + 2)
            i = n if j == -1 else j + 2
            continue
        # $tag$ ... $tag$ dollar-quote
        m = re.match(r"\$[A-Za-z_][A-Za-z0-9_]*\$|\$\$", sql[i:])
        if ch == "$" and m:
            tag = m.group(0)
            j = sql.find(tag, i + len(tag))
            buf.append(sql[i : (n if j == -1 else j + len(tag))])
            i = n if j == -1 else j + len(tag)
            continue
        # '...' single-quoted string (with '' escaping)
        if ch == "'":
            buf.append(ch)
            i += 1
            while i < n:
                if sql[i] == "'":
                    if i + 1 < n and sql[i + 1] == "'":
                        buf.append("''")
                        i += 2
                        continue
                    buf.append(ch)
                    i += 1
                    break
                buf.append(sql[i])
                i += 1
            continue
        # "..." quoted identifier
        if ch == '"':
            buf.append(ch)
            i += 1
            while i < n and sql[i] != '"':
                buf.append(sql[i])
                i += 1
            if i < n:
                buf.append(ch)
                i += 1
            continue
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth = max(0, depth - 1)
        elif ch == ";" and depth == 0:
            stmt = "".join(buf).strip()
            if stmt:
                statements.append(stmt)
            buf = []
            i += 1
            continue
        buf.append(ch)
        i += 1
    stmt = "".join(buf).strip()
    if stmt:
        statements.append(stmt)
    return statements


def classify_statement(stmt: str):
    """Return (category, key) for a defining statement, or None.

    Categories/keys mirror compute_missing:
      ('table', name) / ('column', (table, column))
      ('function', (name, args)) / ('index', (table, name))
      ('policy', (schema, table, name)) / ('trigger', (table, name))
      ('bucket', id)
    """
    # Table (CREATE TABLE ...)
    m = re.match(
        r"CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?"
        r"(?:(?:public|storage)\.)?(\w+)\s*(?:\(|;|\s)",
        stmt,
        re.IGNORECASE,
    )
    if m:
        return ("table", m.group(1).lower())
    # Column (ALTER TABLE ... ADD [COLUMN] ...)
    m = re.match(
        r"ALTER\s+TABLE\s+(?:ONLY\s+)?(?:IF\s+EXISTS\s+)?"
        r"(?:(?:public|storage)\.)?(\w+)\s+ADD\s+(?:COLUMN\s+)?"
        r"(?:IF\s+NOT\s+EXISTS\s+)?([\"\w]+)",
        stmt,
        re.IGNORECASE,
    )
    if m:
        column = m.group(2).strip('"').lower()
        if column != "constraint":
            return ("column", (m.group(1).lower(), column))
    # Function
    m = re.match(
        r"CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+"
        r"(?:(?:public|pg_catalog)\.)?(\w+)\s*\(([^)]*)\)",
        stmt,
        re.IGNORECASE | re.DOTALL,
    )
    if m:
        return ("function", (m.group(1).lower(), normalize_function_args(m.group(2))))
    # Index
    m = re.match(
        r"CREATE\s+(?:UNIQUE\s+)?INDEX\s+(?:IF\s+NOT\s+EXISTS\s+)?"
        r"([\w]+)\s+ON\s+(?:(?:public)\.)?(\w+)",
        stmt,
        re.IGNORECASE,
    )
    if m:
        return ("index", (m.group(2).lower(), m.group(1).lower()))
    # Policy
    m = re.match(
        r"CREATE\s+POLICY\s+\"?([\w_]+)\"?\s+ON\s+"
        r"(?:(\w+)\.)?(\w+)",
        stmt,
        re.IGNORECASE,
    )
    if m:
        schema = (m.group(2) or "public").lower()
        return ("policy", (schema, m.group(3).lower(), m.group(1).lower()))
    # Trigger
    m = re.match(
        r"CREATE\s+(?:OR\s+REPLACE\s+)?TRIGGER\s+([\w]+)",
        stmt,
        re.IGNORECASE,
    )
    if m:
        on = re.search(r"\bON\s+(?:public\.)?(\w+)", stmt, re.IGNORECASE)
        if on:
            return ("trigger", (on.group(1).lower(), m.group(1).lower()))
    # Storage bucket
    m = re.match(
        r"INSERT\s+INTO\s+storage\.buckets\s*\([^)]*\)\s*VALUES"
        r"\s*\(\s*'([\w-]+)'",
        stmt,
        re.IGNORECASE | re.DOTALL,
    )
    if m:
        return ("bucket", m.group(1).lower())
    return None


def extract_statements(migrations_dir: str) -> dict:
    """Extract the defining statement for every declared object.

    Returns {(category, key): sql_statement}. Later migrations override
    earlier ones, matching the declared-inventory semantics. The
    consolidated full-schema migration is skipped (fresh-only duplicate).
    """
    statements = {}
    sql_files = sorted(
        f for f in os.listdir(migrations_dir) if f.endswith(".sql")
    )
    for fname in sql_files:
        if "full_schema" in fname:
            continue
        with open(
            os.path.join(migrations_dir, fname), encoding="utf-8"
        ) as f:
            sql = f.read()
        for stmt in split_sql_statements(sql):
            cls = classify_statement(stmt)
            if cls:
                statements[cls] = stmt
    return statements


def idempotent_sql(category: str, key, stmt: str) -> str:
    """Make a defining statement safe to re-run against the live DB."""
    stmt = stmt.strip().rstrip(";") + ";"
    if category in ("table", "index"):
        # Ensure IF NOT EXISTS for CREATE TABLE / CREATE INDEX.
        if re.search(
            r"CREATE\s+(?:UNIQUE\s+)?(?:TABLE|INDEX)\s+IF\s+NOT\s+EXISTS",
            stmt,
            re.IGNORECASE,
        ):
            return stmt
        return re.sub(
            r"(CREATE\s+(?:UNIQUE\s+)?(?:TABLE|INDEX)\s+)",
            r"\1IF NOT EXISTS ",
            stmt,
            count=1,
            flags=re.IGNORECASE,
        )
    if category == "column":
        # Ensure ADD COLUMN IF NOT EXISTS.
        if re.search(r"ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS", stmt, re.IGNORECASE):
            return stmt
        return re.sub(
            r"(ADD\s+COLUMN\s+)",
            r"\1IF NOT EXISTS ",
            stmt,
            count=1,
            flags=re.IGNORECASE,
        )
    if category == "function":
        # Ensure CREATE OR REPLACE FUNCTION.
        if re.search(r"CREATE\s+OR\s+REPLACE\s+FUNCTION", stmt, re.IGNORECASE):
            return stmt
        return re.sub(
            r"(CREATE\s+FUNCTION\s+)",
            r"\1OR REPLACE ",
            stmt,
            count=1,
            flags=re.IGNORECASE,
        )
    if category == "policy":
        # CREATE POLICY has no IF NOT EXISTS: drop first, then create.
        schema, table, name = key
        drop = f'DROP POLICY IF EXISTS "{name}" ON {schema}.{table}; '
        return drop + stmt
    if category == "trigger":
        # CREATE TRIGGER has no IF NOT EXISTS: drop first, then create.
        table, name = key
        return f"DROP TRIGGER IF EXISTS {name} ON {table}; " + stmt
    if category == "bucket":
        # Make the INSERT idempotent with ON CONFLICT DO NOTHING.
        if re.search(r"ON\s+CONFLICT", stmt, re.IGNORECASE):
            return stmt
        return stmt.rstrip(";") + " ON CONFLICT (id) DO NOTHING;"
    return stmt


# Plural category name (compute_missing key) -> singular statement key.
CATEGORY_TO_KEY = {
    "tables": "table",
    "columns": "column",
    "functions": "function",
    "indexes": "index",
    "policies": "policy",
    "triggers": "trigger",
    "buckets": "bucket",
}


def build_reconcile_plan(missing: dict, statements: dict) -> list:
    """Build the ordered list of (category, key, sql) to apply.

    Dependency order: tables -> columns -> functions -> indexes ->
    policies -> triggers -> buckets.
    """
    plan = []
    for cat in (
        "tables", "columns", "functions", "indexes",
        "policies", "triggers", "buckets",
    ):
        stmt_key = CATEGORY_TO_KEY[cat]
        for key in missing[cat]:
            stmt = statements.get((stmt_key, key))
            if stmt is None:
                plan.append((cat, key, None))
            else:
                plan.append((cat, key, idempotent_sql(stmt_key, key, stmt)))
    return plan


def apply_reconcile(plan: list, dry_run: bool) -> int:
    """Apply the reconcile plan. Returns (applied, failed)."""
    applied, failed = 0, 0
    for cat, key, sql in plan:
        label = f"{cat.rstrip('s')} {key}".replace(" ", " ", 1)
        if cat == "policies":
            label = f"policy {key[2]} on {key[0]}.{key[1]}"
        elif cat == "triggers":
            label = f"trigger {key[1]} on {key[0]}"
        elif cat == "columns":
            label = f"column {key[0]}.{key[1]}"
        elif cat == "functions":
            label = f"function {key[0]}({key[1]})"
        elif cat == "indexes":
            label = f"index {key[1]} on {key[0]}"
        elif cat == "tables":
            label = f"table {key}"
        elif cat == "buckets":
            label = f"bucket {key}"
        if sql is None:
            print(f"  SKIP  {label}: no defining statement found in migrations")
            continue
        if dry_run:
            print(f"  WOULD {label}")
            continue
        status, resp = management_api(
            "POST", "/database/query", {"query": sql}
        )
        if status in (200, 201):
            applied += 1
            print(f"  OK    {label}")
        else:
            failed += 1
            print(f"  FAIL  {label} ({status}): {str(resp)[:220]}")
    return applied, failed


def main() -> None:
    load_deploy_env()
    as_json = "--json" in sys.argv
    exit_zero = "--exit-zero" in sys.argv
    reconcile = "--reconcile" in sys.argv
    dry_run = "--dry-run" in sys.argv
    migrations_dir = DEFAULT_MIGRATIONS_DIR
    if "--migrations-dir" in sys.argv:
        idx = sys.argv.index("--migrations-dir")
        if idx + 1 < len(sys.argv):
            migrations_dir = sys.argv[idx + 1]

    # --project-ref override: the consolidated full-schema migration
    # defines the ENTIRE schema, so checking a scratch project that was
    # bootstrapped with it requires pointing at that project.
    global PROJECT_REF, BASE_URL
    if "--project-ref" in sys.argv:
        idx = sys.argv.index("--project-ref")
        if idx + 1 >= len(sys.argv):
            sys.exit("ERROR: --project-ref requires a value, e.g. --project-ref abcd...")
        PROJECT_REF = sys.argv[idx + 1]
        BASE_URL = f"https://api.supabase.com/v1/projects/{PROJECT_REF}"

    print("== DrsListing schema-drift check ==")
    print(f"  migrations dir: {migrations_dir}")
    print(f"  project:        {PROJECT_REF}")

    declared, dropped = parse_migrations(migrations_dir)
    declared["dropped"] = dropped
    live = fetch_live()
    drift = compute_drift(declared, live)

    counts = {
        "tables": len(declared["tables"]),
        "columns": len(declared["columns"]),
        "functions": len(declared["functions"]),
        "indexes": len(declared["indexes"]),
        "policies": len(declared["policies"]),
        "triggers": len(declared["triggers"]),
        "buckets": len(declared["buckets"]),
    }

    if as_json:
        print(json.dumps({"drift": drift, "declared": counts}, indent=2))
    else:
        print("\nDeclared by migrations:")
        for k, v in counts.items():
            print(f"  {k:10s} {v}")
        print(f"\nDrift findings: {len(drift)}")
        for d in drift:
            print(f"  [DRIFT] {d}")

    if reconcile:
        if not drift:
            print("\nNo drift to reconcile.")
            sys.exit(0)
        missing = compute_missing(declared, live)
        statements = extract_statements(migrations_dir)
        plan = build_reconcile_plan(missing, statements)
        print(
            "\n[--reconcile]" + (" [--dry-run] preview" if dry_run else "")
        )
        applied, failed = apply_reconcile(plan, dry_run)
        if dry_run:
            print(
                f"  (dry run) would apply {len(plan)} objects"
            )
            sys.exit(1 if plan else 0)
        print(f"  applied: {applied}, failed: {failed}")
        # Re-check the live DB after applying.
        live = fetch_live()
        drift = compute_drift(declared, live)
        print(f"\nPost-reconcile drift findings: {len(drift)}")
        for d in drift:
            print(f"  [DRIFT] {d}")
        if drift and not exit_zero:
            print("\nFAIL: drift remains after reconcile (likely a COLUMN TYPE "
                  "mismatch or an object without a defining statement).")
            sys.exit(1)
        print("\nOK: schema fully reconciled.")
        sys.exit(0)

    if drift and not exit_zero:
        print("\nFAIL: schema drift detected — apply the missing migrations "
              "or reconcile the live DB.")
        sys.exit(1)
    print("\nOK: no schema drift (every declared object exists on the live DB)."
          if not drift else "")
    sys.exit(0)


if __name__ == "__main__":
    main()
