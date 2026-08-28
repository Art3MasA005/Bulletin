# Retrieval score floor — first measurement

**Date:** 2026-08-28 · **Corpus:** 9 Green University documents, 51 chunks, all English
**Embeddings:** `baai/bge-m3` (1024-dim) via OpenRouter · **Index:** pgvector HNSW, cosine

PRD §7.2 step 7 / CLAUDE.md #9: below `RETRIEVAL_SCORE_FLOOR` the not-found response is
returned **without calling the LLM**. That only works if a threshold can separate
questions the corpus answers from questions it does not. This is the first measurement of
whether it can.

Ten questions, top-1 dense cosine similarity:

| | score | question |
|---|---|---|
| in-corpus | 0.700 | what happens if a student uses a mobile phone in the exam hall |
| in-corpus | 0.612 | when do the final examinations start |
| in-corpus | 0.552 | how do students evaluate teachers this semester |
| in-corpus | 0.546 | CSE 211 makeup exam date |
| in-corpus | **0.532** | when is the Eid-e-Milad-un-Nabi holiday |
| out-of-corpus | **0.521** | who is the vice chancellor of the university |
| out-of-corpus | 0.480 | how do I apply for a scholarship |
| out-of-corpus | 0.444 | what is the refund policy for tuition |
| out-of-corpus | 0.411 | how much is the hostel accommodation fee per month |
| out-of-corpus | 0.392 | what is the library book borrowing limit |

## The finding

**The two populations overlap.** The weakest in-corpus question (0.532) sits 0.011 above
the strongest out-of-corpus one (0.521). There is no threshold on this corpus that admits
every answerable question and refuses every unanswerable one.

The reason is visible in the questions themselves: "who is the vice chancellor of the
university" is written in the same institutional register as the corpus, so a
general-purpose embedding places it near documents about that institution — near enough
that cosine similarity cannot tell "this is about your university" from "your university
published this".

## What was done about it

`BULLETIN_RETRIEVAL_SCORE_FLOOR` raised **0.35 → 0.45**, which on this sample:

- refuses 3 of 5 out-of-corpus questions before any generation call
- refuses 0 of 5 in-corpus questions, with 0.08 of margin below the weakest

The old 0.35 refused nothing at all: the "hostel fee" question passed the gate at 0.411
and reached the LLM, which then said the context did not contain the answer. The right
outcome by the wrong path — and one that costs a generation call every time.

The overlap band (0.45–0.53) is handled by the generation prompt, which instructs the
model to say the context does not contain the answer rather than reason toward a likely
one. Observed working on the hostel-fee question.

## Still open

- 0.45 is fitted to ten questions. Re-tune against the 70-question gold set (TASKS.md
  Phase 1) and record the confusion matrix at several floors, not a single number.
- Worth testing whether the reranker's score separates the two populations better than
  cosine does. If it does, the gate belongs after reranking rather than before — PRD §6
  permits skipping reranking, but not if it turns out to be the only reliable gate.
- Every question here is English. The Bangla slices will need their own measurement; a
  cross-lingual query's dense score is systematically lower, so one floor may not serve
  both (that is Ablation A's territory).
