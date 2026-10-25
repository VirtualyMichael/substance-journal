# Data audit: MDMA and Ketamine

Audited 2026-10-25. **Proposed changes only; `data/` untouched.**
Checked: PsychonautWiki (PW) pages read directly (first 100k characters), TripSit combos. **Not yet cross-checked against Erowid or studies.**

Sources: https://psychonautwiki.org/wiki/MDMA , https://psychonautwiki.org/wiki/Ketamine

## MDMA (oral, mg)
| Field | Ours | PW | Verdict |
|---|---|---|---|
| doses | 20 / 20-80 / 80-120 / 120-150 / 150+ | same | OK |
| durations | onset 30-45 m, comeup 15-30 m, peak 1.5-2.5 h, offset 1-1.5 h, total 3-6 h, after 12-48 h | same | OK |
| tolerance | half 1 mo, zero 2.5 mo (75 d) | "about 1 month to half and 2.5 months to baseline" | OK |
| cross-tolerance | group "dopaminergic" | "all dopaminergic and serotonergic stimulants" | partly OK; document the serotonergic part |

Findings:
1. **Missing guidance.** PW gives 1.1-1.7 mg/kg (80-120 mg for 70 kg), a "body kg + 50 mg" rule, a 1-3 month interval between uses, and warns against redosing. Add per-kg hints and an "interval since last MDMA" warning to the app.
2. **Hyperthermia, hyponatremia, serotonin syndrome.** Add them as safety notes (PW: avoid more than 3 L of water in a few hours; hyponatremia is an important cause of death).
3. **Non-linear pharmacokinetics.** PW lists oral bioavailability 37-68%. MDMA blood levels rise more than proportionally with dose, so the "dose factor" in `effect_curve.py` (linear in amount) understates heavy doses. Needs a study check (de la Torre 2000) before changing the curve.
4. **Interactions.** Ours: dangerous = Tramadol, MAOIs, DXM; unsafe = 25x-NBOMe, PCP, serotonin releasers, 2C-T-x, 5-HTP. Consistent with PW. PW also lists protease inhibitors (ritonavir slows clearance, stronger and longer), SSRIs/SNRIs, GHB/GBL, DOx, 5-MeO-xxT; all present, as "uncertain". Proposal: raise **protease inhibitors** and **GHB/GBL** to at least "unsafe" (PW: slowed processing and sudden unconsciousness risk).
5. **TripSit shows MDMA + alcohol = Caution, MDMA + LSD/mushrooms/ketamine/2C-B/DMT = Low Risk & Synergy.** Matches the dataset, but see the optimism concern on LSD/mushrooms.
6. Summary is "Summary sheet: MDMA MDMA". Replace.

## Ketamine
| Field | Ours | PW | Verdict |
|---|---|---|---|
| insufflated doses | 5 / 10-30 / 30-75 / 75-150 / 150+ | same | OK |
| oral doses | 50 / 50-100 / 100-300 / 300-450 / 450+ | same | OK |
| insufflated durations | onset 1-3 m, comeup 5-15 m, peak 15-45 m, offset 30-60 m, total 1-2 h, after 2-12 h | same | OK |
| oral durations | onset 10-30 m, comeup 5-20 m, peak 45-90 m, offset 3-6 h, after 4-8 h | same, no "total" listed by PW | OK. Total can be derived (about 3-6 h) |
| **tolerance** | zero = 14 d (manual override) | **half 14 d, baseline 28 d** | **WRONG. Override understates by 2x. Set 28.** |

Findings:
1. **Tolerance override is wrong.** `TOLERANCE_ZERO_DAYS_OVERRIDES["ketamine"] = 14.0` is PW's *half* value. Zero should be 28 d. PW also documents permatolerance with chronic use, which the model ignores.
2. **Missing bioavailability:** PW lists intranasal 45%, oral 17%, rectal 25%, sublingual 20-29%. Store them; the oral dose bands already compensate, so do not double-count.
3. **Grapefruit** roughly doubles oral exposure. Present as uncertain; consider "unsafe" for oral.
4. **Benzodiazepines:** PW says both potentiate ataxia and sedation with unexpected unconsciousness at high doses. Ours has "uncertain". Raise to "unsafe" (TripSit not checked per pair beyond the 8x8).
5. **Bladder/liver damage.** PW notes severe bladder and liver injury; add a chronic-use warning (frequency tracking could flag e.g. more than 2 days per week).
6. **Missing routes:** sublingual (PW lists duration heading but no values) and rectal, IM. Leave out until sourced.
7. Summary is "Summary sheet: Ketamine Ketamine". Replace.
