# Data audit: Psilocybin mushrooms, LSD, DMT, 2C-B

Audited 2026-10-25. **Proposed changes only; `data/` untouched.**
Checked: PsychonautWiki (PW) pages read directly (first 100k characters), TripSit combos. **Not yet cross-checked against Erowid or studies.**

Sources: https://psychonautwiki.org/wiki/Psilocybin_mushrooms , /LSD , /DMT , /2C-B

## Doses and durations
| Substance / route | Result |
|---|---|
| Psilocybin oral (mg psilocybin) | thr 2.5, light 2.5-10, common 10-25, strong 25-50, heavy 50+; onset 20-45 m, comeup 1-1.5 h, peak 2-2.5 h, offset 2.5-3.5 h, total 6-8 h, after 4-24 h. **Matches PW.** |
| LSD sublingual (µg) | 15 / 15-75 / 75-150 / 150-300 / 300+; onset 15-30 m, comeup 45-90 m, peak 3-5 h, offset 3-5 h, total 8-12 h, after 12-48 h. **Matches PW.** |
| DMT smoked (mg) | 2 / 10-20 / 20-40 / 40-60 / 60+; onset 20-40 s, comeup 1-3 m, peak 2-8 m, offset 1-6 m, total 5-20 m, after 10-60 m. **Matches PW.** |
| 2C-B oral | 5 / 10-15 / 15-25 / 25-45 / 45+; onset 20-40 m, comeup 60-90 m, peak 60-90 m, offset 2.5-3.5 h, total 5-7 h. **Matches PW.** |
| 2C-B insufflated | 1 / 5-8 / 8-12 / 12-23 / 23+; onset 1-5 m, comeup 15-30 m, peak 60-90 m, offset 2-3 h, total 4-6 h. **Matches PW.** |

## Findings
1. **Psilocybin is entered in mg of psilocybin but people weigh dried mushrooms.** PW also gives a dried *P. cubensis* table: thr 0.25-0.5 g, light 0.5-1, common 1-2.5, strong 2.5-5, heavy 5+ g, with about 10-12 mg psilocybin per g (strongly batch and species dependent). Add a grams entry mode with a wide uncertainty band and a "potency unknown" warning.
2. **Missing routes:** DMT intravenous (PW table exists but intravenous use is unusual; keep out of the UI); 2C-B rectal and intravenous (same). Recommendation: add rectal only if wanted; skip IV deliberately and document why.
3. **Tolerance.**
   - LSD: PW states tachyphylaxis within about 3 h and "5 days of abstinence to completely reverse". Our zero = 5 d. OK. PW has no "half" value; the model's zero/4 rule (half-life 1.25 d) is an invention. Note in the app as an estimate.
   - Psilocybin: half 3 d, zero 7 d. Ours 7.0. OK.
   - DMT: PW says tolerance does not appear to occur and no cross-tolerance. Ours has tolerance_group "psychedelics" for DMT in the sync overrides (`TOLERANCE_GROUP_OVERRIDES`) but `has_tolerance` is false, so no effect, but remove the override for clarity.
   - 2C-B: PW says it does **not** produce cross-tolerance with other serotonergic psychedelics (with an asymmetry: 2C-B after LSD is reduced, LSD after 2C-B is not), and tolerance "is not built almost immediately". Ours pools 2C-B into the shared "psychedelics" track with 7 d zero. That contradicts PW. Proposal: give 2C-B its own track, and optionally add an LSD->2C-B one-way contribution.
4. **Interaction tiers are inconsistent across pages.** PW lists lithium, cannabis, stimulants and tramadol together as "dangerous" for LSD, DMT, 2C-B, psilocybin. Ours stores lithium as dangerous for LSD/DMT/2C-B, but as "unsafe" for psilocybin; tramadol as "unsafe" everywhere; cannabis and stimulants as "uncertain". Proposal: make lithium dangerous everywhere (PW: "strictly avoided"), keep tramadol at unsafe, and keep cannabis/stimulants at uncertain but add PW's "strong and unpredictable synergy" note for cannabis with LSD/DMT/2C-B.
5. **Missing LSD interactions:** SSRIs (reduced effect, redosing risk), antidepressants/antipsychotics (blocked effects), MDMA (unpredictable, possible neurotoxicity). TripSit rates LSD+MDMA and Mushrooms+MDMA as "Low Risk & Synergy", which is more optimistic than PW's wording. Show both, and surface the PW note.
6. **DMT and MAOIs.** PW discusses MAOI use only in route sections. We have no MAOI entry. Add DMT + MAOI as **dangerous when unplanned** (smoked DMT on top of an MAOI changes dose and duration drastically), pending a second source.
7. **Bad summaries.** LSD, DMT, 2C-B summaries are "Summary sheet: X X". Psilocybin's is a wild-mushroom warning. Replace with proper descriptions.
8. **Wild mushroom warning** is worth keeping as a separate safety note.
