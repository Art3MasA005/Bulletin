# Ablation C — course-code retrieval: dense vs lexical vs hybrid

**Date:** 2026-08-28 · **Corpus:** 9 Green University documents, 51 chunks, English
**Gold set:** 47 answerable + 10 unanswerable questions (`eval/gold_set.jsonl`)
**Embeddings:** `baai/bge-m3` (1024-dim) · **Index:** pgvector HNSW cosine + tsvector + pg_trgm
**Reproduce:** `python eval/run_eval.py --institution <uuid> --ablation`

PRD §12 predicted: *"Expect dense to underperform badly here; that result justifies the
hybrid architecture."* It does — and the margin is in MRR, not Recall.

## Recall@5

| slice | n | dense | lexical | hybrid |
|---|---|---|---|---|
| course_code | 12 | 0.92 | **1.00** | **1.00** |
| notice_native (prose) | 23 | **1.00** | 0.96 | **1.00** |
| routine_vision (tables) | 12 | **1.00** | **1.00** | **1.00** |
| **ALL** | 47 | 0.98 | 0.98 | **1.00** |

## MRR

| slice | n | dense | lexical | hybrid |
|---|---|---|---|---|
| course_code | 12 | **0.74** | **0.94** | 0.92 |
| notice_native (prose) | 23 | **0.98** | 0.93 | 0.95 |
| routine_vision (tables) | 12 | 0.92 | **0.96** | 0.90 |
| **ALL** | 47 | 0.90 | **0.94** | 0.93 |

## What the numbers say

**On course codes, dense retrieval ranks badly — MRR 0.74 against lexical's 0.94.** Recall@5
hides most of it (0.92 vs 1.00) because the right page usually does appear somewhere in the
top five; the difference is *where*. "CSE 211" and "CSE 213" embed almost identically, so
the dense arm returns a plausible-looking set of routine pages in near-arbitrary order.
Lexical matching treats the code as the exact token it is.

**On prose, the ranking reverses** — dense MRR 0.98 against lexical 0.93. A question like
"who is eligible to sit for an improvement examination" shares few content words with the
notice that answers it and shares many with every other notice.

**Neither arm wins everywhere, which is the argument for fusing them.** Hybrid is the only
configuration that reaches Recall@5 = 1.00 across all three slices, and it sits within
0.02–0.06 MRR of whichever arm is stronger on that slice.

**Honest caveat: hybrid is not dominant on MRR.** Overall MRR is 0.93 for hybrid against
0.94 for lexical alone; on course codes lexical leads 0.94 to 0.92. RRF pays a small
ranking cost for robustness — it sometimes moves the top lexical hit from rank 1 to rank 2.
The trade buys the recall (lexical alone misses a prose question outright) and buys the
cross-lingual path (the lexical arm contributes *nothing* when query and document are in
different scripts), but it is a trade, not a free win.

## The reranking question

These numbers come from the **measured-skip** configuration (PRD §6): no cross-encoder is
in the loop. The gap hybrid gives up on MRR is exactly the gap a reranker is meant to
close, so this table is also the baseline for deciding whether `bge-reranker-v2-m3` and its
~2–3 GB of dependencies earn their place. With Recall@5 already at 1.00, a reranker can
only improve *ordering* on this corpus — worth measuring against the cost, not assuming.

## A note on how the first version of this table was wrong

The first run reported `routine_vision` at 0.83 in every configuration, and this report
originally attributed those two misses to chunking. That was wrong, and the way it was
wrong is worth recording.

Both questions — "where is the venue" and "what are the three daily time slots" — have
answers printed on **all 26 routine pages**, but the gold set named only page 1. Retrieval
returned pages 6, 7 and 13; the scorer counted that as a miss. The failure was in the
annotation, not the retriever, and inspecting the actual retrieved pages is what exposed it.

A gold set is code with no tests. On a corpus with near-duplicate pages, "the source page"
is often a set, and writing down one member of it silently understates every configuration
equally — which is exactly the shape of error an ablation table cannot reveal, because all
three columns move together.

## Not yet measured

Every question here is English, so the cross-lingual columns of Ablation A remain empty and
Ablation B (extraction paths) needs the Bangla corpus. Ablation C should be re-run once the
routine-photo slice exists: the join feature runs one query per confirmed course code,
which is precisely the shape this table says lexical retrieval wins.
