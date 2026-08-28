"""Generated fixture PDFs: Unicode Bangla, legacy-font Bangla, scanned, English.

CLAUDE.md requires classify.py tests against real fixture PDFs rather than
mocks. These are built at test time with PyMuPDF so the repository carries no
binaries, and -- importantly -- the legacy fixture is a genuine ASCII-mapped
PDF: its text layer extracts as Latin gibberish while the page renders as
normal Bangla. That is the exact failure mode the pipeline must catch.
"""

from __future__ import annotations

from pathlib import Path

import pymupdf

# Unicode Bangla and its legacy ASCII-mapped equivalent.
BANGLA_UNICODE = (
    "পরীক্ষা ১৫ জানুয়ারি ২০২৬ তারিখে শুরু হবে।\n"
    "বিশ্ববিদ্যালয় কর্তৃপক্ষ কর্তৃক জানানো যাচ্ছে যে,\n"
    "ছাত্রাবাসের নিয়ম অনুযায়ী আবেদন করতে হবে।"
)
BANGLA_LEGACY = (
    "wek¦we`¨vjq KZ©c£ KZ©K cix¶vi ZvwiL Rvbv‡bv hv‡‡Q\n"
    "cix¶v ïi\u0081 n‡e 15 Rvbyqvwi 2026 Zvwi‡L\n"
    "QvÎvevm cÖweavb Abyhvqx Av‡e`b Ki‡Z n‡e"
)
ENGLISH_TEXT = (
    "Final examinations for the Spring 2026 semester commence on 15 January.\n"
    "Students must carry their admit card to every session.\n"
    "Applications for hostel accommodation close on 30 December.\n"
    "The scholarship committee meets in the first week of February."
)

# A scan whose OCR text layer is present, Unicode, not Bijoy -- and wrong.
# Copied from `corpus/inbox/CSE Final Exam Routine Summer 2026 Semester001.pdf`,
# which classify.py labels native_text with high confidence. The mangled dates
# ("07 SIiPTENIBER 2026") are the wrong-answer failure this gate exists for.
BAD_OCR_TEXT = (
    "CSE (Regular)-FINAL Exa#ihation Routine, Summer 2026 DAY Departrnent\n"
    "ofComptrter Science & Eogineering FINAL Exsmlnotlon Routln€\n"
    "07 SIiPTENIBER 2026 I I SnP',rf tltBtiR 2026 06:00 Pll - 08:00 PNI\n"
    "icut( t Bryamcoattd (04 0opanment d CSE teen Urwers{Y d BdCdest'\n"
    "Stt*,,,,' !60 26t t5l 250 251 2.t! 2!t 212 ] 2lt 1t:r ffi t',1 t!.irr4"
)

# Native text carrying the apostrophe-for-hyphen substitution the real corpus
# contains. The euro-for-E half of the damage cannot be fixture-generated --
# base-14 Helvetica has no euro glyph and PyMuPDF writes "?" instead -- so it
# is covered against real corpus strings in test_ocr_quality.py.
OCR_CODE_TEXT = (
    "Makeup Examination Schedule Summer 2026\n"
    "CSE'211: Computer Architecture, 11 August 2026, 10:00 am\n"
    "ENG'207: Business English, 12 August 2026, 12:00 pm\n"
    "All students must carry their admit card to every session listed above."
)

# Candidate font paths, tried in order. Windows ships both variants of
# Kalpurush; a Linux CI box would need one installed.
UNICODE_BANGLA_FONTS = (
    "C:/Windows/Fonts/kalpurush.ttf",
    "C:/Windows/Fonts/Nirmala.ttc",
    "/usr/share/fonts/truetype/noto/NotoSansBengali-Regular.ttf",
)
LEGACY_BANGLA_FONTS = (
    "C:/Windows/Fonts/kalpurush ANSI.ttf",
    "C:/Windows/Fonts/SutonnyMJ.ttf",
)


def find_font(candidates: tuple[str, ...]) -> str | None:
    for path in candidates:
        if Path(path).exists():
            return path
    return None


def _text_pdf(path: Path, text: str, *, fontfile: str | None, fontname: str) -> Path:
    doc = pymupdf.open()
    page = doc.new_page()
    if fontfile:
        page.insert_font(fontname=fontname, fontfile=fontfile)
        page.insert_textbox(pymupdf.Rect(40, 60, 550, 700), text, fontname=fontname, fontsize=13)
    else:
        page.insert_textbox(pymupdf.Rect(40, 60, 550, 700), text, fontsize=13)
    doc.save(path)
    doc.close()
    return path


def english_pdf(path: Path) -> Path:
    """Native text layer, English. The P0 happy path."""
    return _text_pdf(path, ENGLISH_TEXT, fontfile=None, fontname="helv")


def bad_ocr_pdf(path: Path) -> Path:
    """A text layer that is present and unreadable -- the fourth routing state."""
    return _text_pdf(path, BAD_OCR_TEXT, fontfile=None, fontname="helv")


def ocr_code_pdf(path: Path) -> Path:
    """Clean-enough English whose course codes carry the measured OCR damage."""
    return _text_pdf(path, OCR_CODE_TEXT, fontfile=None, fontname="helv")


def bangla_unicode_pdf(path: Path) -> Path | None:
    """Native text layer, Unicode Bangla. None when no Bengali font is present."""
    font = find_font(UNICODE_BANGLA_FONTS)
    if not font:
        return None
    return _text_pdf(path, BANGLA_UNICODE, fontfile=font, fontname="bnuni")


def bangla_legacy_pdf(path: Path) -> Path | None:
    """ASCII-mapped legacy font. Extracts as Latin gibberish, renders as Bangla."""
    font = find_font(LEGACY_BANGLA_FONTS)
    if not font:
        return None
    return _text_pdf(path, BANGLA_LEGACY, fontfile=font, fontname="bnansi")


def scanned_pdf(path: Path) -> Path:
    """A page carrying only an image -- no text layer at all."""
    doc = pymupdf.open()
    page = doc.new_page()
    pixmap = pymupdf.Pixmap(pymupdf.csRGB, pymupdf.IRect(0, 0, 600, 800))
    pixmap.set_rect(pixmap.irect, (235, 235, 235))
    page.insert_image(pymupdf.Rect(0, 0, 600, 800), pixmap=pixmap)
    doc.save(path)
    doc.close()
    return path


def empty_pdf(path: Path) -> Path:
    """A blank page. Must be rejected rather than silently indexed."""
    doc = pymupdf.open()
    doc.new_page()
    doc.save(path)
    doc.close()
    return path


def encrypted_pdf(path: Path) -> Path:
    """Password protected. Must be rejected with a readable reason."""
    doc = pymupdf.open()
    page = doc.new_page()
    page.insert_textbox(pymupdf.Rect(40, 60, 550, 700), ENGLISH_TEXT, fontsize=13)
    doc.save(
        path,
        encryption=pymupdf.PDF_ENCRYPT_AES_256,
        owner_pw="owner-secret",
        user_pw="user-secret",
    )
    doc.close()
    return path
