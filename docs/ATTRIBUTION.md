# Data attribution

## PsychonautWiki (CC BY-SA 4.0)

`data/substances_extra.json` (and its copy in `app/assets/data/`) is derived from
[PsychonautWiki](https://psychonautwiki.org), fetched through its public API by
`scripts/sync_substance_data.py --extra`. PsychonautWiki content is licensed
[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). Each record keeps its source page
URL, the fetch date and a licence note, and the app shows them on the compound page. Changes made:
units normalised, ranges put in min/max order, placeholder summaries removed, and tolerance text
turned into day counts. Treat that data as share-alike.

These 272 substances are **not independently audited**; the app says so on each compound. Only the nine
substances in `data/substances.json` were checked against several sources (`docs/data-audit/`).

## TripSit

Interaction pairs in `data/interactions.json` come from the TripSit combination chart.

## Importing from PsychonautWiki Journal

The importer reads the JSON export file format of the PsychonautWiki Journal app. It uses none of that
app's source code.
