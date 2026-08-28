"""Audience scoping.

CLAUDE.md non-negotiable: "A student query cannot retrieve teacher-scoped
chunks." The full assertion runs against a seeded corpus and RLS in Phase 4;
this file pins the policy the query is built from, which is where the rule is
decided.

PRD 13 makes out-of-audience refusal 100% pass/fail -- a correctness boundary,
not a quality target.
"""

from __future__ import annotations

import pytest

from app.retrieve.audience import (
    Audience,
    Role,
    UnknownRole,
    allowed_audiences,
    audience_sql,
    can_access,
)

# ── the rule that must never break ──────────────────────────────────────────


def test_student_cannot_access_teacher_content() -> None:
    assert not can_access(Role.STUDENT, Audience.TEACHERS)


def test_student_cannot_access_admin_only_content() -> None:
    assert not can_access(Role.STUDENT, Audience.ADMIN_ONLY)


def test_teacher_cannot_access_admin_only_content() -> None:
    assert not can_access(Role.TEACHER, Audience.ADMIN_ONLY)


def test_student_sees_only_all_and_students() -> None:
    assert allowed_audiences(Role.STUDENT) == {Audience.ALL, Audience.STUDENTS}


def test_teacher_sees_student_content_too() -> None:
    """A faculty member may read what students read; the reverse is the risk."""
    assert can_access(Role.TEACHER, Audience.STUDENTS)
    assert can_access(Role.TEACHER, Audience.TEACHERS)


def test_admin_sees_everything() -> None:
    assert allowed_audiences(Role.ADMIN) == set(Audience)


@pytest.mark.parametrize("role", list(Role))
def test_every_role_can_read_all_audience(role: Role) -> None:
    assert can_access(role, Audience.ALL)


def test_no_role_below_admin_reaches_admin_only() -> None:
    for role in (Role.STUDENT, Role.TEACHER):
        assert Audience.ADMIN_ONLY not in allowed_audiences(role)


# ── failure modes must not widen access ─────────────────────────────────────


def test_unknown_role_raises_rather_than_defaulting() -> None:
    """A typo must never resolve to a permissive set."""
    with pytest.raises(UnknownRole):
        allowed_audiences("stduent")


def test_empty_role_raises() -> None:
    with pytest.raises(UnknownRole):
        allowed_audiences("")


def test_unknown_audience_raises() -> None:
    with pytest.raises(UnknownRole):
        can_access(Role.STUDENT, "everyone")


def test_role_accepts_plain_strings_from_a_jwt_claim() -> None:
    assert allowed_audiences("student") == allowed_audiences(Role.STUDENT)


# ── the predicate goes in the query ─────────────────────────────────────────


def test_sql_predicate_is_parameterised_not_interpolated() -> None:
    sql, params = audience_sql(Role.STUDENT)
    assert sql == "audience = ANY(%s)"
    assert params == [["all", "students"]]
    assert "students" not in sql, "values must not be interpolated into SQL"


def test_sql_predicate_for_student_excludes_teacher_audiences() -> None:
    _, params = audience_sql(Role.STUDENT)
    assert "teachers" not in params[0]
    assert "admin_only" not in params[0]


def test_sql_predicate_column_is_configurable_for_joins() -> None:
    sql, _ = audience_sql(Role.TEACHER, column="c.audience")
    assert sql == "c.audience = ANY(%s)"


def test_module_exposes_no_post_filtering_helper() -> None:
    """Post-filtering leaks through the not-found boundary (CLAUDE.md #4).

    There is no correct way to use such a helper, so the module must not offer
    one -- its presence would be an invitation to the exact bug.
    """
    import app.retrieve.audience as module

    names = [n.lower() for n in dir(module) if not n.startswith("_")]
    for banned in ("filter_results", "filter_chunks", "strip_disallowed"):
        assert banned not in names


# ── the SQL policy and the Python policy must not drift ─────────────────────


def test_sql_allowed_audiences_matches_the_python_table() -> None:
    """RLS and the query predicate encode the same rule in two languages.

    They are defence in depth only while they agree. If they drift, one of them
    is wrong and nobody finds out until a student sees a salary policy.
    """
    import re
    from pathlib import Path as _Path

    sql = (
        _Path(__file__).resolve().parents[1] / "app" / "db" / "migrations" / "0001_init.sql"
    ).read_text(encoding="utf-8")

    body = sql[sql.index("function allowed_audiences") :]
    body = body[: body.index("$$", body.index("$$") + 2)]

    for role, marker in (
        (Role.ADMIN, "when 'admin'"),
        (Role.TEACHER, "when 'teacher'"),
        (Role.STUDENT, "else"),
    ):
        line = next(ln for ln in body.splitlines() if marker in ln)
        found = set(re.findall(r"'(all|students|teachers|admin_only)'", line))
        expected = {a.value for a in allowed_audiences(role)}
        assert found == expected, f"{role.value}: SQL {found} != Python {expected}"


def test_attachments_table_has_no_embedding_column() -> None:
    """CLAUDE.md #2, at the schema level: there is nowhere to index them."""
    from pathlib import Path as _Path

    sql = (
        _Path(__file__).resolve().parents[1] / "app" / "db" / "migrations" / "0001_init.sql"
    ).read_text(encoding="utf-8")

    block = sql[sql.index("create table attachments") :]
    block = block[: block.index(");")]
    assert "vector(" not in block
    assert "embedding" not in block
