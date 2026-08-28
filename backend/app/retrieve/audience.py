"""Role -> allowed audience set. PRD 4, CLAUDE.md #4.

    "The filter is applied to the retrieval query, before vector search --
    never to results afterward. Post-filtering leaks information through the
    not-found boundary and is easy to get subtly wrong."

Why post-filtering leaks even when it looks correct: if the top 20 candidates
are fetched without the filter and then stripped, a student asking about a
teacher-only salary policy gets an empty result where an unrelated question
gets answers. The *shape* of the failure reveals that matching content exists.
Worse, the reranker and the score floor both see the unfiltered set, so a
student's not-found threshold is decided by documents they cannot read.

This module exposes the allowed set and a SQL predicate. It deliberately does
NOT expose a "filter these results" helper -- there is no correct way to use
one, so the module refuses to provide it.

Defence in depth: this predicate is the application layer. RLS on `chunks`
(CLAUDE.md #5) is the database layer, and it is not optional. Both, always.
"""

from __future__ import annotations

from enum import StrEnum


class Role(StrEnum):
    STUDENT = "student"
    TEACHER = "teacher"
    ADMIN = "admin"


class Audience(StrEnum):
    ALL = "all"
    STUDENTS = "students"
    TEACHERS = "teachers"
    ADMIN_ONLY = "admin_only"


# Explicit table rather than computed logic. A reader must be able to see, at a
# glance, that a student cannot reach teacher content -- PRD 13 makes
# out-of-audience refusal a 100% pass/fail criterion, not a quality target.
_ALLOWED: dict[Role, frozenset[Audience]] = {
    Role.STUDENT: frozenset({Audience.ALL, Audience.STUDENTS}),
    Role.TEACHER: frozenset({Audience.ALL, Audience.STUDENTS, Audience.TEACHERS}),
    Role.ADMIN: frozenset(
        {Audience.ALL, Audience.STUDENTS, Audience.TEACHERS, Audience.ADMIN_ONLY}
    ),
}


class UnknownRole(ValueError):
    """An unrecognised role. Never defaults to a permissive set."""


def allowed_audiences(role: Role | str) -> frozenset[Audience]:
    """Audiences this role may retrieve.

    An unknown role raises rather than falling back. A typo in a role string
    must not silently widen access.
    """
    try:
        resolved = Role(role)
    except ValueError as exc:
        raise UnknownRole(f"unknown role {role!r}; refusing to guess an audience set") from exc
    return _ALLOWED[resolved]


def can_access(role: Role | str, audience: Audience | str) -> bool:
    """Whether `role` may see content tagged `audience`."""
    try:
        target = Audience(audience)
    except ValueError as exc:
        raise UnknownRole(f"unknown audience {audience!r}") from exc
    return target in allowed_audiences(role)


def audience_sql(role: Role | str, *, column: str = "audience") -> tuple[str, list[str]]:
    """SQL predicate plus parameters, for use INSIDE the retrieval query.

    Returns a fragment to place in the WHERE clause of the vector search
    itself, never applied to its output:

        WHERE institution_id = %s AND audience = ANY(%s)
        ORDER BY embedding <=> %s LIMIT 20

    Parameterised, never interpolated -- the caller passes the values through
    to the driver.
    """
    values = sorted(a.value for a in allowed_audiences(role))
    return f"{column} = ANY(%s)", [values]
