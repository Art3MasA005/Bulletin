# Generation model comparison

Every candidate answered the **same retrieved context** through the
**real answer prompt**. Retrieval ran once per question, so the only
variable is the model.

Measured prompt size: **1813 tokens** average across 5 questions (estimated; Bangla counted at a worse
ratio than Latin, which is honest for this corpus). Cost below assumes
that prompt plus a 300-token answer.

| model | providers | $/M in | $/M out | $/1k questions | passed | bn ok | cites | refuses |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `qwen/qwen3.8-flash` | 1 | 0.150 | 0.470 | $0.41 | 5/5 | 2/2 | 4/4 | 1/1 |
| `deepseek/deepseek-v4-flash` | 16 | 0.087 | 0.174 | $0.21 | 4/5 | 2/2 | 3/4 | 1/1 |
| `google/gemma-4-26b-a4b-it` | 8 | 0.042 | 0.220 | $0.14 | 5/5 | 2/2 | 4/4 | 1/1 |

**passed** — every check for that case. **bn ok** — a Bangla question
answered in Bangla. **cites** — carries [n] markers. **refuses** — declined
the question the corpus cannot answer, instead of inventing one.

`refuses` is the column to read first. A model that scores 4/4 on the
answerable questions and 0/1 here is not a cheaper option, it is a
product that lies about exam dates.

## Answers

### `qwen/qwen3.8-flash`

- **PASS** (2.9s) _When do the final examinations start?_
  > The final examinations start on 05th September 2026 [1].
- **PASS** (37.1s) _What is the exam time for CSE 211?_
  > CSE 211 is at **12:00 pm–01:30 pm** in the Makeup/Improvement/Overlap Midterm schedule [1][3]. In the CSE Regular Final Examination routine, CSE 211 is listed in **Slot 1, 10:00–12:00 PM** [5].
- **PASS** (8.8s) _চূড়ান্ত পরীক্ষা কখন শুরু হবে?_
  > চূড়ান্ত পরীক্ষা ৫ সেপ্টেম্বর ২০২৬ তারিখে শুরু হবে [2]।
- **PASS** (28.8s) _সিএসই বিভাগের পরীক্ষার সময়সূচি কী?_
  > প্রদত্ত তথ্যে সিএসই বিভাগের একাধিক পরীক্ষার সময়সূচি আছে, তাই সংক্ষেপে দেওয়া হলো [1][2][4][5]। - CSE (Regular) Final, Summer 2026: ৫ সেপ্টেম্বর থেকে ১৩ সেপ্টেম্বর ২০২৬ পর্যন্ত দুইটি স্লট—১০:০০–১২:০০ PM ও ০২:৩০–০৪:৩০ PM [1]। - CSE (Diploma-Weekend) Final, Summer 2026: ৭ ও ৯ সেপ্টেম্বর ২০২৬—০৬:০০ PM–
- **PASS** (0.0s) _What are the hostel rules and curfew timings?_
  > Nothing in the published documents covers this. Try rephrasing, or ask the office.

### `deepseek/deepseek-v4-flash`

- **PASS** (1.7s) _When do the final examinations start?_
  > The final examinations start on 5th September 2026 [1].
- **PASS** (23.1s) _What is the exam time for CSE 211?_
  > The exam time for CSE 211 depends on the schedule: - For the Makeup/Improvement/Overlap midterm (Summer 2026, Regular and Weekend), CSE 211 is held in the **12:00 pm - 01:30 pm** slot on **11-Aug-2026** [1], [3]. - For the Final Examination (Summer 2026, Regular), CSE 211 is in **SLOT 1** (10:00 - 1
- **PASS** (5.6s) _চূড়ান্ত পরীক্ষা কখন শুরু হবে?_
  > গ্রিন ইউনিভার্সিটি অব বাংলাদেশের (ল’ বিভাগ ব্যতীত) সামার ২০২৬ সেমিস্টারের চূড়ান্ত পরীক্ষা ৫ই সেপ্টেম্বর ২০২৬ থেকে শুরু হবে [1][2]।
- **FAIL** (11.4s) _সিএসই বিভাগের পরীক্ষার সময়সূচি কী?_
  > গ্রিন ইউনিভার্সিটি অফ বাংলাদেশের সিএসই বিভাগের জন্য নিম্নলিখিত পরীক্ষার সময়সূচি রয়েছে: **১. নিয়মিত (Regular) ফাইনাল পরীক্ষা, স্প্রিং ২০২৬:** ৫ সেপ্টেম্বর থেকে ১৩ সেপ্টেম্বর ২০২৬ পর্যন্ত প্রতিদিন দুটি স্লটে: সকাল ১০:০০ থেকে ১২:০০ এবং বিকাল ২:৩০ থেকে ৪:৩০ [১]। কোর্সগুলোর মধ্যে রয়েছে CSE 101, MAT 1
- **PASS** (0.0s) _What are the hostel rules and curfew timings?_
  > Nothing in the published documents covers this. Try rephrasing, or ask the office.

### `google/gemma-4-26b-a4b-it`

- **PASS** (4.4s) _When do the final examinations start?_
  > The Final Examinations of Summer 2026 for all academic programs (except the Law Department) will be held from 05th September 2026 to 13th September 2026 [1].
- **PASS** (4.2s) _What is the exam time for CSE 211?_
  > Based on the provided documents, the exam time for CSE 211 depends on the examination type: * **Makeup, Improvement and Overlap of Midterm Examinations (Summer 2026 CSE Regular):** The exam for CSE 211-CSE(181): Computer Architecture is scheduled for 11-Aug-2026 from 12:00 pm - 01:30 pm [1]. * **Fin
- **PASS** (5.1s) _চূড়ান্ত পরীক্ষা কখন শুরু হবে?_
  > গ্রিন ইউনিভার্সিটির ২০২৬ সালের সামার (Summer 2026) চূড়ান্ত পরীক্ষা ৫ সেপ্টেম্বর ২০২৬ তারিখে শুরু হবে [2]।
- **PASS** (3.4s) _সিএসই বিভাগের পরীক্ষার সময়সূচি কী?_
  > প্রদত্ত নথিতে সিএসই (CSE) বিভাগের বিভিন্ন পরীক্ষার সময়সূচি দেওয়া হয়েছে: **১. সিএসই (রেগুলার) ফাইনাল পরীক্ষা (সামার ২০২৬):** [1] * **Slot 1:** সকাল ১০:০০ - দুপুর ১২:০০ * **Slot 2:** দুপুর ০২:৩০ - বিকেল ০৪:৩০ **২. সিএসই (ডিপ্লোমা-উইকেন্ড) ফাইনাল পরীক্ষা (সামার ২০২৬):** [2] * **৭ সেপ্টেম্বর ও ৯ সেপ্
- **PASS** (0.0s) _What are the hostel rules and curfew timings?_
  > Nothing in the published documents covers this. Try rephrasing, or ask the office.

