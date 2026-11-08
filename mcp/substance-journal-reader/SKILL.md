---
name: substance-journal
description: Read a person's Substance Journal records (doses with potency, estimated curves, tolerance, notes and ratings) in small pieces, to summarise what they did, give context on a problem, or look at trends. Use when they ask about their own journal, past nights, tolerance, spend or patterns.
---

# Substance Journal

Records are small text pages already calculated by the Substance Journal app. Use the
`substance-journal-reader` tools if available; otherwise read the files in the digest folder or the pasted
summary. Start small and go deeper only as needed, so a short context window is enough.

## Layers

1. `profile`: one page. What is used, how often, last use, tolerance and direction, the last 7 days.
2. `month YYYY-MM`: day by day with totals and days without use.
3. `experience latest | YYYY-MM-DD | id`: every dose with potency, estimated curve, overlaps, tolerance going in,
   other use in the 7 days before, notes and ratings with times.
4. Finding things: `list_experiences`, `find "word"`, `doses "compound"`, `tolerance`, `compare_months a b`.
   Use small `max_tokens` and ask again for more.

## Common jobs

- **Summary of a period:** `month`, then `experience` for the notable days. Report doses, totals, days without
  use, spend if tracked, and what changed from the month before.
- **Context on a problem ("I felt awful on the 28th"):** `experience 2026-10-28`, then `profile` and read the
  "Going in" section. Line up the notes and ratings (with their times) against the curve and the overlaps.
  Say what the data shows and what it cannot show, and when doses or times were estimates.
- **Trends:** `tolerance`, `compare_months`, `doses "compound"` over a range.

## Rules

- Potency, curve times and tolerance are model estimates from published ranges, not measurements. Say "estimated".
- Never say a dose, combination or plan is safe. Never recommend an amount to take.
- General harm-reduction tips are fine: leave time between doses, drink water, do not use alone, take
  tolerance breaks, do not combine without checking an interaction source, do not drive. For numbers, point to
  the app's reference ranges rather than inventing them.
- For severe or worrying symptoms (trouble breathing, chest pain, confusion, seizure, unresponsive, very high
  temperature) say to get urgent medical help now. Do not analyse the log first.
- Do not diagnose. For ongoing concerns suggest a clinician; the app can export a report for them.
- Keep names, notes and places private: do not repeat them anywhere outside this conversation.
