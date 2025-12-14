"""Scraper utilities.

In this offline demo implementation the scraper returns structured grant data
from the built-in dataset. The module is intentionally designed to be easily
extended with HTTP requests or API integrations when network access is
available.
"""

from typing import Iterable, List

from hpg_grant_stw import data
from hpg_grant_stw.models import GrantOpportunity


def available_sources() -> List[str]:
    return ["demo"]


def scrape(source: str = "demo") -> Iterable[GrantOpportunity]:
    """Yield grant opportunities from the provided source.

    When running in disconnected environments, the ``demo`` source is a
    dependency-free set of grants that can still be matched against NGOs.
    """

    normalized = source.lower().strip()
    if normalized != "demo":
        raise ValueError(
            f"Unsupported source '{source}'. Available sources: {', '.join(available_sources())}"
        )

    yield from data.DEMO_GRANTS
