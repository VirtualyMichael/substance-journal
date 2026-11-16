# LSD tolerance and mushroom potency (2026-11-15)

Sources were read (full text where open, otherwise the abstract or a review that tabulates the primary data); anything only reached through a review says so.
Values live in `substance_journal/core/reference_overrides.py` (`TOLERANCE_PROFILES`, applied with `--overrides-only`), `app/packages/sj_core/lib/src/mushroom_potency.dart`
and `app/assets/data/mushroom_strains.json` / `potency_testing.json`.

## What was wrong for LSD
The generic model put LSD's whole tolerance at the moment of dosing (score 1.15 for 100 ug, "Moderate"), let it halve every 1.25 days from there, and pooled it
with mushrooms using a dose-weighted half-life (mushrooms 3 days, so a mixed track decayed more slowly: baseline about 11 days after an LSD-then-mushroom pair).
The human data say the opposite shape: little tolerance for the first hours, the largest about a day later, gone in 3 to 6 days.

| Scenario (100 ug) | Before (score, word) | After (estimated loss of effect, band) |
|---|---|---|
| Right after the dose | 1.15 Moderate | 0% (0-0) |
| 6 h | 1.01 Moderate | 0% (0-7) |
| Repeat 1 day later | 0.66 Moderate | 52% (52-52) |
| Repeat 2 days later | 0.38 Low | 39% (26-42) |
| Repeat 3 days later | 0.22 Low | 26% (0-31) |
| Repeat 5 days later | 0.07 None | 0% (0-10) |
| Repeat 7 or 14 days later | 0.02 / 0.00 None | 0% |
| Daily for 4 days, before a 5th | 1.01 Moderate (falling) | 81% (64-85) |
| LSD, 2 g mushrooms 2 days later, +1 day | 1.20 Moderate | 64% (52-67) |

## Profile values
| Field | Value | Source |
|---|---|---|
| Tolerance starts | after 6 h (3 h at the high end) | Balestrieri & Fontanari 1959 (two 200 ug doses 6 h apart gave nearly the same response, n=2); Freedman 1984 (3 h); both via Buchborn 2016 |
| Largest | 24 h after a dose | Buchborn 2016: mental tolerance "substantially manifests 24h after a one-time administration" |
| One dose | 52% less effect | Isbell 1956: questionnaire responses down 52% by day 2 of daily dosing (mean 138 ug), via Buchborn 2016. No error range published |
| Most measured | 88% | Isbell 1956: about 78% on average across regimens, 88% on the physician's rating |
| Gone after | 5 days (3-6) | Isbell 1956 (3 days off enough after 14 and 84 days of daily use); Cholden 1955, Hoffer & Osmond 1967 (3-6 days); Buchborn 2016 (5 days to reverse completely) |
| Dose size | square root below a common dose, no extra above (band: proportional to none) | **App assumption**: no human dose-response for tolerance was found |
| Cross-tolerance | psilocybin mushrooms, psilocin, mescaline counted fully | Isbell 1961 (LSD and psilocybin both ways), Wolbach 1962 (LSD and mescaline both ways). Strength **assumed** full; no single percentage published |
| Mushrooms | LSD's time course, gone after 5 days (3-7) | No psilocybin time course was found; 7 days is PsychonautWiki's figure. Isbell 1961 found direct tolerance to psilocybin weaker than to LSD |

Gresch 2005 (rats: behavioural tolerance with reduced cortical 5-HT2A signalling) is cited for mechanism only. No 2023-2025 controlled human study of repeated
LSD or psilocybin at short intervals was found (modern trials space doses weeks apart).

## LSD timeline
Onset changed from 15-30 to 24-72 min: Dolder 2017 (PMC5591798) reports onset 0.8 +/- 0.4 h and peak 2.8 +/- 0.8 h after 100 ug oral, duration 8.2 +/- 2.1 h
(200 ug: onset 0.4 +/- 0.3 h, duration about 11 h). Holze 2021 (PMC8027607): 25-200 ug, effects 6.7 to 11 h, ceiling for good effects at 100 ug. Both used an
oral solution; no controlled sublingual data were found. Dose bands (15-75 light, 75-150 common, 150-300 strong, 300+ heavy) are consistent with Holze 2021
(effects from 25 ug, ceiling near 100 ug, more anxiety at 200 ug) and were not changed. The 12-48 h afterglow has no study behind it and was left as published.

## Mushroom calculator constants
- Molar masses: psilocybin 284.25, psilocin 204.27 g/mol (PubChem CID 10624, 4980); factor 1.3916.
- Default potency 1% (the app's existing 10 mg/g); unknown-batch range 0.19% (Rodriguez 2025, "Libelula" user sample) to 2.8% (Galdino 2025, psilocybin 2.57% + psilocin 0.16%).
  Foster 2026 (J AOAC Int) reports 1.14 +/- 0.17% for a standardised grow; Goff 2024 0.88-1.36% for five strains.
- Within-batch spread: coefficient of variation 12.8-23.4% between single fruiting bodies (Sharchaton 2026, J Fungi 12:486); the app uses 23.4% for lab results.
- Caps vs stems: 1.03 vs 0.52 wt% (Gotvaldova 2021), not statistically significant; used only to widen the range.
- Water: fresh culinary mushrooms 88.3-92.45 g/100 g, dried shiitake 9.5 g/100 g (USDA FoodData Central 169382, 169251, 168436). No P. cubensis figure found.
- Storage: Gotvaldova 2021 (dried, dark, room temperature best; fresh frozen worst), Foster 2026 (capsules stable 11 months). No loss rate found; the loss slider is the user's guess.
- Tea and lemon tek extraction: no published measurement found; the calculator assumes full transfer and says so.

## Strains
Numbers only where an analysis was published: Goff 2024 (Creeper, Blue Meanie, B+, Texas Yellow, Thai; psilocybin/psilocin split from the table in Kurzbaum 2025),
Sharchaton 2026 (14 strains incl. Penis Envy, Albino Penis Envy, Jack Frost x Golden Teacher), Rodriguez 2025 (single user-provided samples incl. one Golden
Teacher at 0.25% + 0.05%, B+, Thai Pink Buffalo, Cambodian, Libelula). Golden Teacher's only straight analysis is that one old sample; the app says so.
Not verified: the Beug & Bigwood 1982 Pacific Northwest figures beyond their abstracts (0.1 to nearly 2% across species; about fourfold between flushes).

## Testing services (checked 2026-11-15)
Listed: ACS Laboratory (FAQ: psilocybin testing for DEA-licensed clients only), miraculix Psilocybin QTest, Bunk Police Psilocybin QTest Kit, Oregon's ORELAP
accredited psilocybin labs (list of 16 Dec 2024: Rose City Laboratories). Checked but not listed (mushroom potency not confirmed): Energy Control International,
DrugsData (not accepting samples), Substance (Victoria BC), checkit! Vienna. Not checked: Know Your Stuff, The Loop, DanceSafe, Canadian or Colorado licensed labs.
