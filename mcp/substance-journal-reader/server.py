"""Substance Journal reader: read-only context for a local or cloud AI with a limited context window.

It never touches the journal database. It reads the small text files the Substance Journal app
writes (Settings > Summary for an AI > Keep the folder up to date): a profile, a page per month and
a fact sheet per experience, all calculated by the app (potency, estimated curve, tolerance), so the
AI explains numbers instead of working them out. Every tool returns a bounded amount of text.
"""
from __future__ import annotations

import json
import os
import re
from pathlib import Path

try:
    from mcp.server.mcpserver import MCPServer as FastMCP  # mcp 2.x
except ImportError:
    from mcp.server.fastmcp import FastMCP  # mcp 1.x

GUIDE = """How to use the journal records (read this once):

Layers - start small, go deeper only when needed:
1. profile: one page. What is used, how often, last use, tolerance and its direction, last week.
2. month: one page per month. Every day, totals, days without use.
3. experience: one fact sheet per experience. Every dose with potency and product, the estimated curve
   (when it is noticeable, peaks and fades), overlaps between compounds, tolerance going in, other use in
   the 7 days before, notes and ratings with times.
Tools to find things: list_experiences, find (search notes and doses), doses (one compound over time),
tolerance, compare_months. Every tool takes max_tokens; keep it small and ask again for more.

Answering well:
- The numbers (potency, curve times, tolerance) are the app's model estimates from published ranges, not
  measurements. Say "estimated".
- For a problem ("I felt bad on the 28th"): open that experience, then the profile and the 7 days before
  ("Going in"), look at notes and ratings with times against the curve, and say what the data shows and
  what it cannot show. Say plainly when the log is thin or the dose or time was an estimate.
- Never say a dose, mix or plan is safe, and never recommend an amount to take. General harm-reduction
  tips are fine (leave time between doses, drink water, do not use alone, take tolerance breaks, do not mix
  without checking an interaction source, do not drive), pointing to the app's reference ranges for numbers.
- For severe or worrying symptoms (trouble breathing, chest pain, confusion, seizure, unresponsive,
  very high temperature) tell the person to get urgent medical help now instead of analysing the log.
- Do not diagnose. Suggest a clinician for ongoing concerns; the app can export a report for them."""

mcp = FastMCP(
    "substance-journal-reader",
    instructions=(
        "Read-only access to the user's substance journal as small, pre-calculated text pages. Call guide first "
        "the first time, then start with profile and go deeper only as needed. Report numbers as estimates. "
        "Never call anything safe and never advise on amounts."
    ),
)


def root() -> Path:
    env = os.environ.get("SUBSTANCE_JOURNAL_DIGEST")
    if env:
        return Path(env)
    return Path.home() / "Documents" / "Substance Journal digest"


def _missing() -> str:
    return (
        f"No journal digest found at {root()}. In the Substance Journal app open Settings > Summary for an AI "
        "and turn on 'Keep the folder up to date' (or press Write now). Set SUBSTANCE_JOURNAL_DIGEST to use another folder."
    )


def _people() -> list[Path]:
    r = root()
    if not r.is_dir():
        return []
    return sorted(d for d in r.iterdir() if d.is_dir() and (d / "profile.md").exists())


def _dir(person: str) -> tuple[Path | None, str]:
    people = _people()
    if not people:
        return None, _missing()
    if person:
        want = re.sub(r"[^a-z0-9]+", "-", person.lower()).strip("-")
        for d in people:
            if d.name == want or d.name.startswith(want):
                return d, ""
        return None, "No such person. Available: " + ", ".join(d.name for d in people)
    if len(people) > 1:
        return None, "More than one person in the journal. Pass person=one of: " + ", ".join(d.name for d in people)
    return people[0], ""


def _cap(text: str, max_tokens: int) -> str:
    limit = max(200, int(max_tokens) * 4)
    if len(text) <= limit:
        return text
    cut = text[:limit].rsplit("\n", 1)[0]
    return cut + "\n[Cut to fit max_tokens. Ask for a narrower range, or raise max_tokens.]"


def _index(folder: Path) -> list[dict]:
    try:
        return json.loads((folder / "index.json").read_text(encoding="utf-8")).get("experiences", [])
    except (OSError, ValueError):
        return []


def _read(folder: Path, rel: str) -> str:
    try:
        return (folder / rel).read_text(encoding="utf-8")
    except OSError:
        return ""


@mcp.tool()
def guide() -> str:
    """How the records are laid out and how to answer well from them. Call this first."""
    return GUIDE


@mcp.tool()
def list_people() -> str:
    """The people whose journals are available."""
    people = _people()
    return ", ".join(d.name for d in people) if people else _missing()


@mcp.tool()
def profile(person: str = "", max_tokens: int = 1500) -> str:
    """One page: what is used, how often, last use, tolerance and direction, the last 7 days, the latest experiences."""
    folder, err = _dir(person)
    if folder is None:
        return err
    return _cap(_read(folder, "profile.md"), max_tokens)


@mcp.tool()
def month(month: str = "", person: str = "", max_tokens: int = 2500) -> str:
    """One month day by day with totals (month as YYYY-MM; empty for the latest month)."""
    folder, err = _dir(person)
    if folder is None:
        return err
    months = sorted(p.stem for p in (folder / "months").glob("*.md")) if (folder / "months").is_dir() else []
    if not months:
        return "No months logged yet."
    chosen = month.strip() or months[-1]
    if chosen not in months:
        return f"No page for {chosen}. Months with data: {', '.join(months)}"
    return _cap(_read(folder, f"months/{chosen}.md"), max_tokens)


@mcp.tool()
def list_experiences(start: str = "", end: str = "", substance: str = "", limit: int = 20, person: str = "") -> str:
    """Experiences newest first as one line each (date YYYY-MM-DD for start and end; substance by name). Use experience() to open one."""
    folder, err = _dir(person)
    if folder is None:
        return err
    rows = []
    for e in _index(folder):
        if start and e["date"] < start:
            continue
        if end and e["date"] > end:
            continue
        if substance and substance.lower() not in [s.lower() for s in e["substances"]]:
            continue
        title = f' "{e["title"]}"' if e.get("title") else ""
        rows.append(f'{e["date"]} {e["time"]}{title} | {", ".join(e["substances"])} | {e["doses"]} doses | ~{e["tokens"]} tokens | id {e["id"][:8]}')
    if not rows:
        return "No experiences match."
    shown = rows[: max(1, min(int(limit), 100))]
    more = f"\n... {len(rows) - len(shown)} more; narrow the dates or raise limit." if len(rows) > len(shown) else ""
    return "\n".join(shown) + more


@mcp.tool()
def experience(which: str = "latest", person: str = "", max_tokens: int = 2500) -> str:
    """One experience's full fact sheet: 'latest', a date YYYY-MM-DD (every experience that day) or an id from list_experiences."""
    folder, err = _dir(person)
    if folder is None:
        return err
    index = _index(folder)
    if not index:
        return "No experiences logged yet."
    key = which.strip().lower()
    if key in ("", "latest"):
        picked = index[:1]
    else:
        picked = [e for e in index if e["date"] == key] or [e for e in index if e["id"].lower().startswith(key)]
    if not picked:
        return "No experience matches. Use list_experiences to find one."
    text = "\n\n".join(_read(folder, e["path"]) for e in picked)
    return _cap(text, max_tokens)


@mcp.tool()
def find(text: str, limit: int = 8, person: str = "") -> str:
    """Search notes, doses, products and ratings across everything for a word or phrase. Returns short snippets with the date and file."""
    folder, err = _dir(person)
    if folder is None:
        return err
    needle = text.strip().lower()
    if not needle:
        return "Give a word or phrase to search for."
    hits = []
    for e in _index(folder):
        for n, line in enumerate(_read(folder, e["path"]).splitlines(), 1):
            if needle in line.lower() and not line.startswith("#"):
                hits.append(f'{e["date"]} {e["time"]} ({e["path"]}:{n}) {line.strip()[:220]}')
    if not hits:
        return "No matches."
    shown = hits[: max(1, min(int(limit), 50))]
    more = f"\n... {len(hits) - len(shown)} more matches; make the search more specific or raise limit." if len(hits) > len(shown) else ""
    return "\n".join(shown) + more


@mcp.tool()
def doses(substance: str, start: str = "", end: str = "", limit: int = 40, person: str = "") -> str:
    """Every dose of one compound (by name) over a date range, with potency and notes, newest first."""
    folder, err = _dir(person)
    if folder is None:
        return err
    name = substance.strip().lower()
    if not name:
        return "Give a compound name."
    rows = []
    for e in _index(folder):
        if start and e["date"] < start:
            continue
        if end and e["date"] > end:
            continue
        if name not in [s.lower() for s in e["substances"]]:
            continue
        section = _read(folder, e["path"]).split("## Doses", 1)[-1].split("\n## ", 1)[0]
        for line in section.splitlines():
            m = re.match(r"- (\d\d:\d\d) \(\+[^)]*\) ([^,]+),", line)
            if m and m.group(2).strip().lower() == name:
                rows.append(f'{e["date"]} {line[2:]}')
    if not rows:
        return "No doses of that compound in that range."
    shown = rows[: max(1, min(int(limit), 200))]
    more = f"\n... {len(rows) - len(shown)} more; narrow the dates or raise limit." if len(rows) > len(shown) else ""
    return "\n".join(shown) + more


@mcp.tool()
def tolerance(person: str = "") -> str:
    """Where tolerance stands for each compound used, with its direction (rising, steady, falling), last use and counts."""
    folder, err = _dir(person)
    if folder is None:
        return err
    lines = [ln for ln in _read(folder, "profile.md").splitlines() if ln.startswith("- ") and "tolerance" in ln]
    return "\n".join(lines) if lines else "No tolerance information (nothing used recently)."


@mcp.tool()
def compare_months(a: str, b: str, person: str = "") -> str:
    """Totals for two months side by side (YYYY-MM each): doses, days used, per-compound totals."""
    folder, err = _dir(person)
    if folder is None:
        return err
    out = []
    for m in (a.strip(), b.strip()):
        text = _read(folder, f"months/{m}.md")
        if not text:
            out.append(f"{m}: no data")
            continue
        head = text.split("\n", 2)[1] if "\n" in text else ""
        totals = text.split("## Totals", 1)[-1].split("\n## ", 1)[0].strip()
        out.append(f"{m}: {head}\n{totals}")
    return "\n\n".join(out)


if __name__ == "__main__":
    mcp.run()
