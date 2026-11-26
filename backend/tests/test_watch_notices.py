"""The notice watcher's parsing and its refusal to decide for the user.

No network here. What is worth testing is the part that will break silently
when the site changes its markup, and the part that must not quietly do the
wrong thing with a notice about named students.
"""

from __future__ import annotations

from pathlib import Path

from tools.watch_notices import (
    DETAIL_RE,
    INGESTIBLE,
    Notice,
    list_notices,
    resolve_attachment,
)

LISTING = """
<div class="notices">
  <a href="https://green.edu.bd/notice-details/holiday-for-eid">Holiday</a>
  <a href="https://green.edu.bd/notice-details/final-exam-routine">Routine</a>
  <a href="https://green.edu.bd/notice-details/holiday-for-eid">Holiday again</a>
  <a href="https://green.edu.bd/admission-notice">Not a notice detail</a>
</div>
"""

DETAIL_PDF = """
<h1>Holiday for Eid-e-Milad-un-Nabi</h1>
<iframe src="https://admin.green.edu.bd/storage/files/registrar/holiday-178.pdf#toolbar=0"></iframe>
"""

DETAIL_XLSX = """
<h1>Final Examination Routine</h1>
<a href="https://admin.green.edu.bd/storage/files/tex/ddd-1783685781.xlsx">Download</a>
"""

DETAIL_NOTHING = "<h1>Notice</h1><p>The text is on the page itself.</p>"


def notice(slug: str = "holiday-for-eid", title: str = "Holiday") -> Notice:
    return Notice(slug=slug, url=f"https://green.edu.bd/notice-details/{slug}", title=title)


# ── parsing the site ────────────────────────────────────────────────────────


def test_detail_links_are_found_and_deduplicated() -> None:
    slugs = [m.group(1).rsplit("/", 1)[-1] for m in DETAIL_RE.finditer(LISTING)]
    assert slugs == ["holiday-for-eid", "final-exam-routine", "holiday-for-eid"]


def test_the_listing_ignores_links_that_are_not_notice_details() -> None:
    assert "admission-notice" not in [m.group(1) for m in DETAIL_RE.finditer(LISTING)]


def test_a_pdf_attachment_is_found_and_its_fragment_dropped(monkeypatch) -> None:
    monkeypatch.setattr("tools.watch_notices._get", lambda *a, **k: DETAIL_PDF.encode())
    url, title = resolve_attachment(notice())
    assert url == "https://admin.green.edu.bd/storage/files/registrar/holiday-178.pdf"
    assert title == "Holiday for Eid-e-Milad-un-Nabi"


def test_a_spreadsheet_attachment_is_found_too(monkeypatch) -> None:
    """The exam routines — the most valuable documents on the feed — are .xlsx.

    A pdf-only pattern skipped them silently, which is the worst way to lose
    the one document type that has no OCR layer to be wrong about.
    """
    monkeypatch.setattr("tools.watch_notices._get", lambda *a, **k: DETAIL_XLSX.encode())
    url, _ = resolve_attachment(notice("final-exam-routine"))
    assert url is not None and url.endswith(".xlsx")


def test_a_notice_with_no_attachment_returns_none_rather_than_raising(monkeypatch) -> None:
    monkeypatch.setattr("tools.watch_notices._get", lambda *a, **k: DETAIL_NOTHING.encode())
    url, _ = resolve_attachment(notice())
    assert url is None


def test_the_listing_survives_a_page_with_no_notices(monkeypatch) -> None:
    monkeypatch.setattr("tools.watch_notices._get", lambda *a, **k: b"<html></html>")
    assert list_notices() == []


def test_a_spreadsheet_is_known_to_be_unreadable_today() -> None:
    """If this ever fails because .xlsx was added to INGESTIBLE, the extractor
    had better exist — the listing tells the user which formats it can use."""
    assert ".pdf" in INGESTIBLE
    assert ".xlsx" not in INGESTIBLE


# ── the part that must not decide for the user ──────────────────────────────


def test_a_disciplinary_notice_is_flagged() -> None:
    """Two notices on this feed name students and print their IDs. Indexing
    them would put one student's punishment where every other student can
    retrieve it."""
    assert notice("disciplinary-action-against-few-students").looks_personal


def test_the_flag_reads_the_title_as_well_as_the_slug() -> None:
    assert Notice(slug="notice-2026-08", url="u", title="Show cause to a student").looks_personal


def test_an_ordinary_notice_is_not_flagged() -> None:
    assert not notice("holiday-for-eid").looks_personal
    assert not notice("final-examination-routine-spring-2026").looks_personal


def test_flagging_never_filters() -> None:
    """The mark is a prompt to think, not a control to trust. A keyword list
    that silently dropped notices would be worse than none, because it would
    invite relying on it."""
    source = Path("tools/watch_notices.py").read_text(encoding="utf-8")
    body = source.split("def main(")[1]
    assert "looks_personal" in body, "the flag must reach the listing"
    assert "if notice.looks_personal: continue" not in body.replace("\n", " ")


# ── what counts as already fetched ──────────────────────────────────────────


def test_a_notice_is_new_until_any_file_for_it_exists(tmp_path: Path) -> None:
    item = notice("final-exam-routine")
    assert item.existing(tmp_path) is None
    (tmp_path / "final-exam-routine.xlsx").write_bytes(b"x")
    assert item.existing(tmp_path) is not None


def test_the_format_does_not_matter_for_deduplication(tmp_path: Path) -> None:
    """Re-downloading a notice as a .pdf because it was first saved as .xlsx
    would ingest the same notice twice under two filenames."""
    item = notice("holiday-for-eid")
    (tmp_path / "holiday-for-eid.pdf").write_bytes(b"%PDF-1.4")
    assert item.existing(tmp_path) is not None


def test_another_notices_file_does_not_count(tmp_path: Path) -> None:
    (tmp_path / "some-other-notice.pdf").write_bytes(b"%PDF-1.4")
    assert notice("holiday-for-eid").existing(tmp_path) is None
