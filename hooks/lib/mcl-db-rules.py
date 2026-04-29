#!/usr/bin/env python3
"""MCL DB Rules — generic core (10) + ORM add-on (8 ORMs × 3 = 24).

Mirrors mcl-security-rules.py shape but DB-flavored. Findings carry
severity + category=db-* (no OWASP claim — that's 8.7.0's domain).
8.7.0 ile çakışmazlık: SQL injection / hardcoded credentials /
mass-assignment / insecure-deserialization 8.7.0'da kalır; bu modül
DB tasarım / index / N+1 / schema / migration üzerinde durur.

Since 8.8.0.
"""
from __future__ import annotations
import re
from dataclasses import dataclass, asdict
from pathlib import Path


@dataclass
class Finding:
    severity: str           # HIGH | MEDIUM | LOW
    source: str             # generic | orm | migration | explain
    rule_id: str
    file: str
    line: int
    message: str
    category: str = ""      # db-schema | db-index | db-query | db-migration | db-n-plus-one | db-pooling
    dialect: str = ""       # postgres | mysql | sqlite | mongo | redis | ""
    autofix: str | None = None

    def to_dict(self) -> dict:
        return asdict(self)


_GENERIC_RULES: list = []
_ORM_RULES: dict[str, list] = {}


def generic(rule_id: str):
    def deco(fn):
        fn.rule_id = rule_id
        _GENERIC_RULES.append(fn)
        return fn
    return deco


def orm(tag: str, rule_id: str):
    def deco(fn):
        fn.rule_id = rule_id
        _ORM_RULES.setdefault(tag, []).append(fn)
        return fn
    return deco


def _scan(content: str, pattern: re.Pattern, builder) -> list[Finding]:
    out: list[Finding] = []
    for m in pattern.finditer(content):
        line_no = content[: m.start()].count("\n") + 1
        out.append(builder(line_no, m))
    return out


def _is_test_or_migration(path: str) -> bool:
    p = path.replace("\\", "/").lower()
    return "/test" in p or "/spec" in p or "/__tests__/" in p or "/migrations/" in p or "/migrate/" in p


# ============================================================
# Generic core rules (10)
# ============================================================

@generic("DB-G01-missing-primary-key")
def r_missing_pk(path: str, content: str) -> list[Finding]:
    if _is_test_or_migration(path):
        return []
    pat = re.compile(r"(?is)CREATE\s+TABLE\s+(?!IF\s+NOT\s+EXISTS\s+)?[\"`]?(\w+)[\"`]?\s*\((.*?)\)\s*;")
    out: list[Finding] = []
    for m in pat.finditer(content):
        body = m.group(2)
        if re.search(r"\bPRIMARY\s+KEY\b", body, re.IGNORECASE):
            continue
        if re.search(r"\bSERIAL\s+PRIMARY\s+KEY\b", body, re.IGNORECASE):
            continue
        line_no = content[: m.start()].count("\n") + 1
        out.append(Finding(
            severity="HIGH", source="generic", rule_id="DB-G01-missing-primary-key",
            file=path, line=line_no, category="db-schema",
            message=f"CREATE TABLE {m.group(1)!r} declared without PRIMARY KEY. Every table must have a stable identity.",
        ))
    return out


@generic("DB-G02-select-star-prod")
def r_select_star(path: str, content: str) -> list[Finding]:
    if _is_test_or_migration(path):
        return []
    pat = re.compile(r"(?ix) (?:^|[\(\s\"'`]) SELECT \s+ \* \s+ FROM \s+ ")
    return _scan(content, pat, lambda ln, m: Finding(
        severity="MEDIUM", source="generic", rule_id="DB-G02-select-star-prod",
        file=path, line=ln, category="db-query",
        message="SELECT * outside test/migration. List columns explicitly to control payload, indexes, and serialization.",
    ))


@generic("DB-G03-missing-fk-index")
def r_missing_fk_index(path: str, content: str) -> list[Finding]:
    # DDL: REFERENCES without explicit INDEX next to it.
    pat = re.compile(r"(?im)^\s*(\w+)\s+(?:[A-Z\(\)0-9, ]+?)\s+REFERENCES\s+\w+\s*\([^)]+\)")
    out: list[Finding] = []
    for m in pat.finditer(content):
        col = m.group(1)
        line_no = content[: m.start()].count("\n") + 1
        # Heuristic: if there's no INDEX statement for col within ±200 chars, flag.
        win = content[max(0, m.start()-400): m.end()+400]
        if re.search(rf"\bINDEX\b[^;]*\b{re.escape(col)}\b", win, re.IGNORECASE):
            continue
        out.append(Finding(
            severity="MEDIUM", source="generic", rule_id="DB-G03-missing-fk-index",
            file=path, line=line_no, category="db-index",
            message=f"FK column {col!r} has no explicit index nearby. JOINs and WHERE on this FK will scan.",
        ))
    return out


@generic("DB-G04-update-delete-no-where")
def r_update_delete_no_where(path: str, content: str) -> list[Finding]:
    if _is_test_or_migration(path):
        return []
    pat = re.compile(r"(?ix) \b(UPDATE|DELETE)\s+(?:FROM\s+)?[\"`]?\w+[\"`]?\s+(?:SET\s+[^;]+?)?(?:RETURNING|;|$)")
    out: list[Finding] = []
    for m in pat.finditer(content):
        snippet = m.group(0)
        if re.search(r"\bWHERE\b", snippet, re.IGNORECASE):
            continue
        line_no = content[: m.start()].count("\n") + 1
        out.append(Finding(
            severity="HIGH", source="generic", rule_id="DB-G04-update-delete-no-where",
            file=path, line=line_no, category="db-query",
            message=f"{m.group(1).upper()} without WHERE clause — touches all rows. Add WHERE or use TRUNCATE explicitly.",
        ))
    return out


@generic("DB-G05-jsonb-no-validation")
def r_jsonb_no_check(path: str, content: str) -> list[Finding]:
    pat = re.compile(r"(?im)^\s*(\w+)\s+JSONB\b")
    out: list[Finding] = []
    for m in pat.finditer(content):
        line_no = content[: m.start()].count("\n") + 1
        # Look ahead/back ~300 chars for CHECK constraint mentioning the col.
        col = m.group(1)
        win = content[max(0, m.start()-300): m.end()+300]
        if re.search(rf"CHECK\s*\([^)]*\b{re.escape(col)}\b[^)]*\)", win, re.IGNORECASE):
            continue
        out.append(Finding(
            severity="LOW", source="generic", rule_id="DB-G05-jsonb-no-validation",
            file=path, line=line_no, category="db-schema", dialect="postgres",
            message=f"JSONB column {col!r} has no CHECK constraint or schema. Future writers may insert invalid shapes.",
        ))
    return out


@generic("DB-G06-timestamp-no-tz")
def r_timestamp_no_tz(path: str, content: str) -> list[Finding]:
    pat = re.compile(r"(?im)^\s*\w+\s+TIMESTAMP\b(?!\s*WITH\s+TIME\s+ZONE)(?!TZ)")
    return _scan(content, pat, lambda ln, m: Finding(
        severity="MEDIUM", source="generic", rule_id="DB-G06-timestamp-no-tz",
        file=path, line=ln, category="db-schema", dialect="postgres",
        message="TIMESTAMP without TIME ZONE. Use TIMESTAMPTZ to avoid silent UTC mismatches.",
    ))


@generic("DB-G07-text-id-not-uuid")
def r_text_id(path: str, content: str) -> list[Finding]:
    pat = re.compile(r"(?im)^\s*\w*[_]?id\s+(?:VARCHAR|TEXT|CHAR)\s*\(\s*(\d+)\s*\)")
    out: list[Finding] = []
    for m in pat.finditer(content):
        size = int(m.group(1))
        if size < 32:
            continue
        line_no = content[: m.start()].count("\n") + 1
        out.append(Finding(
            severity="LOW", source="generic", rule_id="DB-G07-text-id-not-uuid",
            file=path, line=line_no, category="db-schema",
            message="ID-like column declared as VARCHAR/TEXT >=32. If holding UUIDs, use the native UUID type.",
        ))
    return out


@generic("DB-G08-enum-as-text")
def r_enum_text(path: str, content: str) -> list[Finding]:
    pat = re.compile(r"(?im)^\s*(\w*(?:status|state|kind|type)\w*)\s+(?:VARCHAR|TEXT)\b")
    out: list[Finding] = []
    for m in pat.finditer(content):
        col = m.group(1)
        win = content[max(0, m.start()-300): m.end()+300]
        if re.search(rf"CHECK\s*\([^)]*\b{re.escape(col)}\b[^)]*IN\s*\(", win, re.IGNORECASE):
            continue
        line_no = content[: m.start()].count("\n") + 1
        out.append(Finding(
            severity="LOW", source="generic", rule_id="DB-G08-enum-as-text",
            file=path, line=line_no, category="db-schema",
            message=f"Enum-like column {col!r} stored as VARCHAR/TEXT without CHECK or DB enum type. Invalid values can be inserted.",
        ))
    return out


@generic("DB-G09-cascade-delete-on-user-data")
def r_cascade_delete(path: str, content: str) -> list[Finding]:
    pat = re.compile(r"(?ix)\b(?:user|customer|account|tenant)s?\b[^;]*?ON\s+DELETE\s+CASCADE")
    return _scan(content, pat, lambda ln, m: Finding(
        severity="MEDIUM", source="generic", rule_id="DB-G09-cascade-delete-on-user-data",
        file=path, line=ln, category="db-schema",
        message="ON DELETE CASCADE on user-data table. Soft-delete or restrict + audit the cascade is usually safer.",
    ))


@generic("DB-G10-n-plus-one-static")
def r_n_plus_one(path: str, content: str) -> list[Finding]:
    # Cross-ORM static heuristic: loop variable accesses .relation.field
    # or .relation_set.attr — common N+1 pattern.
    pat = re.compile(
        r"(?x)"
        r"\bfor\s+\w+\s+in\s+\w+(?:\.\w+)*\s*:[^\n]*\n"           # python: for x in qs:
        r"(?:[\t ]+[^\n]*\n){0,4}"                                  # 0-4 indented lines
        r"[\t ]+\w+\.\w+\.(?:filter|all|first|count|get|find)"     # x.related.<query>
    )
    out: list[Finding] = []
    for m in pat.finditer(content):
        line_no = content[: m.start()].count("\n") + 1
        out.append(Finding(
            severity="MEDIUM", source="generic", rule_id="DB-G10-n-plus-one-static",
            file=path, line=line_no, category="db-n-plus-one",
            message="Loop performs a query per iteration via related-object access. Prefer eager-load (select_related/prefetch_related/include/Preload).",
        ))
    return out


# ============================================================
# ORM add-on rules (8 × 3 = 24)
# ============================================================

# ---- Prisma ----
@orm("orm-prisma", "DB-PR-missing-relation-index")
def r_pr_missing_relation_index(path: str, content: str) -> list[Finding]:
    # Prisma schema: @relation without matching @@index on FK column.
    if not path.endswith(".prisma"):
        return []
    pat = re.compile(r"@relation\s*\(\s*fields\s*:\s*\[\s*(\w+)\s*\]")
    out: list[Finding] = []
    for m in pat.finditer(content):
        fk = m.group(1)
        if re.search(rf"@@index\s*\(\s*\[\s*{re.escape(fk)}\b", content):
            continue
        line_no = content[: m.start()].count("\n") + 1
        out.append(Finding(
            severity="MEDIUM", source="orm", rule_id="DB-PR-missing-relation-index",
            file=path, line=line_no, category="db-index",
            message=f"Prisma @relation FK {fk!r} has no matching @@index. JOINs will scan.",
        ))
    return out


@orm("orm-prisma", "DB-PR-implicit-many-to-many")
def r_pr_implicit_m2m(path: str, content: str) -> list[Finding]:
    if not path.endswith(".prisma"):
        return []
    pat = re.compile(r"(\w+)\s+(\w+)\[\]\s*$", re.MULTILINE)
    return _scan(content, pat, lambda ln, m: Finding(
        severity="LOW", source="orm", rule_id="DB-PR-implicit-many-to-many",
        file=path, line=ln, category="db-schema",
        message="Possible implicit many-to-many. Prefer explicit join model so you can index/extend it.",
    ))


@orm("orm-prisma", "DB-PR-find-many-no-take")
def r_pr_findmany_no_take(path: str, content: str) -> list[Finding]:
    pat = re.compile(r"\.findMany\s*\(\s*\{(?![^}]*\btake\s*:)[^}]*\}\s*\)")
    return _scan(content, pat, lambda ln, m: Finding(
        severity="MEDIUM", source="orm", rule_id="DB-PR-find-many-no-take",
        file=path, line=ln, category="db-query",
        message="Prisma findMany without `take`. Unbounded result set risks memory blowup.",
    ))


# ---- SQLAlchemy ----
@orm("orm-sqlalchemy", "DB-SA-lazy-select-default")
def r_sa_lazy_default(path: str, content: str) -> list[Finding]:
    pat = re.compile(r"\brelationship\s*\(\s*[\"']?\w+[\"']?(?![^)]*\blazy\s*=)")
    return _scan(content, pat, lambda ln, m: Finding(
        severity="MEDIUM", source="orm", rule_id="DB-SA-lazy-select-default",
        file=path, line=ln, category="db-n-plus-one",
        message="SQLAlchemy relationship() without explicit lazy=. Default 'select' triggers per-access query (N+1 risk).",
    ))


@orm("orm-sqlalchemy", "DB-SA-missing-index-fk")
def r_sa_fk_no_index(path: str, content: str) -> list[Finding]:
    pat = re.compile(r"ForeignKey\s*\([^)]+\)(?![^,)]*\bindex\s*=)")
    return _scan(content, pat, lambda ln, m: Finding(
        severity="MEDIUM", source="orm", rule_id="DB-SA-missing-index-fk",
        file=path, line=ln, category="db-index",
        message="SQLAlchemy ForeignKey without index=True. Most JOINs/WHEREs on this FK need it.",
    ))


@orm("orm-sqlalchemy", "DB-SA-bulk-via-loop")
def r_sa_bulk_loop(path: str, content: str) -> list[Finding]:
    pat = re.compile(r"(?s)for\s+\w+\s+in\s+\w+\s*:[^\n]*\n(?:[\t ]+[^\n]*\n){0,3}[\t ]+session\.add\s*\(")
    return _scan(content, pat, lambda ln, m: Finding(
        severity="MEDIUM", source="orm", rule_id="DB-SA-bulk-via-loop",
        file=path, line=ln, category="db-query",
        message="session.add() in loop. Use session.bulk_save_objects() / bulk_insert_mappings() for batches.",
    ))


# ---- Django ORM ----
@orm("orm-django", "DB-DJ-missing-select-related")
def r_dj_missing_sr(path: str, content: str) -> list[Finding]:
    pat = re.compile(r"(?s)for\s+\w+\s+in\s+(\w+)\.objects\.(?:all|filter)\([^)]*\)\s*:[^\n]*\n(?:[\t ]+[^\n]*\n){0,4}[\t ]+\w+\.\w+\.(?!values)")
    return _scan(content, pat, lambda ln, m: Finding(
        severity="MEDIUM", source="orm", rule_id="DB-DJ-missing-select-related",
        file=path, line=ln, category="db-n-plus-one",
        message="Django queryset loop accesses related field without select_related/prefetch_related — N+1.",
    ))


@orm("orm-django", "DB-DJ-fk-no-db-index")
def r_dj_fk_no_index(path: str, content: str) -> list[Finding]:
    pat = re.compile(r"models\.ForeignKey\s*\([^)]+\)(?![^,)]*\bdb_index\s*=)")
    return _scan(content, pat, lambda ln, m: Finding(
        severity="MEDIUM", source="orm", rule_id="DB-DJ-fk-no-db-index",
        file=path, line=ln, category="db-index",
        message="Django ForeignKey without db_index=True. Default indexes the FK in some versions but not all — explicit is safer.",
    ))


@orm("orm-django", "DB-DJ-all-in-loop")
def r_dj_all_in_loop(path: str, content: str) -> list[Finding]:
    pat = re.compile(r"(?s)for\s+\w+\s+in\s+\w+\.objects\.all\s*\(\s*\)\s*:")
    return _scan(content, pat, lambda ln, m: Finding(
        severity="MEDIUM", source="orm", rule_id="DB-DJ-all-in-loop",
        file=path, line=ln, category="db-query",
        message="Iterating .objects.all() loads entire table into memory. Use .iterator() or pagination.",
    ))


# ---- ActiveRecord ----
@orm("orm-activerecord", "DB-AR-missing-includes")
def r_ar_missing_includes(path: str, content: str) -> list[Finding]:
    pat = re.compile(r"\.where\s*\([^)]*\)\.each\s+do\s+\|\w+\|[^\n]*\n[^\n]*\.\w+\.\w+")
    return _scan(content, pat, lambda ln, m: Finding(
        severity="MEDIUM", source="orm", rule_id="DB-AR-missing-includes",
        file=path, line=ln, category="db-n-plus-one",
        message="ActiveRecord chain misses .includes(:relation). Use eager loading.",
    ))


@orm("orm-activerecord", "DB-AR-has-many-no-counter")
def r_ar_no_counter(path: str, content: str) -> list[Finding]:
    pat = re.compile(r"belongs_to\s+:\w+(?![^,\n]*counter_cache)")
    return _scan(content, pat, lambda ln, m: Finding(
        severity="LOW", source="orm", rule_id="DB-AR-has-many-no-counter",
        file=path, line=ln, category="db-query",
        message="belongs_to without counter_cache. .count on parent will hit DB each time.",
    ))


@orm("orm-activerecord", "DB-AR-find-each-skipped")
def r_ar_find_each(path: str, content: str) -> list[Finding]:
    pat = re.compile(r"\b(?:User|Order|Account|Customer|Product)\.all\b")
    return _scan(content, pat, lambda ln, m: Finding(
        severity="MEDIUM", source="orm", rule_id="DB-AR-find-each-skipped",
        file=path, line=ln, category="db-query",
        message="Model.all loads the whole table. Use .find_each / .find_in_batches for iteration.",
    ))


# ---- Sequelize ----
@orm("orm-sequelize", "DB-SQ-no-include")
def r_sq_no_include(path: str, content: str) -> list[Finding]:
    pat = re.compile(r"\.findAll\s*\(\s*\{(?![^}]*\binclude\s*:)[^}]*\}\s*\)")
    return _scan(content, pat, lambda ln, m: Finding(
        severity="MEDIUM", source="orm", rule_id="DB-SQ-no-include",
        file=path, line=ln, category="db-n-plus-one",
        message="Sequelize findAll without include. Eager-load associations to avoid N+1.",
    ))


@orm("orm-sequelize", "DB-SQ-raw-no-replacements")
def r_sq_raw(path: str, content: str) -> list[Finding]:
    pat = re.compile(r"sequelize\.query\s*\(\s*[`\"'][^`\"']*\$\{[^}]+\}")
    return _scan(content, pat, lambda ln, m: Finding(
        severity="MEDIUM", source="orm", rule_id="DB-SQ-raw-no-replacements",
        file=path, line=ln, category="db-query",
        message="sequelize.query with template-string interpolation. Use replacements/bind to keep query plan stable.",
    ))


@orm("orm-sequelize", "DB-SQ-missing-indexes")
def r_sq_missing_indexes(path: str, content: str) -> list[Finding]:
    pat = re.compile(r"sequelize\.define\s*\(\s*[\"']\w+[\"']\s*,[^)]*?(?<!indexes\s*:\s*\[)")
    return _scan(content, pat, lambda ln, m: Finding(
        severity="LOW", source="orm", rule_id="DB-SQ-missing-indexes",
        file=path, line=ln, category="db-index",
        message="sequelize.define without indexes:[]. Add explicit composite/single indexes.",
    ))


# ---- TypeORM ----
@orm("orm-typeorm", "DB-TO-many-to-one-lazy")
def r_to_lazy(path: str, content: str) -> list[Finding]:
    pat = re.compile(r"@ManyToOne\s*\([^)]*\blazy\s*:\s*true")
    return _scan(content, pat, lambda ln, m: Finding(
        severity="MEDIUM", source="orm", rule_id="DB-TO-many-to-one-lazy",
        file=path, line=ln, category="db-n-plus-one",
        message="TypeORM @ManyToOne with lazy:true. Each access triggers a query — confirm intent.",
    ))


@orm("orm-typeorm", "DB-TO-missing-Index-decorator")
def r_to_missing_index(path: str, content: str) -> list[Finding]:
    pat = re.compile(r"@(?:JoinColumn|ManyToOne|OneToOne)[^\n]*\n(?:\s*//[^\n]*\n)*\s*(?!@Index)\s*\w+\s*:")
    return _scan(content, pat, lambda ln, m: Finding(
        severity="MEDIUM", source="orm", rule_id="DB-TO-missing-Index-decorator",
        file=path, line=ln, category="db-index",
        message="TypeORM relation without @Index. JOINs and WHEREs on this column will scan.",
    ))


@orm("orm-typeorm", "DB-TO-find-no-relations")
def r_to_find_no_rel(path: str, content: str) -> list[Finding]:
    pat = re.compile(r"\.find(?:One)?\s*\(\s*\{(?![^}]*\brelations\s*:)[^}]*\}\s*\)")
    return _scan(content, pat, lambda ln, m: Finding(
        severity="LOW", source="orm", rule_id="DB-TO-find-no-relations",
        file=path, line=ln, category="db-n-plus-one",
        message="TypeORM find/findOne without relations. If you access related entities later, this is N+1.",
    ))


# ---- GORM ----
@orm("orm-gorm", "DB-GR-missing-Preload")
def r_gr_no_preload(path: str, content: str) -> list[Finding]:
    pat = re.compile(r"db\.Find\s*\(\s*&\w+\s*\)(?![^.]*\.Preload)")
    return _scan(content, pat, lambda ln, m: Finding(
        severity="MEDIUM", source="orm", rule_id="DB-GR-missing-Preload",
        file=path, line=ln, category="db-n-plus-one",
        message="GORM .Find without .Preload. Each related access triggers a query.",
    ))


@orm("orm-gorm", "DB-GR-fk-no-index-tag")
def r_gr_fk_no_index(path: str, content: str) -> list[Finding]:
    pat = re.compile(r"`gorm:\"[^\"]*foreignKey:[^\"]*\"`(?![^`]*index)")
    return _scan(content, pat, lambda ln, m: Finding(
        severity="MEDIUM", source="orm", rule_id="DB-GR-fk-no-index-tag",
        file=path, line=ln, category="db-index",
        message="GORM foreignKey tag without index tag. Add `index` to gorm tag.",
    ))


@orm("orm-gorm", "DB-GR-raw-no-bind")
def r_gr_raw(path: str, content: str) -> list[Finding]:
    pat = re.compile(r"db\.Raw\s*\(\s*fmt\.Sprintf")
    return _scan(content, pat, lambda ln, m: Finding(
        severity="MEDIUM", source="orm", rule_id="DB-GR-raw-no-bind",
        file=path, line=ln, category="db-query",
        message="GORM db.Raw with fmt.Sprintf. Use placeholder bindings for plan stability.",
    ))


# ---- Eloquent (Laravel) ----
@orm("orm-eloquent", "DB-EL-missing-with")
def r_el_missing_with(path: str, content: str) -> list[Finding]:
    pat = re.compile(r"::\s*all\s*\(\s*\)\s*->\s*each\b")
    return _scan(content, pat, lambda ln, m: Finding(
        severity="MEDIUM", source="orm", rule_id="DB-EL-missing-with",
        file=path, line=ln, category="db-n-plus-one",
        message="Eloquent ::all()->each without ::with(). Eager-load relations.",
    ))


@orm("orm-eloquent", "DB-EL-n-plus-one-loop")
def r_el_loop(path: str, content: str) -> list[Finding]:
    pat = re.compile(r"foreach\s*\(\s*\$\w+\s+as\s+\$\w+\s*\)[^{]*\{[^}]*->\w+->\w+")
    return _scan(content, pat, lambda ln, m: Finding(
        severity="MEDIUM", source="orm", rule_id="DB-EL-n-plus-one-loop",
        file=path, line=ln, category="db-n-plus-one",
        message="foreach over collection accesses ->relation->attr inside the loop — classic Eloquent N+1.",
    ))


@orm("orm-eloquent", "DB-EL-fillable-missing")
def r_el_fillable(path: str, content: str) -> list[Finding]:
    pat = re.compile(r"class\s+\w+\s+extends\s+Model\b(?![^}]*\$fillable)")
    return _scan(content, pat, lambda ln, m: Finding(
        severity="LOW", source="orm", rule_id="DB-EL-fillable-missing",
        file=path, line=ln, category="db-schema",
        message="Eloquent Model without $fillable. Mass-assignment defaults to guarded — confirm explicit lists.",
    ))


# ============================================================
# Public API
# ============================================================

def scan_file(path: str, content: str, stack_tags: set[str]) -> list[Finding]:
    findings: list[Finding] = []
    # Generic core rules only fire if at least one DB tag is present.
    has_db_tag = any(t.startswith("db-") for t in stack_tags)
    if has_db_tag:
        for fn in _GENERIC_RULES:
            try:
                findings.extend(fn(path, content))
            except Exception:
                pass
    # ORM add-ons fire only if their tag is detected.
    for tag in stack_tags:
        if not tag.startswith("orm-"):
            continue
        for fn in _ORM_RULES.get(tag, []):
            try:
                findings.extend(fn(path, content))
            except Exception:
                pass
    return findings


def all_rule_ids() -> list[str]:
    out = [fn.rule_id for fn in _GENERIC_RULES]
    for tag, fns in _ORM_RULES.items():
        out.extend(fn.rule_id for fn in fns)
    return sorted(out)


def rules_version_seed() -> str:
    src = Path(__file__).read_text(encoding="utf-8")
    return "|".join(all_rule_ids()) + "\n---\n" + src
