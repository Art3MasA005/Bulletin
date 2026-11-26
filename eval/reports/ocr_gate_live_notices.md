# OCR quality gate against the live notice feed

**Date:** 2026-08-29 · **Source:** 10 notices from `green.edu.bd/notice` · **Pages:** 34 · **Floor:** `BULLETIN_OCR_QUALITY_FLOOR` = 0.9

Every page classifies as `native_text` — there is always a text layer, and it is
always OCR output. This is the fourth case PRD §7.1 does not model, and the reason
`ocr_quality.py` exists.

## Result

| population | pages | score range | escalates to vision |
|---|---:|---|---:|
| prose notices | 8 | 0.869 – 0.996 | 1/8 |
| routine tables | 26 | 0.590 – 0.827 | 26/26 |

**The gate holds.** Every routine-table page escalates, and those are the pages
where a mangled exam date would be answered confidently — the worst failure this
product has. Prose notices pass, and their bodies stay intact enough to retrieve
even where extraction is visibly imperfect.

## The one false escalation

`notice-pre-registration-of-courses-for-fall-2026` scores **0.869** and is sent to
vision, but its body is clean:

> Subject: Pre-Registration of Courses for Fall 2026 Semester (Except Law
> Department). In accordance with the approval of the management authority, this
> is to inform all students of Green University of Ba…

What drags it under the floor is the letterhead:

> `G}T.X,EN T]NIYENSTTY OF BA}'}SLA}ES I-I`

That letterhead is on every notice, extracts badly on all of them, and answers no
question anyone will ask. Scoring a page on boilerplate that repeats corpus-wide
and carries no answerable content is measuring the wrong text.

**Not fixed, deliberately.** This false positive costs one vision read of a page
that renders correctly, so the outcome is still right, only dearer. Excluding a
letterhead means detecting one, and a rule tuned on ten notices from a single
registrar would not survive the second institution. Revisit when the corpus holds
more than one letterhead.

## Correction to an earlier claim

A first look at one notice (`holiday-for-eid-e-milad-un-nabi`, 0.969) suggested
the gate was too lenient, and that apostrophes standing in for terminal
punctuation would sharpen it. Measured across all 34 pages that is wrong twice:
the gate is not too lenient, and the apostrophe rate is 3.5 per 100 words on that
*passing* prose page against 0.0 on every *failing* table page. Adding the signal
would have pushed good prose toward escalation — the opposite of the intent.

## Per page

| notice | page | kind | score |
|---|---:|---|---:|
| `disciplinary-action-against-few-students-of-gu` | 1 | prose | 0.959 |
| `disciplinary-actions-against-a-few-students-fo` | 1 | prose | 0.959 |
| `holiday-for-eid-e-milad-un-nabi` | 1 | prose | 0.969 |
| `makeup-improvement-and-overlap-of-mid-term-exa` | 1 | table | 0.776 ⚠ |
| `makeup-improvement-and-overlap-of-mid-term-exa` | 2 | table | 0.707 ⚠ |
| `makeup-improvement-and-overlap-of-mid-term-exa` | 3 | table | 0.762 ⚠ |
| `makeup-improvement-and-overlap-of-mid-term-exa` | 4 | table | 0.697 ⚠ |
| `makeup-improvement-and-overlap-of-mid-term-exa` | 5 | table | 0.779 ⚠ |
| `makeup-improvement-and-overlap-of-mid-term-exa` | 6 | table | 0.693 ⚠ |
| `makeup-improvement-and-overlap-of-mid-term-exa` | 7 | table | 0.820 ⚠ |
| `makeup-improvement-and-overlap-of-mid-term-exa` | 8 | table | 0.827 ⚠ |
| `makeup-improvement-and-overlap-of-mid-term-exa` | 9 | table | 0.754 ⚠ |
| `makeup-improvement-and-overlap-of-mid-term-exa` | 10 | table | 0.751 ⚠ |
| `makeup-improvement-and-overlap-of-mid-term-exa` | 11 | table | 0.590 ⚠ |
| `makeup-improvement-and-overlap-of-mid-term-exa` | 12 | table | 0.773 ⚠ |
| `makeup-improvement-and-overlap-of-mid-term-exa` | 13 | table | 0.803 ⚠ |
| `makeup-improvement-and-overlap-of-mid-term-exa` | 1 | prose | 0.941 |
| `notice-final-examinationsexcept-law-department` | 1 | prose | 0.920 |
| `notice-holiday-for-july-mass-uprising-day` | 1 | prose | 0.972 |
| `notice-pre-registration-of-courses-for-fall-20` | 1 | prose | 0.869 ⚠ |
| `notice-teachers-evaluation-by-the-students-for` | 1 | prose | 0.996 |
| `updated-makeup-improvement-and-overlap-of-mid-` | 1 | table | 0.776 ⚠ |
| `updated-makeup-improvement-and-overlap-of-mid-` | 2 | table | 0.707 ⚠ |
| `updated-makeup-improvement-and-overlap-of-mid-` | 3 | table | 0.762 ⚠ |
| `updated-makeup-improvement-and-overlap-of-mid-` | 4 | table | 0.697 ⚠ |
| `updated-makeup-improvement-and-overlap-of-mid-` | 5 | table | 0.779 ⚠ |
| `updated-makeup-improvement-and-overlap-of-mid-` | 6 | table | 0.693 ⚠ |
| `updated-makeup-improvement-and-overlap-of-mid-` | 7 | table | 0.820 ⚠ |
| `updated-makeup-improvement-and-overlap-of-mid-` | 8 | table | 0.827 ⚠ |
| `updated-makeup-improvement-and-overlap-of-mid-` | 9 | table | 0.754 ⚠ |
| `updated-makeup-improvement-and-overlap-of-mid-` | 10 | table | 0.718 ⚠ |
| `updated-makeup-improvement-and-overlap-of-mid-` | 11 | table | 0.590 ⚠ |
| `updated-makeup-improvement-and-overlap-of-mid-` | 12 | table | 0.773 ⚠ |
| `updated-makeup-improvement-and-overlap-of-mid-` | 13 | table | 0.803 ⚠ |
