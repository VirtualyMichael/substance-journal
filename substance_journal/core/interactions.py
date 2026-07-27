from __future__ import annotations

from dataclasses import dataclass

from substance_journal.core.database import Store
from substance_journal.core.models import Interaction

# Risk levels that are just informational (TripSit's "Low Risk & ..." tiers) and
# shouldn't interrupt the user with a warning banner.
_LOW_RISK_PREFIX = "Low Risk"


@dataclass(frozen=True)
class InteractionWarning:
    other_substance_key: str
    interaction: Interaction


def is_notable_risk(risk_level: str) -> bool:
    return not risk_level.startswith(_LOW_RISK_PREFIX)


def check_new_ingestion(store: Store, consumer: str, new_substance_key: str) -> list[InteractionWarning]:
    """Check the new substance against every other substance already logged in the
    consumer's currently open session. Only sessions (not calendar days) are used as
    the "still active" scope, since a session represents one continuous experience."""
    session = store.get_open_session(consumer)
    if session is None:
        return []

    active_keys = {
        ingestion.substance_key
        for ingestion in store.list_ingestions_for_session(session.id)
        if ingestion.substance_key != new_substance_key
    }

    warnings = []
    for other_key in sorted(active_keys):
        interaction = store.lookup_interaction(other_key, new_substance_key)
        if interaction is not None and is_notable_risk(interaction.risk_level):
            warnings.append(InteractionWarning(other_substance_key=other_key, interaction=interaction))
    return warnings
