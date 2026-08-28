"""Greetings and small talk, answered without pretending to be grounded.

A student who types "hi" is not asking a question the corpus can answer, and
answering with *"Nothing in the published documents covers this"* is wrong
twice over: it is rude, and it misuses the not-found state, whose whole job is
to say **this institution has not published that** (PRD §13, DESIGN §6.3). Say
that about a greeting and the message stops meaning anything.

The boundary this module holds:

    greeting / thanks / goodbye   ->  a fixed, local reply. No model call, no
                                      citations, no claim about any document.
    anything else                 ->  retrieval, exactly as before.

It is deliberately NOT a chat mode. There is no model call here at all: the
replies are constants. The product's promise is that every factual sentence is
traceable to a page (PRD §2), and a model free to chat is a model free to
answer "when do exams start?" from memory. A fixed greeting cannot.

Matching is whole-message only. "hi when do finals start" is a question with a
greeting attached, and it goes to retrieval.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass

from app.bangla.normalize import detect_lang, normalize

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class SmallTalk:
    """A recognised non-question, and what to say back."""

    kind: str  # "greeting" | "thanks" | "farewell"
    reply_en: str
    reply_bn: str

    def reply(self, lang: str) -> str:
        return self.reply_bn if lang == "bn" else self.reply_en


# The reply says what the app is for, because a greeting is usually the first
# thing a new user types and the answer is a chance to teach the product
# (DESIGN §6.2: an empty screen is an invitation to act).
GREETING = SmallTalk(
    kind="greeting",
    reply_en=(
        "Hello. Ask me anything your institution has published — exam dates, "
        "fees, notices, holidays — and I will answer with the page it came from."
    ),
    reply_bn=(
        "আসসালামু আলাইকুম। আপনার প্রতিষ্ঠানের প্রকাশিত যেকোনো বিষয়ে জিজ্ঞাসা করুন — "
        "পরীক্ষার তারিখ, ফি, নোটিশ, ছুটি — উত্তরের সঙ্গে উৎস পৃষ্ঠাও পাবেন।"
    ),
)

THANKS = SmallTalk(
    kind="thanks",
    reply_en="Any time. Ask whenever you need something from the documents.",
    reply_bn="যেকোনো সময়। নথিপত্র থেকে কিছু জানার থাকলে জিজ্ঞাসা করবেন।",
)

FAREWELL = SmallTalk(
    kind="farewell",
    reply_en="Goodbye. Come back whenever you need an answer.",
    reply_bn="আল্লাহ হাফেজ। প্রয়োজনে আবার আসবেন।",
)

# Whole-message patterns only. Each is anchored, so a greeting followed by a
# real question does not match and goes to retrieval instead.
_PATTERNS: list[tuple[re.Pattern[str], SmallTalk]] = [
    (
        re.compile(
            r"^(hi|hii+|hey+|hello+|helo|yo|salam|salaam|assalamu\s*alaikum|"
            r"as+alamualaikum|good\s*(morning|afternoon|evening|night)|"
            r"হাই|হ্যালো|আসসালামু\s*আলাইকুম|সালাম|শুভ\s*(সকাল|বিকেল|সন্ধ্যা|রাত্রি|রাত))"
            r"[\s!.,?]*$",
            re.IGNORECASE,
        ),
        GREETING,
    ),
    (
        re.compile(
            r"^(thanks?|thank\s*you|thx|ty|shukriya|dhonnobad|"
            r"ধন্যবাদ|শুকরিয়া|থ্যাংকস)[\s!.,]*$",
            re.IGNORECASE,
        ),
        THANKS,
    ),
    (
        re.compile(
            r"^(bye+|goodbye|see\s*you|khoda\s*hafez|allah\s*hafez|"
            r"বিদায়|আল্লাহ\s*হাফেজ|খোদা\s*হাফেজ)[\s!.,]*$",
            re.IGNORECASE,
        ),
        FAREWELL,
    ),
    (
        re.compile(
            r"^(who\s+are\s+you|what\s+(are|can)\s+you\s+do|what\s+is\s+this|help|"
            r"তুমি\s*কে|আপনি\s*কে|কী\s*করতে\s*পারো|এটা\s*কী|সাহায্য)[\s!.,?]*$",
            re.IGNORECASE,
        ),
        GREETING,
    ),
]

# Longer than this and it is not a greeting, whatever it matches. Guards
# against a pathological input padded with punctuation.
MAX_SMALLTALK_CHARS = 60


def detect(question: str) -> SmallTalk | None:
    """Return the small talk this message is, or None to retrieve as usual."""
    text = normalize(question or "").strip()
    if not text or len(text) > MAX_SMALLTALK_CHARS:
        return None

    for pattern, response in _PATTERNS:
        if pattern.match(text):
            logger.info("small talk kind=%s", response.kind)
            return response
    return None


def reply_for(question: str) -> tuple[str, str] | None:
    """(reply, kind) in the question's own language, or None."""
    found = detect(question)
    if found is None:
        return None
    return found.reply(detect_lang(question)), found.kind
