#!/usr/bin/env python3
"""
DrsListing — Generate schema documentation from the consolidated migration.

Parses supabase/migrations/20260807000001_full_schema_all_fields.sql and
emits docs/schema.md: a Mermaid ER diagram plus per-table column reference,
RLS policies, functions, triggers, indexes and the storage bucket.

Usage:
    python supabase/gen_schema_docs.py
"""

import os
import re

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
MIGRATION = os.path.join(
    ROOT, "supabase/migrations/20260807000001_full_schema_all_fields.sql"
)
OUT = os.path.join(ROOT, "docs", "schema.md")

# A NEW column starts when a line at 4-space indent matches
# `name <one-of-these-type-keywords>`. Note TEXT[] is accepted via the \b
# boundary (TEXT[ begins with TEXT).
NEW_COLUMN_RE = re.compile(r"^    ([a-z_]+)\s+(TEXT|UUID|JSONB|DATE|DOUBLE|INTEGER|BOOLEAN|TIMESTAMPTZ)\b")

TABLE_OPEN_RE = re.compile(r"CREATE TABLE IF NOT EXISTS public\.(\w+)\s*\(")
TABLE_CLOSE_RE = re.compile(r"^\s*\)\s*;")
CONSTRAINT_RE = re.compile(r"^\s{4}CONSTRAINT\s+(\w+)\s*(.*)$")


def strip_inline_comment(line):
    """Split a line into (code, comment). Only strips `--` NOT inside quotes."""
    in_single = in_double = False
    for i, ch in enumerate(line):
        if ch == "'" and not in_double:
            in_single = not in_single
        elif ch == '"' and not in_single:
            in_double = not in_double
        elif ch == "-" and i + 1 < len(line) and line[i + 1] == "-" and not in_single and not in_double:
            return line[:i].rstrip(), line[i + 2 :].strip()
    return line, ""


def find_matching_paren(s, start):
    """Given s[start] == '(', return the index of the matching ')', honoring quotes."""
    depth = 0
    in_single = in_double = False
    i = start
    while i < len(s):
        ch = s[i]
        if ch == "'" and not in_double:
            in_single = not in_single
        elif ch == '"' and not in_single:
            in_double = not in_double
        elif not in_single and not in_double:
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0:
                    return i
        i += 1
    return -1


def parse():
    """Return {tables, policies, functions, triggers, bucket} from the migration."""
    with open(MIGRATION, encoding="utf-8") as f:
        raw = f.read()
    lines = raw.splitlines()

    tables = {}
    policies = []
    functions = []
    triggers = []
    bucket = None

    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        code, _ = strip_inline_comment(line)

        # ── Table block ────────────────────────────────────────────
        m = TABLE_OPEN_RE.search(line)
        if m:
            tname = m.group(1)
            tbl = {"columns": [], "constraints": [], "indexes": [], "comments": {}}
            i += 1
            current = None  # dict for the column being accumulated
            # Look ahead to collect the whole block until `);`
            block = []
            while i < n and not TABLE_CLOSE_RE.match(lines[i]):
                block.append(lines[i])
                i += 1
            i += 1  # skip `);`

            for bline in block:
                bcode, bcomment = strip_inline_comment(bline)
                cm = CONSTRAINT_RE.match(bline)
                if cm:
                    # flush any pending column before switching to constraints
                    if current is not None:
                        tbl["columns"].append(current)
                        current = None
                    # Peek the next line for the UNIQUE (...) clause body
                    body = cm.group(2).strip()
                    if not body and i < n:
                        nxt, _ = strip_inline_comment(lines[i])
                        nxt = nxt.strip()
                        if nxt.startswith("UNIQUE") or nxt.startswith("CHECK"):
                            body = nxt.rstrip(",")
                            i += 1
                    tbl["constraints"].append(
                        f"{cm.group(1)} {body}".strip().rstrip(",")
                    )
                    continue
                if re.match(r"^\s*--", bline):
                    # standalone comment — attach to previous column if any
                    if current is not None:
                        current["comment"] = (current.get("comment", "") + " " + bcomment).strip()
                    continue
                nc = NEW_COLUMN_RE.match(bline)
                if nc and not bcode.strip().startswith(("REFERENCES", "CHECK", "CONSTRAINT")):
                    if current is not None:
                        tbl["columns"].append(current)
                    # raw = everything after the leading `name TYPE` prefix
                    raw = bcode.strip().rstrip(",")
                    raw = re.sub(r"^\s*\w+\s+", "", raw, count=1)
                    current = {
                        "name": nc.group(1),
                        "raw": raw,
                        "comment": bcomment,
                    }
                elif current is not None and bcode.strip():
                    # continuation of the previous column
                    current["raw"] += " " + bcode.strip().rstrip(",")
                    if bcomment and not current.get("comment"):
                        current["comment"] = bcomment
            if current is not None:
                tbl["columns"].append(current)
            tables[tname] = tbl
            i -= 0
            continue

        # ── CREATE INDEX (single- or multi-line) ───────────────────
        im = re.search(r"CREATE INDEX IF NOT EXISTS (\w+)", line)
        if im:
            target = None
            om = re.search(r"ON public\.(\w+)", line)
            if om:
                target = om.group(1)
            else:
                # peek following lines for the ON clause
                j = i
                while j < min(n, i + 4):
                    om = re.search(r"ON public\.(\w+)", lines[j])
                    if om:
                        target = om.group(1)
                        break
                    j += 1
            if target:
                tables.setdefault(
                    target, {"columns": [], "constraints": [], "indexes": []}
                )
                tables[target]["indexes"].append(im.group(1))
            i += 1
            continue

        # ── CREATE POLICY ──────────────────────────────────────────
        pm = re.search(r'CREATE POLICY "([^"]+)"', line)
        if pm:
            j = i
            on_table = None
            while j < min(n, i + 4):
                om = re.search(r"ON\s+(?:public\.|storage\.)?(\w+)", lines[j])
                if om:
                    on_table = om.group(1)
                    break
                j += 1
            policies.append({"name": pm.group(1), "table": on_table or "?"})
            i += 1
            continue

        # ── CREATE OR REPLACE FUNCTION ─────────────────────────────
        # Signature may span multiple lines (e.g. add_device_token(
        #     p_token TEXT,
        #     p_platform TEXT DEFAULT 'android'
        # )). Consume lines until the balanced close paren when needed.
        fm = re.search(r"CREATE OR REPLACE FUNCTION public\.(\w+)\s*\(", line)
        if fm:
            fname = fm.group(1)
            open_idx = line.index("(", fm.start())
            close_idx = find_matching_paren(line, open_idx)
            if close_idx != -1:
                args = line[open_idx + 1 : close_idx].strip()
                i += 1
            else:
                buf = line
                j = i + 1
                while j < n:
                    buf += "\n" + lines[j]
                    close_idx = find_matching_paren(buf, open_idx)
                    if close_idx != -1:
                        break
                    j += 1
                args = buf[open_idx + 1 : close_idx].strip() if close_idx != -1 else ""
                i = j + 1
            functions.append({"name": fname, "args": args})
            continue

        # ── CREATE TRIGGER (multi-line) ────────────────────────────
        tm = re.search(r"CREATE TRIGGER (\w+)", line)
        if tm:
            j = i
            ev = tbl_name = None
            # BEFORE may be on the same line as ON, or many lines apart
            # (e.g. BEFORE INSERT OR UPDATE OF\n col,...\n ON public.appointments)
            while j < min(n, i + 12):
                lj, _ = strip_inline_comment(lines[j])
                if ev is None:
                    # Event = words between BEFORE and the (optional) ON clause
                    em = re.search(
                        r"BEFORE\s+(.+?)(?:\s+ON\s+public\.\w+)?\s*$",
                        lj.rstrip(),
                    )
                    if em:
                        ev = re.sub(r"\s+", " ", em.group(1)).strip()
                if tbl_name is None:
                    om = re.search(r"ON\s+public\.(\w+)", lj)
                    if om:
                        tbl_name = om.group(1)
                if ev and tbl_name:
                    break
                j += 1
            if ev and tbl_name:
                triggers.append({"name": tm.group(1), "event": ev, "table": tbl_name})
            i += 1
            continue

        # ── storage bucket ─────────────────────────────────────────
        if "INSERT INTO storage.buckets" in line:
            j = i
            while j < min(n, i + 3):
                bm = re.search(r"VALUES\s*\('(\w+)',\s*'(\w+)',\s*(\w+)\)", lines[j])
                if bm:
                    bucket = {"id": bm.group(1), "name": bm.group(2), "public": bm.group(3)}
                    break
                j += 1
            i += 1
            continue

        i += 1

    return {
        "tables": tables,
        "policies": policies,
        "functions": functions,
        "triggers": triggers,
        "bucket": bucket,
    }


def parse_column(raw):
    """Break a raw column def into type / constraints / default / comment."""
    s = raw.strip().rstrip(",")
    comment = ""
    m = re.search(r"--\s*(.+)$", s)
    if m:
        comment = m.group(1).strip()
        s = s[: m.start()].strip()

    primary = "PRIMARY KEY" in s
    s = s.replace("PRIMARY KEY", " ").strip()

    # CHECK (...) — balanced-paren extraction
    constraints = []
    cm = re.search(r"CHECK\s*\(", s)
    if cm:
        open_idx = cm.end() - 1
        close_idx = find_matching_paren(s, open_idx)
        if close_idx != -1:
            expr = s[open_idx + 1 : close_idx].strip()
            constraints.append(f"CHECK ({expr})")
            s = (s[: cm.start()] + s[close_idx + 1 :]).strip()

    # DEFAULT
    default = None
    dm = re.search(r"DEFAULT\s+(.+)$", s)
    if dm:
        default = dm.group(1).strip().rstrip(",")
        s = s[: dm.start()].strip()

    not_null = "NOT NULL" in s
    s = s.replace("NOT NULL", " ").strip()

    # REFERENCES
    rm = re.search(r"REFERENCES\s+public\.(\w+)\((\w+)\)\s*(ON DELETE \w+)?", s)
    if rm:
        ref = f"FK → {rm.group(1)}.{rm.group(2)}"
        if rm.group(3):
            ref += f" ({rm.group(3)})"
        constraints.append(ref)
        s = s.replace(rm.group(0), " ").strip()

    if "UNIQUE" in s:
        constraints.append("UNIQUE")
        s = s.replace("UNIQUE", " ").strip()

    typ = re.sub(r"\s+", " ", s).strip()
    return {
        "type": typ,
        "comment": comment,
        "default": default,
        "not_null": not_null,
        "primary": primary,
        "constraints": constraints,
    }


def mermaid_safe(s):
    """Strip characters that break the mermaid erDiagram attribute label."""
    return (
        s.replace("(", " ")
        .replace(")", " ")
        .replace(",", " ")
        .replace('"', "'")
        .replace("{", " ")
        .replace("}", " ")
        .replace("→", "->")
        .replace("|", " ")
        .replace(";", " ")
    )


def render_mermaid(doc):
    t = doc["tables"]
    order = ["users", "appointments", "saved_doctors", "doctors", "doctor_slots", "api_usage_count"]
    out = ["```mermaid", "erDiagram"]
    for name in order:
        if name not in t:
            continue
        out.append(f"    {name} {{")
        for col in t[name]["columns"]:
            p = parse_column(col["raw"])
            label_bits = []
            if p["primary"]:
                label_bits.append("PK")
            for c in p["constraints"]:
                label_bits.append(mermaid_safe(c))
            if p["not_null"] and not p["primary"]:
                label_bits.append("NOT NULL")
            typ_tok = p["type"].split()[0].replace("[]", "")
            label = " ".join(label_bits) if label_bits else ""
            out.append(
                f"        {typ_tok} {col['name']}"
                + (f" \"{label}\"" if label else "")
            )
        out.append("    }")
        out.append("")
    rels = [
        ("users", "appointments", "1", "N", "books"),
        ("users", "saved_doctors", "1", "N", "saves"),
        ("doctors", "appointments", "1", "N", "hosts"),
        ("doctors", "doctor_slots", "1", "N", "has schedule"),
    ]
    for a, b, ca, cb, label in rels:
        if a in t and b in t:
            out.append(f'    {a} ||--o{{ {b} : "{label}"')
    out.append("```")
    return "\n".join(out)


def md_escape(s):
    return str(s).replace("|", "\\|").replace("`", "'")


def render_table_section(name, tbl):
    out = [f"### `{name}`", ""]
    out.append("| Column | Type | Nullable | Default | Constraints |")
    out.append("|--------|------|----------|---------|-------------|")
    for col in tbl["columns"]:
        p = parse_column(col["raw"])
        nullable = "NO" if (p["not_null"] or p["primary"]) else "YES"
        default = p["default"] or "—"
        cons = "; ".join(p["constraints"]) if p["constraints"] else "—"
        if p["primary"]:
            cons = "PRIMARY KEY" + (f"; {cons}" if cons != "—" else "")
        out.append(
            f"| `{md_escape(col['name'])}` | `{md_escape(p['type'])}` "
            f"| {nullable} | `{md_escape(default)}` | {md_escape(cons)} |"
        )
        if col.get("comment"):
            out.append(
                f"|  | *{md_escape(col['comment'])}* | | | |"
            )
    if tbl["constraints"]:
        out.append("")
        for c in tbl["constraints"]:
            out.append(f"- Composite constraint: `{md_escape(c)}`")
    if tbl["indexes"]:
        out.append("")
        out.append("**Indexes:** " + ", ".join(f"`{i}`" for i in tbl["indexes"]))
    out.append("")
    return "\n".join(out)


def main():
    doc = parse()

    out = [
        "# DrsListing — Database Schema",
        "",
        "Auto-generated from `supabase/migrations/20260807000001_full_schema_all_fields.sql` "
        "(the consolidated full-schema migration). Regenerate with "
        "`python supabase/gen_schema_docs.py`.",
        "",
        "## Overview",
        "",
        "Six tables. Users log in by mobile number (no OTP); identity is a locally-stored "
        "UUID and RLS is scoped to custom request headers (`x-user-mobile` / "
        "`x-user-id`). The QR booking-page Edge Function writes with the service role "
        "key (bypasses RLS). Two server-side triggers enforce booking rules: a slot stays "
        "occupied until the appointment is **Cancelled**, and appointments are blocked on "
        "dates the doctor marked unavailable.",
        "",
        "## ER Diagram",
        "",
        render_mermaid(doc),
        "",
        "## Tables",
        "",
    ]
    order = ["users", "appointments", "saved_doctors", "doctors", "doctor_slots", "api_usage_count"]
    for name in order:
        if name in doc["tables"]:
            out.append(render_table_section(name, doc["tables"][name]))

    out.append("## Row Level Security Policies")
    out.append("")
    out.append("| Policy | Table |")
    out.append("|--------|-------|")
    for p in doc["policies"]:
        out.append(f"| `{md_escape(p['name'])}` | `{md_escape(p['table'])}` |")
    out.append("")

    out.append("## Functions")
    out.append("")
    out.append("| Function | Signature |")
    out.append("|----------|-----------|")
    for f in doc["functions"]:
        sig = f"({f['args']})" if f["args"] else "()"
        out.append(f"| `{md_escape(f['name'])}` | `{md_escape(sig)}` |")
    out.append("")

    out.append("## Triggers")
    out.append("")
    out.append("| Trigger | Event | Table |")
    out.append("|---------|-------|-------|")
    for t in doc["triggers"]:
        out.append(f"| `{md_escape(t['name'])}` | {md_escape(t['event'])} | `{md_escape(t['table'])}` |")
    out.append("")

    out.append("## Storage")
    out.append("")
    if doc["bucket"]:
        b = doc["bucket"]
        pols = [p["name"] for p in doc["policies"] if p["table"] == "objects"]
        out.append("| Bucket | ID | Public | Policies |")
        out.append("|--------|----|--------|----------|")
        out.append(
            f"| `{b['name']}` | `{b['id']}` | {b['public']} | "
            + (", ".join(f"`{p}`" for p in pols) if pols else "—")
            + " |"
        )
    out.append("")

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(out))
    print(f"Wrote {OUT} ({len(out)} lines)")


if __name__ == "__main__":
    main()
