"""Build app/assets/data/dose_audit.json: dose bands cross-checked against several sources.

The app loads dose_audit.json as an overlay on the catalog (app/lib/data/reference_repository.dart);
the MCP server reads it for its dose hold. This script is how that file was made on 2026-11-15.

Inputs (kept in a sources folder, by default build/dose_audit_sources/, or set DOSE_AUDIT_SOURCES):
  pw/sb_<Page>.json   PsychonautWiki's Template:SubstanceBox/<Page> wikitext, from the MediaWiki API
  tripsit/drugs.json  TripSit's open dataset (CC BY-SA 4.0), github.com/TripSit/drugs
  app/assets/data/substances.json and substances_extra.json (the catalog; read in place)
Erowid's dose charts cannot be downloaded in bulk, so their figures are typed into AUDIT below from
the pages linked there (read by hand), together with the clinical papers and FDA labels used for context.

Re-run (needs network for --fetch only; the Erowid numbers in AUDIT do not refresh themselves):
  python scripts/build_dose_audit.py --fetch            # download the PsychonautWiki and TripSit inputs
  python scripts/build_dose_audit.py --rest app/assets/data/dose_audit.json
Without an output path it only prints the comparison report. Review the report before committing:
"!!" marks a ladder that does not rise, SKIP>3x a route left unaudited because two sources differ
more than threefold, and HEAVY KEPT a heavy edge held at the app's previous value.

Pick rule per band edge (threshold, low, common, high, heavy):
  3+ sources: the median (lower median for an even count).
  2 sources: PsychonautWiki's value if the other is within 1.25x, otherwise the lower (more cautious) one.
  1 source: that value.
  A heavy (warning) edge never moves above the app's previous one unless two sources publish a
  higher heavy figure. Clinical papers and FDA labels are context only and never vote.
Ladder: low.max = common.min, common.max = high.min, high.max = heavy (or the strong max when no source gives heavy).
--rest adds every other catalog compound where PsychonautWiki and TripSit both publish a route.

After a rebuild, run scripts/apply_owner_dose_decisions.py so the owner's own choices (commit 6c7a7ec) replace the audit's medians on those routes.
"""
import json, os, re, sys, time, urllib.parse, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HERE = Path(os.environ.get("DOSE_AUDIT_SOURCES", ROOT / "build" / "dose_audit_sources"))
APP = ROOT / "app" / "assets" / "data"
RETRIEVED = "2026-11-15"
U = {"µg": 0.001, "ug": 0.001, "mg": 1.0, "g": 1000.0}

catalog = json.loads((APP / "substances.json").read_text(encoding="utf-8")) + json.loads((APP / "substances_extra.json").read_text(encoding="utf-8"))
by = {}
for s in catalog:
    by.setdefault(s["key"], s)
_ts_path = HERE / "tripsit" / "drugs.json"
tripsit = json.loads(_ts_path.read_text(encoding="utf-8")) if _ts_path.exists() else {}
SKIP_KEYS = {"psilocybin_mushrooms", "salvinorin_a"}  # mushrooms: bands owned elsewhere; salvinorin A: no bands


def rest_rows():
    """(category, key, PsychonautWiki page) for catalog compounds not in AUDIT, in category order."""
    audited = {a[0] for a in AUDIT} | SKIP_KEYS
    rows, seen = [], set()
    for s in catalog:
        u = s.get("wiki_url") or ""
        if s["key"] in seen or s["key"] in audited or not u.startswith("https://psychonautwiki.org/wiki/"):
            continue
        seen.add(s["key"])
        if any(r.get("dose_common") for r in s["roas"]):
            rows.append((s.get("category", ""), s["key"], urllib.parse.unquote(u.split("/wiki/")[1])))
    return sorted(rows)


def fetch():
    """Download the PsychonautWiki templates and TripSit's dataset into HERE (network)."""
    (HERE / "pw").mkdir(parents=True, exist_ok=True)
    (HERE / "tripsit").mkdir(parents=True, exist_ok=True)
    agent = {"User-Agent": "Mozilla/5.0 (substance-journal dose audit)"}
    with urllib.request.urlopen(urllib.request.Request("https://raw.githubusercontent.com/TripSit/drugs/main/drugs.json", headers=agent), timeout=60) as r:
        _ts_path.write_bytes(r.read())
    pages = sorted({a[2] for a in AUDIT} | {p for _c, _k, p in rest_rows()})
    for page in pages:
        q = urllib.parse.urlencode({"action": "parse", "page": "Template:SubstanceBox/" + page, "prop": "wikitext", "format": "json", "redirects": 1})
        with urllib.request.urlopen(urllib.request.Request("https://psychonautwiki.org/w/api.php?" + q, headers=agent), timeout=30) as r:
            (HERE / "pw" / f"sb_{page.replace('/', '_')}.json").write_bytes(r.read())
        time.sleep(0.3)
    print(f"fetched TripSit and {len(pages)} PsychonautWiki pages into {HERE}")


def conv(v, frm, to):
    return None if v is None else round(v * U[frm] / U[to], 6)


# ---------- PsychonautWiki ----------
def pw_bands(page):
    w = json.loads((HERE / "pw" / f"sb_{page}.json").read_text(encoding="utf-8"))["parse"]["wikitext"]["*"]
    out = {}
    for m in re.finditer(r"\|\s*(\w+)ROA_(Threshold|Light|Common|Strong|Heavy)\s*=([^\n]*)", w):
        route, band, raw = m.group(1).lower(), m.group(2).lower(), m.group(3)
        raw = re.sub(r"<ref.*?(</ref>|/>)", "", raw)
        raw = re.sub(r"\[\[[^\]]*?::([^\]]*)\]\]", r"\1", raw)
        raw = re.sub(r"<[^>]+>|'''[^']*'''", "", raw)
        nums = [float(x) for x in re.findall(r"\d+(?:\.\d+)?", raw.split("|")[0] if "abbr" not in raw else raw.replace("{{abbr|", "").split("]]")[0])]
        unit = next((u for u in ("µg", "mg", "g") if re.search(rf"\d\s*{u}\b|\s{u}\b", raw)), None)
        if not nums:
            continue
        shown = re.sub(r"\{\{abbr\|([^\]|]*)\]\]\|([^}]*)\}\}", lambda m: m.group(1) + " (" + m.group(2) + ")", raw).replace(chr(39) * 3, "")
        out.setdefault(route, {})[band] = (nums, unit, re.sub(r"\s+", " ", shown).strip())
    return out


def pw_source(page, pw_route, unit):
    b = pw_bands(page).get(pw_route)
    if not b:
        return None
    vals, text = {}, []
    for band in ("threshold", "light", "common", "strong", "heavy"):
        if band not in b:
            continue
        nums, u, raw = b[band]
        u = u or unit
        lo = conv(nums[0], u, unit)
        hi = conv(nums[1], u, unit) if len(nums) > 1 else None
        vals[band] = (lo, hi)
        text.append(f"{band} {raw}")
    return {"name": "PsychonautWiki", "url": f"https://psychonautwiki.org/wiki/{page}", "published": "; ".join(text), "vals": vals}


# ---------- TripSit ----------
def ts_parse(text, unit):
    s = text.strip().lower().replace("µ", "u").replace(" ", "").rstrip(".")
    m = re.fullmatch(r"([\d.]+)([a-z]*)(?:-([\d.]+)([a-z]*))?(\+?)", s)
    if not m:
        return None
    lo, u1, hi, u2, _ = m.groups()
    u = (u2 or u1).replace("ug", "µg")
    if u not in U:
        return None
    return conv(float(lo), u, unit), (conv(float(hi), u, unit) if hi else None)


def ts_source(key, ts_route, unit):
    e = tripsit.get(key)
    if not e:
        return None
    fd = {r.lower(): v for r, v in (e.get("formatted_dose") or {}).items()}
    bands = fd.get(ts_route)
    if not bands:
        return None
    vals, text = {}, []
    for theirs, ours in (("Threshold", "threshold"), ("Light", "light"), ("Common", "common"), ("Strong", "strong"), ("Heavy", "heavy")):
        if theirs in bands:
            text.append(f"{ours} {bands[theirs]}")
            p = ts_parse(bands[theirs], unit)
            if p:
                vals[ours] = p
    if not vals:
        return None
    return {"name": "TripSit", "url": f"https://tripsit.me/factsheets/{key}", "published": f"{ts_route}: " + "; ".join(text), "vals": vals}


def ero(path, published, **vals):
    return {"name": "Erowid", "url": f"https://erowid.org/{path}", "published": published, "vals": {k: v for k, v in vals.items()}}


def ctx(name, url, published):
    return {"name": name, "url": url, "published": published, "context": True}


def label(drug, setid, text):
    return ctx(f"FDA label ({drug})", f"https://dailymed.nlm.nih.gov/dailymed/lookup.cfm?setid={setid}", text)


# ---------- the audit list: (key, route, PW page, PW route, TripSit key, TripSit route, extra sources, overrides) ----------
HOLZE = ctx("Holze et al. 2021, Neuropsychopharmacology 46:537 (25/50/100/200 µg LSD base)", "https://pmc.ncbi.nlm.nih.gov/articles/PMC8027607/",
            "Subjective effects from 25 µg; 50 µg 'moderately intense', a good starting dose for people new to psychedelics; ceiling for good effects at 100 µg; 200 µg more ego dissolution and significant anxiety; duration 6.7 h (25 µg) to 11 h (200 µg). 1 µg base = 1.25 µg tartrate.")
BERSHAD = ctx("Bershad et al. 2019, Biol Psychiatry (6.5/13/26 µg LSD)", "https://pmc.ncbi.nlm.nih.gov/articles/PMC6814527/",
              "Dose-related subjective effects at 6.5, 13 and 26 µg; the authors call 13 µg a threshold dose.")
VIZELI = ctx("Vizeli and Liechti 2017, J Psychopharmacol (75 and 125 mg MDMA, 166 subjects)", "https://pubmed.ncbi.nlm.nih.gov/28443695/",
             "125 mg gave more good effects than 75 mg, and significantly more hypertension, tachycardia and body temperature above 38 °C.")
KLAIBER = ctx("Klaiber et al. 2024, Neuropsychopharmacology (100/200/400/800 mg mescaline)", "https://pmc.ncbi.nlm.nih.gov/articles/PMC11442856/",
              "Effects dose-dependent above 100 mg; duration 6.4 h (100 mg) to 14 h (800 mg); nausea and vomiting frequent at 800 mg.")
LEY = ctx("Ley et al. 2023, Neuropsychopharmacology (mescaline 300/500 mg vs LSD 100 µg vs psilocybin 20 mg)", "https://pmc.ncbi.nlm.nih.gov/articles/PMC10517157/",
          "300 and 500 mg called moderate to high doses; 500 mg mescaline was comparable to 100 µg LSD and 20 mg psilocybin.")
NHS = ctx("NHS: calculating alcohol units", "https://www.nhs.uk/live-well/alcohol-advice/calculating-alcohol-units/", "One UK unit is 10 ml or 8 g of pure alcohol (used to convert TripSit's units).")

AUDIT = [
    # (1) LSD
    ("lsd", "sublingual", "LSD", "sublingual", "lsd", "oral",
     [ero("chemicals/lsd/lsd_dose.shtml", "oral: threshold 10-20 ug; light 20-75 ug; common 50-150 ug; strong 150-400 ug; heavy 400+ ug",
          threshold=(10, 20), light=(20, 75), common=(50, 150), strong=(150, 400), heavy=(400, None)), HOLZE, BERSHAD],
     {"note": "Erowid and TripSit publish LSD doses as oral; blotter is held in the mouth, so they are compared with the sublingual route here. Street and study doses differ by salt: 100 µg LSD base is about 125 µg tartrate (Holze 2021). Holze 2021 places 50 µg as a moderate first experience, 100 µg as a full dose and 200 µg as the dose where anxiety rises."}),
    # (3) most commonly logged
    ("mdma", "oral", "MDMA", "oral", "mdma", "oral",
     [ero("chemicals/mdma/mdma_dose.shtml", "oral: threshold 30 mg; light 40-75 mg; common 75-125 mg (60-90 small or sensitive, 110-150 large); strong 150-200 mg; heavy 200+ mg",
          threshold=(30, None), light=(40, 75), common=(75, 125), strong=(150, 200), heavy=(200, None)), VIZELI],
     {"note": "Sources disagree most on where heavy begins (150, 175 or 200 mg). In Vizeli and Liechti 2017, 125 mg already raised blood pressure, heart rate and body temperature significantly more often than 75 mg. Doses are for pure MDMA HCl; pills vary widely."}),
    ("cannabis", "oral", "Cannabis", "oral", None, None,
     [ero("plants/cannabis/cannabis_dose.shtml", "oral THC, no tolerance: light 2-4 mg; medium 3-8 mg; strong 4-15 mg",
          light=(2, 4), common=(3, 8), strong=(4, 15))],
     {"keep": "PsychonautWiki", "agreement": "disagree", "confidence": "low",
      "note": "Erowid's oral ranges overlap each other and begin lower: for people without tolerance its strong range starts at 4 mg THC, where PsychonautWiki's starts at 10 mg. The overlapping ranges cannot be merged into one ladder, so PsychonautWiki's bands are kept; start lower than the common band and wait two hours before taking more."}),
    ("cannabis", "smoked", "Cannabis", "smoked", None, None, [],
     {"note": "Erowid (grams of flower) and TripSit (mg of product) do not publish smoked doses as mg of THC absorbed, so they cannot be compared with this route's unit."}),
    ("alcohol", "oral", "Alcohol", "oral", "alcohol", None,
     [ctx("TripSit", "https://tripsit.me/factsheets/alcohol", "oral: light 1-2 units; common 2-4 units; heavy 5-6 units (UK unit = 8 g: light 8-16 g, common 16-32 g, heavy 40-48 g)"), NHS],
     {"extra_vals": {"name": "TripSit", "url": "https://tripsit.me/factsheets/alcohol", "published": "oral: light 1-2 units; common 2-4 units; heavy 5-6 units (8 g per UK unit)",
                     "vals": {"light": (8, 16), "common": (16, 32), "heavy": (40, 48)}}}),
    ("caffeine", "oral", "Caffeine", "oral", "caffeine", "oral",
     [ero("chemicals/caffeine/caffeine_dose.shtml", "oral: threshold 10-20 mg; common 50-150 mg; strong 150-400 mg; heavy 400+ mg",
          threshold=(10, 20), common=(50, 150), strong=(150, 400), heavy=(400, None))], {}),
    ("caffeine", "insufflated", "Caffeine", "insufflated", "caffeine", "insufflated", [], {}),
    ("caffeine", "smoked", "Caffeine", "smoked", "caffeine", "smoked", [], {}),
    ("nicotine", "smoked", "Nicotine", "smoked", None, None,
     [ero("chemicals/nicotine/nicotine_dose.shtml", "smoked: threshold 0.2-0.3 mg; light 0.3-0.8 mg; common 0.6-1.5 mg; strong 1-2 mg; heavy 2-4 mg",
          threshold=(0.2, 0.3), light=(0.3, 0.8), common=(0.6, 1.5), strong=(1, 2), heavy=(2, 4))], {}),
    ("nicotine", "buccal", "Nicotine", "buccal", None, None, [], {}),
    ("nicotine", "oral", "Nicotine", "oral", None, None, [], {}),
    ("ketamine", "insufflated", "Ketamine", "insufflated", "ketamine", "insufflated",
     [ero("chemicals/ketamine/ketamine_dose.shtml", "insufflated: threshold 10-15 mg; light 15-30 mg; common 30-75 mg; strong 60-125 mg; 'the K hole' 100-250 mg",
          threshold=(10, 15), light=(15, 30), common=(30, 75), strong=(60, 125), heavy=(100, 250))], {}),
    ("ketamine", "oral", "Ketamine", "oral", "ketamine", "oral",
     [ero("chemicals/ketamine/ketamine_dose.shtml", "oral: threshold 40-50 mg; light 50-100 mg; common 75-300 mg; strong 200-450 mg",
          threshold=(40, 50), light=(50, 100), common=(75, 300), strong=(200, 450))], {}),
    ("cocaine", "insufflated", "Cocaine", "insufflated", "cocaine", "insufflated", [], {"note": "PsychonautWiki now lists lower insufflated bands (light 10-30, common 30-60, strong 60-90, heavy 90+ mg) than the copy this app shipped with, which matched TripSit (20-50, 50-100, 100-150, 150+ mg). Street cocaine purity varies widely."}),
    ("cocaine", "intravenous", "Cocaine", "intravenous", "cocaine", "intravenous", [], {}),
    ("cocaine", "oral", "Cocaine", "oral", "cocaine", "oral", [], {}),
    ("cocaine", "smoked", "Cocaine", "smoked", "cocaine", "smoked", [], {}),
    ("amphetamine", "oral", "Amphetamine", "oral", "amphetamine", "oral",
     [label("amphetamine sulfate", "00242264-40d8-4267-a91a-727a1f088616", "Narcolepsy: usual dose 5 to 60 mg per day in divided doses; start with 10 mg daily from age 12.")], {}),
    ("amphetamine", "insufflated", "Amphetamine", "insufflated", "amphetamine", "insufflated", [], {}),
    ("amphetamine", "intravenous", "Amphetamine", "intravenous", "amphetamine", "intravenous", [], {}),
    ("methamphetamine", "oral", "Methamphetamine", "oral", "methamphetamine", "oral",
     [ero("chemicals/meth/meth_dose.shtml", "oral: threshold 5 mg; light 5-15 mg; common 10-30 mg; strong 20-60 mg; very strong (or with tolerance) 40-150 mg",
          threshold=(5, None), light=(5, 15), common=(10, 30), strong=(20, 60), heavy=(40, 150)),
      label("methamphetamine hydrochloride", "90c02ac6-e5e2-4c97-8c68-81e4e389a195", "Start 5 mg once or twice daily; usual range 20 to 25 mg daily.")], {}),
    ("methamphetamine", "insufflated", "Methamphetamine", "insufflated", "methamphetamine", "insufflated",
     [ero("chemicals/meth/meth_dose.shtml", "insufflated: threshold 5 mg; light 5-15 mg; common 10-40 mg; strong 30-60 mg; very strong 50+ mg",
          threshold=(5, None), light=(5, 15), common=(10, 40), strong=(30, 60), heavy=(50, None))], {}),
    ("methamphetamine", "smoked", "Methamphetamine", "smoked", "methamphetamine", "smoked",
     [ero("chemicals/meth/meth_dose.shtml", "smoked/vaporized: threshold 5-10 mg; light 10-20 mg; common 10-40 mg; strong 30-60 mg; very strong 50+ mg",
          threshold=(5, 10), light=(10, 20), common=(10, 40), strong=(30, 60), heavy=(50, None))], {}),
    ("methamphetamine", "intravenous", "Methamphetamine", "intravenous", "methamphetamine", "intravenous",
     [ero("chemicals/meth/meth_dose.shtml", "injected: threshold 5 mg; light 5-10 mg; common 10-40 mg; strong 30-60 mg; very strong 50-100 mg",
          threshold=(5, None), light=(5, 10), common=(10, 40), strong=(30, 60), heavy=(50, 100))], {}),
    ("methamphetamine", "rectal", "Methamphetamine", "rectal", "methamphetamine", "rectal", [], {}),
    ("methylphenidate", "oral", "Methylphenidate", "oral", "methylphenidate", "oral",
     [label("methylphenidate hydrochloride ER", "10aa0dc0-bd0e-4927-a19a-8722d78ad67d", "Extended release: start 20 mg once daily; maximum 60 mg per day.")], {}),
    ("methylphenidate", "insufflated", "Methylphenidate", "insufflated", "methylphenidate", "insufflated", [], {}),
    ("dmt", "smoked", "DMT", "smoked", "dmt", "vapourized",
     [ero("chemicals/dmt/dmt_dose.shtml", "smoked/vaporized: threshold 2-5 mg; light 10-20 mg; common 20-40 mg; strong 40-60 mg",
          threshold=(2, 5), light=(10, 20), common=(20, 40), strong=(40, 60))], {}),
    ("5-meo-dmt", "smoked", "5-MeO-DMT", "smoked", "5-meo-dmt", "smoked",
     [ero("chemicals/5meo_dmt/5meo_dmt_dose.shtml", "smoked/vaporized: threshold 1-2 mg; light 2-5 mg; common 5-10 mg; strong 10-20 mg",
          threshold=(1, 2), light=(2, 5), common=(5, 10), strong=(10, 20))], {}),
    ("5-meo-dmt", "insufflated", "5-MeO-DMT", "insufflated", "5-meo-dmt", "insufflated",
     [ero("chemicals/5meo_dmt/5meo_dmt_dose.shtml", "insufflated: threshold 3-5 mg; light 5-10 mg; common 8-15 mg; strong 10-25 mg",
          threshold=(3, 5), light=(5, 10), common=(8, 15), strong=(10, 25))], {}),
    ("mescaline", "oral", "Mescaline", "oral", "mescaline", "oral",
     [ero("chemicals/mescaline/mescaline_dose.shtml", "oral mescaline HCl: threshold 100 mg; light 100-200 mg; common 200-300 mg; strong 300-500 mg; heavy 500-700 mg",
          threshold=(100, None), light=(100, 200), common=(200, 300), strong=(300, 500), heavy=(500, 700)), KLAIBER, LEY],
     {"note": "Erowid's chart is for mescaline hydrochloride. The clinical studies call 300-500 mg moderate to high and found 500 mg comparable to 100 µg LSD, so the heavy edge from Erowid and TripSit (500 mg) is cautious; PsychonautWiki puts heavy at 800 mg, where nausea and vomiting were frequent (Klaiber 2024)."}),
    ("2c-b", "oral", "2C-B", "oral", "2c-b", "oral",
     [ero("chemicals/2cb/2cb_dose.shtml", "oral: threshold 2-5 mg; light 5-15 mg; common 15-25 mg; strong 25-50 mg",
          threshold=(2, 5), light=(5, 15), common=(15, 25), strong=(25, 50))], {}),
    ("2c-b", "insufflated", "2C-B", "insufflated", "2c-b", "insufflated", [], {}),
    ("1p-lsd", "oral", "1P-LSD", "oral", "1p-lsd", "oral", [], {}),
    ("4-aco-dmt", "oral", "4-AcO-DMT", "oral", "4-aco-dmt", "oral",
     [ero("chemicals/4_acetoxy_dmt/4_acetoxy_dmt_dose.shtml", "oral: threshold 2.5 mg; light 3-7 mg; common 8-20 mg; strong 20-35 mg; heavy 30+ mg",
          threshold=(2.5, None), light=(3, 7), common=(8, 20), strong=(20, 35), heavy=(30, None))], {}),
    ("4-aco-dmt", "insufflated", "4-AcO-DMT", "insufflated", "4-aco-dmt", "insufflated",
     [ero("chemicals/4_acetoxy_dmt/4_acetoxy_dmt_dose.shtml", "insufflated: threshold 2-4 mg; light 3-10 mg; common 8-20 mg; strong 15-25 mg; heavy 25+ mg",
          threshold=(2, 4), light=(3, 10), common=(8, 20), strong=(15, 25), heavy=(25, None))], {}),
    ("dextromethorphan", "oral", "DXM", "oral", "dextromethorphan", None,
     [ero("chemicals/dxm/dxm_dose.shtml", "oral DXM HBr: threshold unknown; light 100-200 mg; common 200-400 mg; strong 300-600 mg; heavy 600-1500 mg; risk of death 2,500-20,000 mg",
          light=(100, 200), common=(200, 400), strong=(300, 600), heavy=(600, 1500)),
      ctx("TripSit", "https://tripsit.me/factsheets/dextromethorphan", "oral: light 1.5-2.5 mg/kg; common 2.5-7.5 mg/kg; strong 7.5-15 mg/kg; heavy 15-20 mg/kg (per kg of body weight, so not compared)")], {}),
    ("nitrous", "inhaled", "Nitrous", "inhaled", "nitrous", None, [], {}),
    ("ghb", "oral", "GHB", "oral", "ghb", "oral",
     [ero("chemicals/ghb/ghb_dose.shtml", "oral: light 0.5-1.5 g; common 1-2.5 g; strong 2-4 g; can induce heavy sleep 3-5 g; overdose 5-10 g; poisoning (risk of death) 10+ g",
          light=(0.5, 1.5), common=(1, 2.5), strong=(2, 4), heavy=(3, 5))], {}),
    ("diazepam", "oral", "Diazepam", "oral", "diazepam", "oral",
     [label("diazepam", "01f04ee4-fff9-499a-8213-984e16368084", "Anxiety: 2 mg to 10 mg, 2 to 4 times daily.")], {}),
    ("alprazolam", "oral", "Alprazolam", "oral", "alprazolam", "oral",
     [label("alprazolam", "02840ea6-e4a0-96a0-e063-6394a90a19ae", "Anxiety: start 0.25 mg to 0.5 mg three times daily; maximum 4 mg per day in divided doses.")], {}),
    ("alprazolam", "inhaled", "Alprazolam", "inhaled", "alprazolam", "inhaled", [], {}),
    ("clonazepam", "oral", "Clonazepam", "oral", "clonazepam", "oral",
     [label("clonazepam", "00f323c0-e007-40df-ae7f-e6b3c7ba0aa8", "Panic disorder: initial dose 0.25 mg twice daily. Seizures: initial dose not above 1.5 mg per day in three doses.")], {}),
    ("oxycodone", "oral", "Oxycodone", "oral", "oxycodone", "oral",
     [ero("pharms/oxycodone/oxycodone_dose.shtml", "oral, no tolerance: light 2.5-5 mg; common 5-10 mg; strong 10-30 mg",
          light=(2.5, 5), common=(5, 10), strong=(10, 30)),
      label("oxycodone hydrochloride", "01db4606-d49c-4b10-a78a-1cf41880a9fb", "First opioid (opioid-naive): 5 to 15 mg every 4 to 6 hours as needed.")], {}),
    ("oxycodone", "insufflated", "Oxycodone", "insufflated", "oxycodone", "insufflated",
     [ero("pharms/oxycodone/oxycodone_dose.shtml", "insufflated, no tolerance: common 2.5-5 mg; strong 5-10 mg", common=(2.5, 5), strong=(5, 10))], {}),
    ("oxycodone", "intravenous", "Oxycodone", "intravenous", "oxycodone", "intravenous", [], {}),
    ("oxycodone", "smoked", "Oxycodone", "smoked", "oxycodone", "smoked", [], {}),
    ("hydrocodone", "oral", "Hydrocodone", "oral", "hydrocodone", "oral",
     [label("hydrocodone bitartrate and acetaminophen", "025eb0f7-d002-4ce0-87b8-71461ab18356", "First opioid: 1 to 2 tablets of 5 mg/325 mg every 4 to 6 hours as needed.")], {}),
    ("morphine", "oral", "Morphine", "oral", "morphine", "oral",
     [label("morphine sulfate", "07593aa4-f2c4-4d6e-b186-ab2a4ecaa38a", "First opioid (opioid-naive adults): 15 mg to 30 mg every 4 hours as needed.")], {}),
    ("morphine", "intravenous", "Morphine", "intravenous", "morphine", "intravenous", [], {}),
    ("codeine", "oral", "Codeine", "oral", "codeine", "oral",
     [label("codeine sulfate", "010905f9-3bcb-4b50-9fe8-a3ad0010f14c", "Start 15 to 60 mg every 4 hours as needed.")], {}),
    ("tramadol", "oral", "Tramadol", "oral", "tramadol", "oral",
     [ero("pharms/tramadol/tramadol_dose.shtml", "oral: threshold 25 mg; light 50-100 mg; common 75-200 mg; strong 250+ mg",
          threshold=(25, None), light=(50, 100), common=(75, 200), strong=(250, None)),
      label("tramadol hydrochloride", "007bf37f-0e46-426a-ac8c-be63d4b7414c", "Start 50 mg to 100 mg every 4 to 6 hours as needed; not more than 400 mg per day.")], {}),
    ("kratom", "oral", "Kratom", "oral", "kratom", "oral",
     [ero("plants/kratom/kratom_dose.shtml", "oral dried leaf, 2018 standard grade: threshold 1-2 g; light 2-4 g; common 3-5 g; strong 4-8 g",
          threshold=(1, 2), light=(2, 4), common=(3, 5), strong=(4, 8))],
     {"note": "Erowid gives separate charts by leaf grade; the 2018 standard grade is used here. Extract-enhanced products need far less. TripSit's figures match an older PsychonautWiki version."}),
    ("modafinil", "oral", "Modafinil", "oral", "modafinil", "oral",
     [label("modafinil", "013450dd-cd42-46c7-98d6-9a2925761978", "200 mg once a day; up to 400 mg a day was tolerated with no consistent added benefit.")], {}),
    ("pregabalin", "oral", "Pregabalin", "oral", "pregabalin", "oral",
     [label("pregabalin", "0101cd1f-4a95-40e9-86a8-ccde8d656e3d", "Begin at 150 mg per day; maximum 600 mg per day.")], {}),
    ("pregabalin", "rectal", "Pregabalin", "rectal", "pregabalin", "rectal", [], {}),
    ("gabapentin", "oral", "Gabapentin", "oral", "gabapentin", "oral",
     [label("gabapentin", "01b810b7-f4c8-4412-bbc5-b9220d8770d8", "Postherpetic neuralgia: 300 mg on day 1, titrated up to 1800 mg per day; epilepsy: 300 to 600 mg three times daily.")], {}),
    ("phenibut", "oral", "Phenibut", "oral", "phenibut", "oral", [], {}),
    ("pcp", "oral", "PCP", "oral", "pcp", "oral",
     [ero("chemicals/pcp/pcp_dose.shtml", "oral: light 3-5 mg; common 5-10 mg; strong 10+ mg", light=(3, 5), common=(5, 10), strong=(10, None))], {}),
    ("pcp", "insufflated", "PCP", "insufflated", "pcp", "insufflated", [], {}),
    ("pcp", "smoked", "PCP", "smoked", "pcp", "smoked", [], {}),
    ("methoxetamine", "insufflated", "Methoxetamine", "insufflated", "mxe", "insufflated",
     [ero("chemicals/methoxetamine/methoxetamine_dose.shtml", "insufflated (very tentative): threshold 5-20 mg; light 10-50 mg; common 20-60 mg; strong 25-100+ mg",
          threshold=(5, 20), light=(10, 50), common=(20, 60), strong=(25, 100))], {}),
    ("methoxetamine", "oral", "Methoxetamine", "oral", "mxe", "oral",
     [ero("chemicals/methoxetamine/methoxetamine_dose.shtml", "oral (very tentative): threshold 8-20 mg; light 10-30 mg; common 40-60 mg; strong 50-100+ mg",
          threshold=(8, 20), light=(10, 30), common=(40, 60), strong=(50, 100))], {}),
]

EDGES = ("threshold", "light", "common", "strong", "heavy")
HEAVY_KEPT = []


def pick(values, pw_value):
    vals = sorted(v for v in values if v is not None)
    if not vals:
        return None
    if len(vals) >= 3:
        return vals[(len(vals) - 1) // 2]
    if len(vals) == 2:
        lo, hi = vals
        if pw_value is not None and hi / lo <= 1.25:
            return pw_value
        return lo
    return vals[0]


def fmt(v):
    return int(v) if float(v).is_integer() else v


def build(audit=AUDIT, require_two=False, out=None, report=None):
    out = {} if out is None else out
    report = [] if report is None else report
    for key, route, page, pw_route, ts_key, ts_route, extra, opts in audit:
        s = by[key]
        roa = next(r for r in s["roas"] if r["route"] == route)
        unit = roa["unit"]
        if unit not in U:
            continue
        sources = []
        try:
            pw = pw_source(page, pw_route, unit)
        except (KeyError, FileNotFoundError, json.JSONDecodeError):
            pw = None
        if pw:
            sources.append(pw)
        if ts_key and ts_route:
            t = ts_source(ts_key, ts_route, unit)
            if t:
                sources.append(t)
        if opts.get("extra_vals"):
            sources.append(opts["extra_vals"])
        sources += [e for e in extra if not e.get("context")]
        context = [e for e in extra if e.get("context") and not (opts.get("extra_vals") and e["name"] == "TripSit")]
        numeric = [x for x in sources if x.get("vals")]
        pw_vals = pw["vals"] if pw else {}
        if opts.get("keep") == "PsychonautWiki":
            chosen = {e: pw_vals.get(e, (None, None))[0] for e in EDGES}
            strong_max = pw_vals.get("strong", (None, None))[1]
        else:
            chosen = {e: pick([x["vals"].get(e, (None,))[0] for x in numeric], pw_vals.get(e, (None,))[0]) for e in EDGES}
            strong_max = pick([x["vals"].get("strong", (None, None))[1] for x in numeric], pw_vals.get("strong", (None, None))[1])
        # spread and agreement
        worst = 1.0
        for e in EDGES:
            vs = [x["vals"][e][0] for x in numeric if e in x["vals"] and x["vals"][e][0]]
            if len(vs) >= 2:
                worst = max(worst, max(vs) / min(vs))
        agreement = opts.get("agreement") or ("agree" if worst <= 1.25 else "minor differences" if worst <= 1.6 else "disagree")
        independent = len(numeric)
        if require_two and independent == 2 and worst > 3:
            report.append(f"SKIP>3x {key} {route} " + " | ".join(x["published"] for x in numeric))
            continue
        if independent == 2 and worst > 3 and pw and opts.get("keep") != "PsychonautWiki":
            # Two sources on different scales (often a prescribing dose against a recreational
            # one): mixing their edges would make a nonsense ladder, so show PsychonautWiki's
            # as published and flag the other's lower figures.
            other = next(x for x in numeric if x is not pw)
            chosen = {e: pw_vals.get(e, (None, None))[0] for e in EDGES}
            strong_max = pw_vals.get("strong", (None, None))[1]
            opts = {**opts, "keep": "PsychonautWiki", "confidence": "low", "agreement": "disagree",
                    "note": f"The two sources differ more than threefold, so PsychonautWiki's ladder is shown as published; {other['name']}'s figures are much lower (see How the sources compare). Treat the lower figures as the cautious ones."}
            agreement = "disagree"
        clinical = any(c["name"].startswith(("Holze", "Vizeli", "Klaiber", "Ley", "FDA")) for c in context)
        if opts.get("confidence"):
            confidence = opts["confidence"]
        elif independent <= 1:
            confidence = "low"
        elif agreement == "disagree":
            confidence = "medium" if independent >= 3 or clinical else "low"
        elif independent >= 3 or clinical:
            confidence = "high"
        else:
            confidence = "medium"
        fixes = []
        if chosen["heavy"] is not None and chosen["strong"] is not None and chosen["heavy"] <= chosen["strong"]:
            higher = sorted(x["vals"]["heavy"][0] for x in numeric if "heavy" in x["vals"] and x["vals"]["heavy"][0] > chosen["strong"])
            fixes.append(f"The picked heavy edge ({fmt(chosen['heavy'])}) did not sit above the high band, so the next source's heavy figure is used.")
            chosen["heavy"] = higher[0] if higher else None
        if chosen["threshold"] is not None and chosen["light"] is not None and chosen["threshold"] > chosen["light"]:
            fixes.append(f"The threshold ({fmt(chosen['threshold'])}) was above where the low band starts, so it is set to the low band's start.")
            chosen["threshold"] = chosen["light"]
        # A warning line never moves later on thin evidence: if the heavy edge would rise above
        # the app's previous one, at least two sources must publish a heavy figure above it.
        old_heavy = roa.get("dose_heavy")
        if old_heavy is not None and chosen["heavy"] is not None and chosen["heavy"] > old_heavy:
            backing = [x["name"] for x in numeric if "heavy" in x["vals"] and x["vals"]["heavy"][0] > old_heavy]
            if len(backing) < 2:
                fixes.append(f"Heavy is kept at the app's previous {fmt(old_heavy)} {unit}: only {len(backing)} source(s) put it higher ({fmt(chosen['heavy'])}), and a warning line is never moved later without two.")
                HEAVY_KEPT.append(f"{key} {route}: heavy {fmt(chosen['heavy'])} -> kept {fmt(old_heavy)} {unit} (backing: {', '.join(backing) or 'none'})")
                chosen["heavy"] = old_heavy
                if chosen["strong"] is not None and chosen["strong"] > old_heavy:
                    fixes.append(f"The high band's start is capped at the same {fmt(old_heavy)} {unit}.")
                    chosen["strong"] = old_heavy
        opts = {**opts, "note":" ".join([*fixes, *([opts["note"]] if opts.get("note") else [])])}
        heavy = chosen["heavy"]
        bands = {
            "threshold": chosen["threshold"],
            "low": {"min": chosen["light"], "max": chosen["common"]},
            "common": {"min": chosen["common"], "max": chosen["strong"]},
            "high": {"min": chosen["strong"], "max": heavy if heavy is not None else strong_max},
            "heavy": heavy,
        }
        # sanity: the ladder must rise
        seq = [v for v in (chosen["threshold"], chosen["light"], chosen["common"], chosen["strong"], heavy) if v is not None]
        problems = [] if all(a <= b for a, b in zip(seq, seq[1:])) else ["ladder does not rise"]
        if chosen["light"] is not None and chosen["common"] is not None and chosen["light"] >= chosen["common"]:
            problems.append("low.min >= common.min")
        notes = []
        if independent <= 1:
            notes.append("No second source publishes doses for this route in a comparable unit, so PsychonautWiki's current bands are used as they are.")
        elif opts.get("keep") != "PsychonautWiki":
            notes.append("Each band edge is the median of the sources (with two sources: PsychonautWiki's figure when they are within 25%, otherwise the lower one).")
        if opts.get("note"):
            notes.append(opts["note"])
        entry = {
            "unit": unit,
            **{k: v for k, v in bands.items()},
            "sources": [{"name": x["name"], "url": x["url"], "bands_as_published": x["published"], "retrieved": RETRIEVED} for x in sources + context],
            "agreement": agreement,
            "confidence": confidence,
            "note": " ".join(notes),
        }
        if require_two and (independent < 2 or problems or not pw):
            report.append(f"SKIP {key} {route} n={independent} {problems}")
            continue
        def clean(o):
            if isinstance(o, dict):
                return {k: clean(v) for k, v in o.items()}
            if isinstance(o, float):
                return fmt(round(o, 4))
            return o
        out.setdefault(key, {})[route] = clean(entry)
        old = (roa.get("dose_threshold"), (roa.get("dose_light") or {}).get("min"), (roa.get("dose_common") or {}).get("min"), (roa.get("dose_strong") or {}).get("min"), roa.get("dose_heavy"))
        new = (chosen["threshold"], chosen["light"], chosen["common"], chosen["strong"], heavy)
        report.append(f"{key:18} {route:12} {unit:3} {agreement:17} {confidence:6} n={independent} old={old} new={tuple(fmt(round(v,4)) if v is not None else None for v in new)} {'!! ' + ', '.join(problems) if problems else ''}")
    return out, report


def rest_audit():
    idx = {}
    for k, e in tripsit.items():
        for n in [k, e.get("pretty_name", ""), *e.get("aliases", [])]:
            idx.setdefault(re.sub(r"[^a-z0-9]", "", n.lower()), k)
    rows = rest_rows()
    items = []
    for _cat, key, page in rows:
        s = by[key]
        names = [s["name"], s["key"], *s.get("common_names", [])]
        ts_key = next((idx[re.sub(r"[^a-z0-9]", "", n.lower())] for n in names if re.sub(r"[^a-z0-9]", "", n.lower()) in idx), None)
        if not ts_key:
            continue
        fd = {r.lower().replace("vapourized", "vaporized"): r.lower() for r in (tripsit[ts_key].get("formatted_dose") or {})}
        for r in s["roas"]:
            if r.get("dose_common") is None or r["route"] not in fd:
                continue
            items.append((key, r["route"], page.replace("/", "_"), r["route"], ts_key, fd[r["route"]], [], {}))
    return items


if __name__ == "__main__":
    if "--fetch" in sys.argv:
        fetch()
        sys.exit(0)
    data, report = build()
    if "--rest" in sys.argv:
        build(rest_audit(), require_two=True, out=data, report=report)
        sys.argv.remove("--rest")
    doc = {
        "version": 1,
        "generated": RETRIEVED,
        "method": "Per route, each band edge (threshold, low, common, high, heavy) was read from PsychonautWiki (live page), Erowid's dose chart and TripSit's open dataset where they publish the same route and unit. Three or more sources: the median edge. Two: PsychonautWiki's figure when within 25%, otherwise the lower, more cautious one. Clinical studies and FDA labels are listed for context and never vote. No number here was estimated; every figure comes from a source listed with it.",
        "substances": data,
    }
    if len(sys.argv) > 1:
        Path(sys.argv[1]).write_text(json.dumps(doc, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print("\n".join(report))
    print("HEAVY KEPT:\n  " + "\n  ".join(HEAVY_KEPT))
    print(len(data), "compounds,", sum(len(v) for v in data.values()), "routes")
