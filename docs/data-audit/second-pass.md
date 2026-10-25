# Second pass: Erowid dose pages, primary studies, PsychonautWiki API tiers (2026-10-25)

Nothing in `data/` has been changed. Erowid blocks plain fetches (HTTP 403), so the pages below were read in the built-in browser, the full dose pages for MDMA, LSD, DMT, 2C-B, ketamine and nicotine. Erowid has no alcohol dose page (404). Cannabis and psilocybin Erowid data come from search summaries (first pass).

## 1. PsychonautWiki API tiers match our stored data
Queried `api.psychonautwiki.org` for the dangerous / unsafe / uncertain lists. For alcohol, LSD, DMT, MDMA, 2C-B and cannabis (danger), the API lists are **identical** to `data/substances.json`. So our tier differences between substances (for example lithium "dangerous" for LSD but "unsafe" for psilocybin) come from PsychonautWiki itself, not from a sync bug. Any change there is a deliberate override and must be labelled as ours. Nicotine and psilocybin queries returned nothing usable.

## 2. Erowid vs PsychonautWiki (ours)
| Substance, route | Field | Ours (PW) | Erowid | Verdict |
|---|---|---|---|---|
| MDMA oral | threshold / light | 20 / 20-80 | 30 / 40-75 | Close |
| | common | 80-120 | 75-125 (small 60-90, large 110-150) | Consistent |
| | strong / heavy | 120-150 / 150+ | 150-200 / 200+ | **PW is more conservative.** Keep PW, show Erowid in the note |
| | onset / duration | 30-45 m / total 3-6 h | 20-70 m / 3-5 h | Widen onset to 20-70 m |
| LSD oral | threshold / light | 15 / 15-75 | 10-20 / 20-75 | Consistent |
| | common | 75-150 | 50-150 | Consistent (Erowid lower floor) |
| | strong / heavy | 150-300 / 300+ | 150-400 / 400+ | PW more conservative, keep |
| | extra | | blotter 30-100 µg typical; **NBOMe often sold as LSD** | Add a safety note |
| DMT smoked | doses | 2 / 10-20 / 20-40 / 40-60 / 60+ | 2-5 / 10-20 / 20-40 / 40-60 | Match |
| | onset / total / after | 20-40 s / 5-20 m / 10-60 m | 15-60 s / 5-20 m / 15-60 m | Match; widen onset to 15-60 s |
| | extra | | pipe residue risk (up to ~20 mg left); changa needs slightly lower DMT | Add notes |
| 2C-B oral | doses | 5 / 10-15 / 15-25 / 25-45 / 45+ | 2-5 / 5-15 / 15-25 / 25-50 | Consistent (Erowid lower floor and a higher strong top) |
| Ketamine insufflated | doses | 5 / 10-30 / 30-75 / 75-150 / 150+ | 10-15 / 15-30 / 30-75 / strong 60-125 / **K-hole 100-250** | PW heavy (150+) starts higher than Erowid's K-hole (100). Prefer 100 mg as the "heavy" warning line |
| | onset / duration | 1-3 m / 1-2 h | 5-15 m / 45-60 m, after 1-3 h | Widen onset to 1-15 m; total 45 m-2 h |
| Ketamine oral | doses | 50 / 50-100 / 100-300 / 300-450 / 450+ | 40-50 / 50-100 / 75-300 / 200-450 / 500+ | Consistent |
| | **timing** | onset 10-30 m, **offset 3-6 h** | onset 5-20 m, **duration 90 min**, after 4-8 h | **Disagreement.** PW's 3-6 h offset looks too long for the active effect. Treat active effects as about 1.5-3 h and put the rest under after effects |
| Ketamine rectal | | not stored | peak 30-60 m, duration 1-2 h | Optional |
| Nicotine smoked | doses | 0.2 / 0.3-0.8 / 0.8-1.5 / 1.5-3.5 / 3.5+ | 0.2-0.3 / 0.3-0.8 / 0.6-1.5 / 1-2 / 2-4 | Common matches. Erowid strong/heavy are lower |
| | duration | total 1-3 h | duration **10-30 min**, after effects 1-3 h | **Disagreement.** PW "total" is really the after-effect window. Active effect is 10-30 min |
| Nicotine "oral" | | swallowed, onset 20-40 m, total 5-7 h | gum/lozenge-type: 1-4 mg common, duration 1-2 h | PW's buccal route is the Erowid equivalent. Keep both but label "oral (swallowed)" vs "buccal (gum, lozenge, pouch)" |
| Nicotine delivery per cigarette | | | labelled 0.13-2.0 mg (older method), 1-3 mg (Massachusetts method); up to 3 mg measured in plasma (Benowitz 1998); gum 3.4-4 mg bioavailable of 4 mg | See study row below |

## 3. Primary studies
| Topic | Finding | Source | Effect on our data |
|---|---|---|---|
| LSD PK (Dolder 2017) | plasma peak 1.4-1.5 h; half-life 2.6 h; subjective duration **8.2 h at 100 µg, 11.6 h at 200 µg**; dose-proportional, first-order | https://edoc.unibas.ch/56155 | PW 8-12 h total holds. **Duration scales with dose**, which `effect_curve.py` ignores |
| Psilocin PK | peak about 2 h; half-life 1.8-3 h; psilocin bioavailability about 55%; review range 1.23-4.72 h | https://pubmed.ncbi.nlm.nih.gov/39812743/ | Consistent with PW peak 2-2.5 h |
| Alcohol elimination | mean about 0.018 g% per h, range 0.009-0.035 (Widmark via NIST); range 0.10-0.20 g/L/h; TBW about 55-60% body weight in males, 50-55% in females | https://pmc.ncbi.nlm.nih.gov/articles/PMC4361698 ; Jones 2010 (cited, not read) | Alcohol Tracker's default rate should sit inside 0.010-0.020 and stay user-editable. Watson 1980 formula **not verified yet** |
| Nicotine delivery | absorbed about 1-2 mg per cigarette (UCSF); mean 2.3 mg, range 0.37-3.47 (NCI Monograph 7); half-life about 2 h (range 90-150 min) | https://cancercontrol.cancer.gov/brp/tcrb/monographs/7/m7_7.pdf | PW smoked common (0.8-1.5 mg) is about one cigarette. Use **about 1.5 mg absorbed per cigarette (range 0.4-3.5)** as the preset |
| Nicotine pouches | 10 mg pouch gives plasma exposure comparable to a cigarette; 4 mg pouch similar to 4 mg lozenge | https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9050656/ | Pouch presets by mg per pouch, not per mg of absorbed dose |
| MDMA | plasma level rises more than proportionally with dose (metabolism saturation), seen in all genotypes | https://pmc.ncbi.nlm.nih.gov/articles/PMC2014905 | Linear dose factor understates large doses; add a note and a cap |
| Ketamine bioavailability | intranasal 30-50% (63% at 28 mg S-ketamine down to 50% at 112 mg), sublingual 20-30%, oral 7-25%, IM 93-95% | https://www.ncbi.nlm.nih.gov/pmc/articles/PMC10479106/ | PW values (45 / 17 / 20-29) are inside these ranges |
| DMT IV (Strassman) | effects begin immediately, peak 90-120 s, nearly gone by 30 min | https://erowid.org/references/refs_view.php?ID=6271 | Consistent with PW IV (total 15-30 min) |

## 4. New or changed proposals
1. **Ketamine oral timing**: reduce `offset` to about 1-2 h (active ending around 90 min to 3 h), keep after effects 4-8 h. Needs your OK because it contradicts PW.
2. **Nicotine smoked**: store total as 10-30 min active plus 1-3 h after effects, instead of 1-3 h total.
3. **Nicotine routes**: relabel to "oral (swallowed)" and "buccal (gum, lozenge, pouch)".
4. **Ketamine insufflated**: warning line at 100 mg (Erowid K-hole) as well as PW's 150 mg.
5. **Widen onsets**: MDMA 20-70 m, DMT 15-60 s, insufflated ketamine 1-15 m, oral cannabis up to 120 m.
6. **Dose-scaled duration** for LSD (100 vs 200 µg) and nonlinear MDMA exposure in the effect curve.
7. **Safety notes**: NBOMe misrepresented as LSD; DMT pipe residue; changa needs less DMT.

## 5. Still not verified
- Erowid alcohol (no dose page exists), plus Erowid effects/FAQ pages for each substance.
- Watson 1980 TBW formula and Jones 2010 elimination review (cited via secondary pages only).
- Full MDMA PK dose-by-dose values and psilocin data for 15-20 mg doses (search summaries only).
- Cannabis Erowid dose page was read via search summaries, not directly.
