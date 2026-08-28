# Generation model comparison

Every candidate answered the **same retrieved context** through the
**real answer prompt**. Retrieval ran once per question, so the only
variable is the model.

Measured prompt size: **1813 tokens** average across 5 questions (estimated; Bangla counted at a worse
ratio than Latin, which is honest for this corpus). Cost below assumes
that prompt plus a 300-token answer.

| model | providers | $/M in | $/M out | $/1k questions | passed | bn ok | cites | refuses |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `google/gemma-4-31b-it` | 13 | 0.080 | 0.340 | $0.25 | 3/5 | 2/2 | 3/4 | 1/1 |
| `google/gemma-4-26b-a4b-it` | 8 | 0.042 | 0.220 | $0.14 | 4/5 | 2/2 | 3/4 | 1/1 |

**passed** — every check for that case. **bn ok** — a Bangla question
answered in Bangla. **cites** — carries [n] markers. **refuses** — declined
the question the corpus cannot answer, instead of inventing one.

`refuses` is the column to read first. A model that scores 4/4 on the
answerable questions and 0/1 here is not a cheaper option, it is a
product that lies about exam dates.

## Answers

### `google/gemma-4-31b-it`

- **PASS** (2.2s) _When do the final examinations start?_
  > The Final Examinations of Summer 2026 start on 05th September 2026 [1].
- **PASS** (1.9s) _What is the exam time for CSE 211?_
  > Based on the provided documents, the exam time for CSE 211 varies by schedule: * **Makeup, Improvement and Overlap (Regular):** 12:00 pm - 01:30 pm on 11-Aug-2026 [1]. * **Makeup, Improvement and Overlap (Weekend):** 12:00 pm - 01:30 pm on 11-Aug-2026 [3], [4]. * **FINAL Examination (Regular):** 10:
- **FAIL** (2.9s) _চূড়ান্ত পরীক্ষা কখন শুরু হবে?_
  > চূড়ান্ত পরীক্ষা ৫ সেপ্টেম্বর ২০২৬ থেকে শুরু হবে [১], [২]।
- **FAIL** (23.7s) _সিএসই বিভাগের পরীক্ষার সময়সূচি কী?_
  > সিএসই বিভাগের বিভিন্ন পরীক্ষার সময়সূচি নিচে দেওয়া হলো: **১. সিএসই (রেগুলার) ফাইনাল পরীক্ষা (সামার ২০২৬):** * **৫ সেপ্টেম্বর ২০২৬:** স্লট ১ (১০:০০ - ১২:০০) ডিসক্রিট ম্যাথমেটিক্স; স্লট ২ (০২:৩০ - ০৪:৩০) স্ট্রাকচার্ড প্রোগ্রামিং [1]। * **৬ সেপ্টেম্বর ২০২৬:** স্লট ১ (১০:০০ - ১২:০০) - কোনো কোর্স উল্লেখ
- **PASS** (0.0s) _What are the hostel rules and curfew timings?_
  > Nothing in the published documents covers this. Try rephrasing, or ask the office.

### `google/gemma-4-26b-a4b-it`

- **PASS** (7.2s) _When do the final examinations start?_
  > The Final Examinations of Summer 2026 for all academic programs (except Law Department) will be held from 05th September 2026 to 13th September, 2026 [1].
- **PASS** (6.9s) _What is the exam time for CSE 211?_
  > The exam time for CSE 211 depends on the type of examination: * **Makeup, Improvement and Overlap of Midterm Examinations (CSE Regular):** The time is not explicitly stated for a specific date, but the schedule provides time slots of 10:00 am - 11:30 am, 12:00 pm - 01:30 pm, and 02:30 pm - 04:00 pm 
- **FAIL** (3.5s) _চূড়ান্ত পরীক্ষা কখন শুরু হবে?_
  > গ্রিন ইউনিভার্সিটি অব বাংলাদেশ-এর ২০২৬ সালের সামার সেমিস্টারের চূড়ান্ত পরীক্ষা ৫ সেপ্টেম্বর ২০২৬ থেকে ১৩ সেপ্টেম্বর ২০২৬ পর্যন্ত অনুষ্ঠিত হবে [২]।
- **PASS** (2.6s) _সিএসই বিভাগের পরীক্ষার সময়সূচি কী?_
  > সিএসই বিভাগের পরীক্ষার সময়সূচি বিভিন্ন ধরণের পরীক্ষার জন্য ভিন্ন ভিন্ন: * **CSE (Regular) Final Examination (Summer 2026):** পরীক্ষার স্লট অনুযায়ী সময় ১০:০০ - ১২:০০ PM এবং ০২:৩০ - ০৪:৩০ PM [1]। * **CSE (Diploma-Weekend) Final Examination (Summer 2026):** সোমবার এবং বুধবার পরীক্ষার সময় সন্ধ্যা ০৬
- **PASS** (0.0s) _What are the hostel rules and curfew timings?_
  > Nothing in the published documents covers this. Try rephrasing, or ask the office.

