# Cannabis model review: bioavailability and curve shapes (2026-10-25)

Status: **proposals applied** in `app/packages/sj_core/lib/src/cannabis.dart` (inhaled 8/18/30%, vaporised 10/22/40%, sublingual 5/12/25%, oral unchanged; inhaled curve absorption half-life 8 min, sublingual 30 min and effect half-life 120 min, oral unchanged). The tables below show the numbers before and after.

## Sources read
- Huestis, *Human cannabinoid pharmacokinetics*, Chem Biodivers 2007 (full text, first 100k of 190k characters): https://pmc.ncbi.nlm.nih.gov/articles/PMC2689518/
- Brownie study, 10/25/50 mg THC, 17 adults: https://pmc.ncbi.nlm.nih.gov/articles/PMC7549129 (blood levels only; its subjective results are published separately and were not found)
- Spindle 2018 (smoked vs vaporised, 10 and 25 mg THC product) and Newmeyer 2016 abstract, via search summaries only; the Spindle full text was blocked by a captcha.
- Karschner 2011 and the TGA Sativex product information, via search summaries.

## Bioavailability
| Route | Current (low / central / high) | What the sources say | Proposed |
|---|---|---|---|
| Inhaled (smoked) | 10 / 25 / 35% | Huestis 2007: reported range 2-56%; "systemic availability of smoked THC is ca. 8-24%"; Adams and Martin used 10-25%. McGilveray 2005 gives a 30% average | **8 / 18 / 30%.** The old 25% centre sat at the top of the typical 8-24% band |
| Vaporised / dabbed | 30 / 45 / 60% | Only a single clinic page said 30-60%. Spindle 2018 and Newmeyer 2016 found blood THC virtually identical right after smoking and vaping, with somewhat higher levels later after vaping | **10 / 22 / 40%**, low confidence. Similar to smoking, wider upside |
| Oral | 4 / 10 / 20% | Huestis 2007 cites 4-20% overall: Wall 10-20%, Ohlsson 6% | **Keep.** Well supported |
| Sublingual | 10 / 25 / 35% | Karschner 2011: oral THC exposure was 93-99% of the same dose by oromucosal spray, i.e. about the same as swallowing. Much of a sublingual dose is swallowed | **5 / 12 / 25%**, low confidence |

A cross-check supports the lower inhaled centre. Spindle 2018 smoked cigarettes containing **10 mg** THC (product) and got moderate effects in infrequent users (drug-effect rating 46/100) with more at 25 mg. At 18% absorption, 10 mg of product is 1.8 mg absorbed, the bottom of PsychonautWiki's "common" band (2-4 mg), and 25 mg is 4.5 mg, "strong". At 25% it would read stronger than these volunteers reported. Under the proposal a whole 1 g joint at 20% (200 mg product) is 36 mg absorbed, far beyond "heavy", which is why `fractionUsed` matters: nobody in the study smoked that much.

Erowid's 0.3 g of medium flower as "strong" lines up better too: at 15% that is 45 mg product, 8 mg at 18%, which is "strong" to "heavy" rather than clearly heavy.

## Curve shapes
Reminder: the curves are **effect** curves ("how strong do you feel"), not plasma curves. Effects lag plasma by minutes to tens of minutes, and Huestis 2007 notes plasma THC "begins to decline prior to the time of peak effects".

| Route | Evidence | Current model | Verdict |
|---|---|---|---|
| Inhaled | Plasma peak about 9 minutes (Huestis 1992, mean 84 and 162 ng/mL), at most 5 ng/mL within 2 h. Peak effect 30-45 min after smoking starts. Effect onset within minutes. Newmeyer: median plasma tmax about 6 min | Peak 22 min, 50% by 5 min, 72% at 1 h, 36% at 2 h, 9% at 4 h | Slightly early and a little short. **Proposed absorption half-life 8 min, effect half-life 60 min: peak 27 min, 78% at 1 h, 39% at 2 h, 10% at 4 h** |
| Oral | Brownie study (whole blood): THC tmax 1.6-1.9 h, 11-OH-THC 1.9-2.2 h, back to baseline within 8 h. Newmeyer: median tmax 2.5 h. Ohlsson: peak 1-5 h. Wall: 4-6 h in sesame oil | Peak 122 min, 20% of peak left at 8 h, 10% at 10 h | **Keep.** Peak matches the brownie study. Effects outlasting blood levels is expected, and fits the reference data's 4-10 h total |
| Sublingual | TGA Sativex information: plasma THC appears within about 15 min, peak 45-120 min. PsychonautWiki user reports say onset 1-10 min and peak 30-60 min | Peak 53 min, 73% at 2 h, 32% at 4 h | Peak a little early compared with the PK data. **Proposed lag 5 min, absorption half-life 30 min, effect half-life 120 min: peak 85 min, 94% at 2 h, 54% at 4 h.** Low confidence; PK data and user reports disagree |

## Other observations
- **Dose scaling is not linear in the real data.** The brownie study's mean peak whole-blood THC was 0.8 / 3.4 / 5.9 ng/mL at 10 / 25 / 50 mg, with huge individual spread (0-18). The app's intensity grows linearly with dose up to the 3x cap. That cap is the right idea, and a sublinear rule would be a defensible refinement, but there is no firm data to fit it.
- **Tolerance changes everything.** Regular users feel less at the same dose; the app's tolerance track models this separately.
- **11-OH-THC.** After oral dosing, 11-OH-THC is about as high as THC (Huestis 2007), versus 6-10% of THC after smoking. The oral curve does not model it separately, so oral effect per absorbed mg is folded into PsychonautWiki's oral bands.
- **Fatigue and food.** Taking edibles with a fatty meal speeds and raises absorption (the studies above mostly did not control it). Not modelled.

## Not verified
- Subjective-effect time courses for smoking and edibles in the primary papers (only review statements were read).
- Spindle 2018 full text (captcha).
- Any primary study measuring sublingual tincture bioavailability. The 12% figure is an inference from Karschner 2011.
