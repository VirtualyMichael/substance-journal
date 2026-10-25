# Reference data audit: summary (2026-10-25)

**Status: data fixes applied (uncommitted).** All corrections live in `substance_journal/core/reference_overrides.py` (each substance lists what changed under `overrides`, with `sources` and `safety_notes`), applied by `scripts/sync_substance_data.py` and re-appliable offline with `--overrides-only`. Tests: `tests/test_reference_data.py`. Not done (belongs to later phases): cannabis absorbed-dose model, nicotine product presets, psilocybin grams entry, per-dose LSD duration, nonlinear MDMA curve, nicotine interaction data, optional ketamine/DMT/2C-B extra routes.

The rest of this document is the original proposal text.

Per-substance detail: [cannabis](cannabis.md) , [alcohol and nicotine](alcohol-nicotine.md) , [psilocybin, LSD, DMT, 2C-B](psychedelics.md) , [MDMA and ketamine](mdma-ketamine.md).

## How far the checking went
| Source | Coverage |
|---|---|
| PsychonautWiki pages | Read directly for all 9 substances (first 100k characters of each page; dosage, duration, tolerance, interaction sections). |
| TripSit combos | Full file compared with `data/interactions.json`: all 28 pairs identical. |
| Erowid | Search summaries only, for cannabis and psilocybin. Not read page by page for the others. |
| Studies | Search summaries only: THC bioavailability (McGilveray 2005), MDMA nonlinear PK (de la Torre 2000), ketamine bioavailability (Chue 2023 review), nicotine pouch PK. |

Treat this as a solid first pass, not a finished verification. Erowid dose charts and the primary papers still need a full read for LSD, DMT, 2C-B, MDMA, alcohol and nicotine.

## Headline result
**The numbers in the app are faithful copies of PsychonautWiki.** Every dose band and duration range I checked matches. The problems are in what surrounds the numbers.

## Confirmed errors (fix)
1. **Ketamine tolerance is wrong.** The override sets zero tolerance at 14 days, but PW says 14 days is *half* and baseline is 28 days. (`TOLERANCE_ZERO_DAYS_OVERRIDES` in `scripts/sync_substance_data.py`.)
2. **The tolerance model decays too fast.** `core/tolerance.py` sets half-life = zero-tolerance days / 4, but PW publishes real half values: alcohol 3-7 d (model gives 2.6 d), cannabis 1-2 wk (model 4.4 d), MDMA 1 mo (model 18.8 d), ketamine 14 d (model 3.5 d after the fix above). Use PW's half value when present.
3. **2C-B is pooled with all psychedelics** though PW says it has no cross-tolerance with other serotonergic psychedelics (one-way asymmetry with LSD). DMT also carries a leftover group override although it has no tolerance.
4. **Junk summaries** for 6 of 9 substances ("Summary sheet: LSD LSD", a carcinogen paragraph for nicotine, a wild-mushroom warning for psilocybin) and a blank cannabis category.
5. **Lithium tier is inconsistent**: dangerous for LSD/DMT/2C-B/cannabis, only "unsafe" for psilocybin. PW says strictly avoid for all.

## Unit and meaning problems (design issues)
- **Cannabis**: PW mg is mg of THC reaching you; the app's calculator stores mg of THC in the flower, 5-10x larger. Needs product mg, absorption factor and "share smoked". See cannabis.md.
- **Nicotine**: unit basis undefined on PW (cigarette content 10-12 mg vs delivered about 1-2 mg; Marlboro Gold lists 0.8 mg/cigarette in a PK trial, comparable to a 10 mg pouch in plasma exposure). Needs product presets.
- **Psilocybin**: users weigh dried mushrooms. PW says about 10-12 mg psilocybin per g; Erowid says about 0.63% psilocybin + 0.60% psilocin in wild cubensis and up to 10x batch variation. Grams entry needs a wide uncertainty band.
- **Alcohol**: PW standard drink = 10 g ethanol; Alcohol Tracker uses US 14 g. Must be an explicit setting.

## Where sources disagree (needs your call)
| Item | PW (ours) | Other | Conservative pick |
|---|---|---|---|
| Psilocybin mg, heavy | 50+ | Erowid heavy 35+, common 6-20, strong 20-40, threshold 3-4 | Show Erowid's lower heavy line as a note |
| Cannabis oral strong | 10-25 mg | Erowid strong stoning 4-15 mg (no tolerance) | Advise new users to start at 2.5 mg |
| Cannabis oral onset / total | 20-60 m / 4-10 h | Erowid 20-120 m / 3-9 h, Grotenhermen 30-90 min | Widen onset max to 120 min |
| Ketamine bioavailability | 45% intranasal, 17% oral, 20-29% SL | Review: intranasal 30-50%, oral 7-25%, SL 20-30%, IM 93-95% | Consistent, keep PW with ranges |
| MDMA | linear dose bands | de la Torre 2000: blood levels rise more than proportionally with dose | Do not extrapolate the curve linearly above 125 mg; add a note |

## Interaction coverage gaps
- **TripSit pairs match exactly**, but TripSit rates LSD/mushrooms/DMT/2C-B/ketamine + MDMA as "Low Risk & Synergy" while PW says unpredictable with possible neurotoxicity. Show both.
- **Nicotine has no interaction data at all.**
- **DMT + MAOI** is missing (dangerous if unplanned).
- Proposed raises: MDMA + protease inhibitors and + GHB/GBL to unsafe; ketamine + benzodiazepines and oral ketamine + grapefruit to unsafe; add LSD + SSRIs/antipsychotics note; cannabis + psychedelics note ("strong, volatile synergy").

## Missing routes (decide whether to add)
Cannabis sublingual; DMT intravenous; 2C-B rectal and intravenous; ketamine sublingual/rectal/IM (PW has no dose tables). Recommendation: add cannabis sublingual only; leave the rest out on purpose and say why.

## Proposed data changes (once you approve)
1. `scripts/sync_substance_data.py`: fix ketamine zero to 28 d; add `tolerance_half_days` field parsed from PW; remove DMT group override; give 2C-B its own track; add summaries, cannabis category, sublingual cannabis route, widened oral cannabis ranges, extra interactions and per-value `sources`.
2. `core/tolerance.py`: use `tolerance_half_days` when present.
3. New `tests/test_reference_data.py` (min <= max, thresholds ascending, no placeholder summaries, lithium tier consistent, half <= zero).
4. App: show "Sources and confidence" and the "dose is absorbed, not product" labels.

## Second pass (done): see [second-pass.md](second-pass.md)
Erowid dose pages were read in full (browser) for MDMA, LSD, DMT, 2C-B, ketamine and nicotine, and the PsychonautWiki API tiers were checked. New findings:
- Our interaction tiers equal PsychonautWiki's API exactly, so tier differences between substances are PW's own.
- **Ketamine oral timing**: PW offset 3-6 h vs Erowid duration 90 min. **Nicotine smoked**: PW total 1-3 h vs Erowid 10-30 min active. Both need your decision.
- Dose bands: PW is equal to or more conservative than Erowid for MDMA, LSD, DMT and 2C-B; Erowid is more conservative for ketamine insufflated "heavy" (100 mg vs 150 mg) and for psilocybin heavy.
- Studies back the PW values: LSD duration scales with dose (8.2 h at 100 µg, 11.6 h at 200 µg), nicotine absorbed per cigarette about 1-2.3 mg, MDMA exposure is nonlinear.

## Still not verified
- Erowid alcohol (no dose page exists) and Erowid effects/FAQ pages.
- Watson 1980 and Jones 2010 (cited via secondary pages only).
- Full MDMA PK values; psilocin PK at 15-20 mg.
