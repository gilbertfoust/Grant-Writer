from dataclasses import dataclass, field
from typing import List, Optional, Tuple


@dataclass
class NGO:
    """Represents an HPG NGO partner."""

    id: str
    name: str
    region: str
    mission: str
    focus_areas: List[str]
    annual_budget: str
    needs: List[str]
    differentiators: List[str]


@dataclass
class GrantOpportunity:
    """A grant opportunity sourced from public listings or APIs."""

    id: str
    name: str
    funder: str
    description: str
    themes: List[str]
    region: str
    amount_range: Tuple[str, str]
    deadline: str
    url: str


@dataclass
class AlignmentResult:
    """Score and rationale for an NGO-grant match."""

    ngo: NGO
    grant: GrantOpportunity
    score: float
    theme_matches: List[str] = field(default_factory=list)
    region_match: bool = False
    notes: List[str] = field(default_factory=list)

    def summary(self) -> str:
        theme_info = ", ".join(self.theme_matches) if self.theme_matches else "None"
        note_text = "; ".join(self.notes) if self.notes else "No alignment notes"
        return (
            f"Score: {self.score:.2f}\n"
            f"Themes: {theme_info}\n"
            f"Region match: {'yes' if self.region_match else 'no'}\n"
            f"Notes: {note_text}"
        )


@dataclass
class DraftGrant:
    """A draft proposal body for a matched NGO and grant opportunity."""

    alignment: AlignmentResult
    content: str
    filename: Optional[str] = None
