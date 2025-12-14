"""Alignment logic between HPG NGOs and grant opportunities."""

from collections import Counter
from typing import Iterable, List, Optional

from hpg_grant_stw.models import AlignmentResult, GrantOpportunity, NGO


def _normalize_tokens(values: Iterable[str]) -> Counter:
    tokens: Counter = Counter()
    for raw_value in values:
        for token in raw_value.lower().replace("/", " ").split():
            cleaned = token.strip(",.;:()[]{}" "\n\t").strip()
            if cleaned:
                tokens[cleaned] += 1
    return tokens


def score_alignment(ngo: NGO, grant: GrantOpportunity) -> AlignmentResult:
    ngo_tokens = _normalize_tokens(ngo.focus_areas + ngo.needs + [ngo.mission])
    grant_tokens = _normalize_tokens(grant.themes + [grant.description])

    theme_matches: List[str] = []
    overlap_score = 0.0
    for theme in grant.themes:
        token = theme.lower()
        if token in ngo_tokens:
            theme_matches.append(theme)
            overlap_score += 1.0

    region_match = ngo.region.lower() == grant.region.lower()
    region_score = 0.5 if region_match else 0.0

    description_overlap = sum((ngo_tokens & grant_tokens).values())
    description_score = min(description_overlap * 0.1, 1.0)

    score = overlap_score + region_score + description_score

    notes: List[str] = []
    if theme_matches:
        notes.append(f"Matches themes: {', '.join(theme_matches)}")
    if region_match:
        notes.append("Operates in the target region")
    if description_score > 0:
        notes.append("Mission language overlaps grant description")

    return AlignmentResult(
        ngo=ngo,
        grant=grant,
        score=score,
        theme_matches=theme_matches,
        region_match=region_match,
        notes=notes,
    )


def align(ngos: Iterable[NGO], grants: Iterable[GrantOpportunity]) -> List[AlignmentResult]:
    results: List[AlignmentResult] = []
    for ngo in ngos:
        for grant in grants:
            results.append(score_alignment(ngo, grant))

    return sorted(results, key=lambda result: result.score, reverse=True)


def filter_alignments(
    alignments: Iterable[AlignmentResult],
    min_score: float = 0.0,
    require_region_match: bool = False,
    required_theme: Optional[str] = None,
) -> List[AlignmentResult]:
    """Filter alignment results based on score and qualitative checks."""

    required_theme_normalized = required_theme.lower().strip() if required_theme else None
    filtered: List[AlignmentResult] = []
    for result in alignments:
        if result.score < min_score:
            continue
        if require_region_match and not result.region_match:
            continue
        if required_theme_normalized:
            grant_themes = [theme.lower() for theme in result.grant.themes]
            if required_theme_normalized not in grant_themes:
                continue
        filtered.append(result)

    return sorted(filtered, key=lambda result: result.score, reverse=True)


def top_for_ngo(
    ngo: NGO,
    grants: Iterable[GrantOpportunity],
    limit: int = 3,
    min_score: float = 0.0,
    require_region_match: bool = False,
) -> List[AlignmentResult]:
    """Convenience helper to fetch the highest-value alignments for one NGO."""

    all_alignments = [score_alignment(ngo, grant) for grant in grants]
    filtered = filter_alignments(
        all_alignments,
        min_score=min_score,
        require_region_match=require_region_match,
    )
    return filtered[:limit]
