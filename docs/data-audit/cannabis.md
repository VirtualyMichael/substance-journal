# Data audit: Cannabis (pilot)

Audited 2026-10-25. Status: **proposed changes only, nothing in `data/` has been edited.**
Limits: PsychonautWiki was read in full for dosage, duration, tolerance and interactions (first 100k of 135k characters). Erowid and the studies were read through search summaries, not the full pages, so those rows are marked "secondary".

## Sources
- PsychonautWiki: https://psychonautwiki.org/wiki/Cannabis
- Erowid dose: https://www.erowid.org/plants/cannabis/cannabis_dose.shtml
- Erowid effects: https://erowid.org/plants/cannabis/cannabis_effects.shtml
- Grotenhermen PK review (via Erowid refs): https://erowid.org/references/refs_view.php?ID=6617
- McGilveray 2005, Pain Res Manag (inhaled about 30%, oral 4-12%): https://doaj.org/article/cd19194d483a4b9ab4f9b7558d6dde3a
- THC pharmacokinetics (French review, 2008): https://pubmed.ncbi.nlm.nih.gov/18847571/
- Vanderbilt poison control summary (inhaled 10-35%): https://www.vumc.org/poison-control/node/780

## Dose ranges (mg THC)
| Route | Field | Ours | PsychonautWiki | Verdict |
|---|---|---|---|---|
| smoked | threshold | 0.4 | 0.4 | OK |
| smoked | light / common / strong / heavy | 0.4-2 / 2-4 / 4-10 / 10+ | same | OK |
| oral | threshold | 1 | 1 | OK |
| oral | light / common / strong / heavy | 2.5-5 / 5-10 / 10-25 / 25+ | same | OK |

Erowid oral: light 2-4 mg, strong 4-15 mg for a non-tolerant user. This is lower than PW's strong band, so keep PW's bands but add a "new users: start at 2.5 mg" note (conservative rule).

## Durations
| Route | Phase | Ours | PsychonautWiki | Erowid / studies | Verdict |
|---|---|---|---|---|---|
| smoked | onset | 0.1-10 min | 0.1-10 min | 20-90 s | OK |
| smoked | comeup / peak | 5-10 min / 15-45 min | same | peak 15-30 min (Grotenhermen) | OK |
| smoked | offset / total | 3-4 h / 2.5-5 h | same | 2-4 h | OK |
| oral | onset / comeup | 20-60 min / 30-60 min | same | onset 20-120 min | Widen onset max to 120 min (stomach contents; Erowid, Grotenhermen 30-90) |
| oral | peak / offset / total | 1-2 h / 4-6 h / 4-10 h | same | peak 2-3 h; total 3-9 h | Peak 1-3 h is better supported |
| oral | afterglow | 6-12 h | 6-12 h | 12+ h (Erowid) | OK, flag Erowid |

## Tolerance
Half 1-2 weeks, zero 2-3 weeks (PW). Ours: `tolerance_zero_days` = 17.5, `tolerance_group` = cannabinoids. Consistent. Note PW says THC is detectable up to 77 days in heavy users; that is detection time, not tolerance, so do not use it.

## Interactions
Ours lists Lithium as dangerous and 12 others as uncertain. PW lists the same 13 under dangerous/uncertain, with lithium as "strictly avoid". Consistent. TripSit not yet compared (needs the combo dataset diff).

## Defects found
1. **Missing sublingual route.** PW has duration data (onset 1-10 min, comeup 15-30 min, peak 30-60 min, offset 4-6 h, total 3-7 h) but no dose table. The sync script does not request it, so tinctures cannot be logged accurately.
2. **Empty category and bad summary.** `category` is blank and `summary` is "Summary sheet: Cannabis Cannabis". Replace with a real description.
3. **Unit semantics.** PW doses are mg of THC delivered to the user and described as "user-gathered, verify with other sources". The calculator stores mg of THC in the flower, which is typically 5-10x larger than the absorbed dose. A 1g joint at 20% is 200 mg in the flower, which with 25-30% absorption is 50-60 mg, far above the 10 mg "heavy" line, even though one person rarely smokes a whole joint (sharing, sidestream smoke, butt loss). The model needs `product_mg`, `bioavailability` and a "share of the joint you smoked" field.
4. **Bioavailability defaults to adopt** (editable in UI): inhaled 10-35% with 25-30% as the central estimate; oral 4-20% (central about 10%); sublingual about 10-35% (low quality source, mark low confidence); vaporised 30-60% (low quality, mark low confidence).

## Proposed edits
- `scripts/sync_substance_data.py`: add `sublingual` to cannabis routes; add overrides for category, summary, oral onset max 120 min, oral peak 1-3 h; add `sources` field.
- Keep dose bands as they are.
- Add `core/cannabis.py` constants for bioavailability with citations.

## Implementation (app/packages/sj_core/lib/src/cannabis.dart)
> **Superseded in part:** the bioavailability figures and curve parameters below were revised after review. Current values: inhaled 8 / 18 / 30%, vaporised 10 / 22 / 40%, oral 4 / 10 / 20%, sublingual 5 / 12 / 25%; inhaled curve peak about 27 min, sublingual about 85 min. See `cannabis-model-review.md`.

- **Units used against PsychonautWiki's bands:** smoked, vaped and dabbed doses are compared as mg of THC *absorbed* (product mg x bioavailability). Oral doses are compared as the swallowed label mg, which is how edibles are sold. Sublingual has no published bands, so it is not classified.
- **Bioavailability (low / central / high):** inhaled 10 / 25 / 35% (moderate confidence); vaporised or dabbed 30 / 45 / 60% (low confidence, one weak source); oral 4 / 10 / 20% (moderate); sublingual 10 / 25 / 35% (low). Each carries its source string in the code.
- **Dose class is a range.** Because absorption varies several-fold the app reports the class at the low and high estimate ("light to strong") instead of one false-precise label. A whole 1 g joint at 20% is "heavy" at both ends; a 0.1 g bowl at 15% is "light" to "strong".
- **Known tension:** Erowid calls 0.3 g of medium-potency flower a *strong* smoked dose. At 15% that is 45 mg THC, about 11 mg absorbed at the central 25% estimate, which PsychonautWiki would call *heavy*. The bands and the bioavailability literature do not line up neatly, which is another reason to show ranges. Sharing a joint, sidestream smoke and unfinished joints are handled by the `fractionUsed` input.
- **Curves:** one-compartment curves with first-order absorption (peak normalised to 1, height from the dose factor). Inhaled: absorption half-life 6 min, effect half-life 60 min, peak about 22 min, under 10% of peak after 4 h. Oral: 20 min lag, absorption half-life 45 min, effect half-life 120 min, peak about 2 h, still above 20% of peak at 6 h. Sublingual: 5 min lag, 15 and 100 min. These are shape choices fitted to the published peak times and durations, not fitted to measured plasma data.
