# Data audit: Alcohol and Nicotine

Audited 2026-10-25. **Proposed changes only; `data/` untouched.**
Checked: PsychonautWiki (PW) pages read directly (first 100k characters), TripSit combo dataset (full). Erowid and studies: only a thin search for alcohol elimination; **not yet cross-checked** (see SUMMARY.md follow-ups).

Sources: https://psychonautwiki.org/wiki/Alcohol , https://psychonautwiki.org/wiki/Nicotine , https://github.com/TripSit/drugs

## Alcohol (oral, g of ethanol)
| Field | Ours | PW | Verdict |
|---|---|---|---|
| threshold / light / common / strong / heavy | 10 / 10-20 / 20-30 / 30-40 / 40+ | same | OK |
| onset, comeup, peak, offset, total, after effects | 2-5 m, 15-45 m, 30-90 m, 45-120 m, 1.5-5 h, 6-48 h | same | OK |
| tolerance half / zero | 3-7 d / 1-2 wk (10.5 d) | same | OK values, but see tolerance model finding in SUMMARY |
| interactions | depressants, dissociatives, benzos, DXM, GHB/GBL, ketamine, MXE, opioids, tramadol = dangerous | same set | OK |

Findings:
1. **Standard drink mismatch.** PW defines a standard drink as 10 g ethanol. Alcohol Tracker uses the US 14 g (0.6 fl oz). The merged app must pick one and label it everywhere (recommend a user setting, default US 14 g, with PW's g-based bands shown in grams). 20-30 g common is about 1.4-2.1 US drinks.
2. **Interactions with weak tiers.** PW describes Nitrous and SSRIs with sedation/blackout/impaired-judgement language but ours has them as "uncertain". Add a note rather than re-tier, because Bifrost's tier labels were not visible in the page text. Needs a Bifrost query to confirm.
3. **Missing from our data (PW "unsafe" extras):** disulfiram-like antibiotics (ALDH2 inhibitors) and hepatotoxic drugs are present; add antibiotic/modified-release dose-dumping notes.
4. **Elimination rate.** Average about 0.015 %BAC per hour (range 0.010-0.020), from consumer sites plus one PubMed breath-alcohol study (https://pubmed.ncbi.nlm.nih.gov/17064864/). This supports Alcohol Tracker's zero-order model. Primary sources (Jones 2010 review, Watson 1980) still to be cited.

## Nicotine (mg)
| Route | Ours vs PW | Verdict |
|---|---|---|
| smoked | 0.2 / 0.3-0.8 / 0.8-1.5 / 1.5-3.5 / 3.5+ ; onset 5-20 s ... total 1-3 h | matches |
| oral | 0.2 / 1-3 / 3-5 / 5-7 / 7+ ; total 5-7 h | matches |
| buccal | 0.2 / 0.5-2 / 2-4 / 4-6 / 6+ ; total 45-90 min | matches |
| tolerance | half 3-7 d, zero 1-2 wk (10.5 d) | matches, but PW also says receptors may need several months to normalise |
| interactions | none stored | TripSit has no nicotine entry; PW page text has no list |

Findings:
1. **Dose basis undefined.** PW does not say if mg is absorbed or product mg. A cigarette contains about 10-12 mg but delivers about 1-2 mg; pouches are 4-14 mg/g product. The app needs a product-to-absorbed conversion like cannabis, and the entry UI needs product presets (cigarette, vape ml at mg/ml, pouch, gum, lozenge).
2. **Bad summary.** Stored summary is a long NNN carcinogen paragraph, not a description. Replace.
3. **Category "Depressant, Stimulants"** is a literal copy of PW's class tags. Keep "Stimulant" as the main category.
4. **No interaction data.** Add a hand-written minimum set from PW (stimulants additive cardiovascular load, cannabis, alcohol) marked "low confidence/manual".
5. **Cross-tolerance.** PW says none with other dopaminergic stimulants; our tolerance_group is None. Correct.
