# Cross-lingual embedding check

Model: `baai/bge-m3`  ·  pairs: 20

- **Top-1 accuracy: 100%** (floor 70%)
- Mean matched cosine: 0.8809
- Mean mismatched cosine: 0.4950
- **Margin: +0.3859** (floor +0.0500)

## Verdict: PASS

Strategy A (shared embedding space) is viable with this model.
Strategy B (query translation) remains worth measuring in Ablation A --
PRD 7.2 predicts B wins on noisy legacy-font and vision-read chunks.

## Per pair

| English | cosine | rank | top-1 |
|---|---|---|---|
| When do the final examinations start? | 0.9063 | 1 | yes |
| The exam routine is published on the notice board. | 0.8097 | 1 | yes |
| Students must carry their admit card. | 0.8638 | 1 | yes |
| How do I apply for a scholarship? | 0.8627 | 1 | yes |
| The tuition fee must be paid before registration. | 0.9126 | 1 | yes |
| What are the hostel rules? | 0.7489 | 1 | yes |
| Hostel residents must return before ten at night. | 0.8565 | 1 | yes |
| The library remains closed on public holidays. | 0.8534 | 1 | yes |
| Application for leave must be submitted in writing. | 0.8996 | 1 | yes |
| The semester begins in the first week of January. | 0.8877 | 1 | yes |
| Late registration carries an additional fee. | 0.9061 | 1 | yes |
| Results will be published in February. | 0.9337 | 1 | yes |
| A minimum attendance of seventy percent is required. | 0.8923 | 1 | yes |
| The department office opens at nine in the morning. | 0.8972 | 1 | yes |
| Students may appeal against a published result. | 0.9143 | 1 | yes |
| Identity cards must be renewed every academic year. | 0.8786 | 1 | yes |
| The university will remain closed during Eid. | 0.9067 | 1 | yes |
| Course registration closes on the thirtieth of De... | 0.8771 | 1 | yes |
| Medical certificates must be submitted within sev... | 0.8758 | 1 | yes |
| Financial aid is available for eligible students. | 0.9349 | 1 | yes |
