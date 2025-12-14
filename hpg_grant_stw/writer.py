"""Grant draft generation utilities."""

from textwrap import dedent
from typing import Iterable, List

from hpg_grant_stw.models import AlignmentResult, DraftGrant


INTRO = (
    "HPG Grant STW synthesizes organizational context and grant requirements into a"
    " ready-to-edit draft. Each section is concise so program leads can quickly"
    " tailor it before submission."
)


SECTION_TEMPLATE = """
# {grant_name}

**Funder:** {funder}
**Deadline:** {deadline}
**Amount Range:** {amount_min} - {amount_max}
**URL:** {url}

## Cover Letter
{cover_letter}

## Organizational Summary
{org_summary}

## Problem Statement
{problem_statement}

## Proposed Activities & Milestones
{activities}

## Measurement & Learning
{measurement}

## Budget Snapshot
{budget}

## Attachments to Prepare
{attachments}
"""


def _format_list(values: Iterable[str]) -> str:
    bullet_lines = [f"- {value}" for value in values]
    return "\n".join(bullet_lines)


def build_draft(alignment: AlignmentResult) -> DraftGrant:
    ngo = alignment.ngo
    grant = alignment.grant

    cover_letter = dedent(
        f"""
        Dear {grant.funder} Team,

        On behalf of {ngo.name}, we are pleased to submit our proposal for the
        {grant.name}. Our organization operates in {ngo.region} and focuses on
        {', '.join(ngo.focus_areas)}. We see strong alignment with your
        priorities of {', '.join(grant.themes)} and look forward to partnering
        to scale our impact.
        """
    ).strip()

    org_summary = dedent(
        f"""
        {ngo.name} is an HPG member organization with an annual budget of
        {ngo.annual_budget}. Our mission is: "{ngo.mission}". We specialize in
        {', '.join(ngo.differentiators)}.
        """
    ).strip()

    problem_statement = dedent(
        f"""
        Communities in {ngo.region} face persistent challenges related to
        {', '.join(ngo.needs)}. Without investment, these barriers will limit
        equitable progress toward the Sustainable Development Goals.
        """
    ).strip()

    activities = dedent(
        f"""
        We will deploy a phased plan that builds on our existing programs:
        - Launch an inception workshop with local partners to confirm needs.
        - Implement core activities around {', '.join(ngo.focus_areas)} tailored
          to the grant's emphasis on {', '.join(grant.themes)}.
        - Stand up monitoring systems and community feedback loops to adapt in
          real time.
        - Share learnings with HPG peers to multiply impact.
        """
    ).strip()

    measurement = dedent(
        """
        We will track reach, outcome adoption, and sustainability. Example KPIs
        include number of households served, percentage improvement against the
        baseline, and cost per beneficiary. We will generate quarterly learning
        briefs for the funder.
        """
    ).strip()

    budget = dedent(
        f"""
        Requested support: {grant.amount_range[0]} - {grant.amount_range[1]}.
        Funds will prioritize frontline delivery, local staffing, community
        governance, and third-party evaluation.
        """
    ).strip()

    attachments = _format_list(
        [
            "Board roster and bios",
            "Audited financials",
            "Letters of support from community partners",
            "Workplan Gantt chart",
        ]
    )

    content = SECTION_TEMPLATE.format(
        grant_name=grant.name,
        funder=grant.funder,
        deadline=grant.deadline,
        amount_min=grant.amount_range[0],
        amount_max=grant.amount_range[1],
        url=grant.url,
        cover_letter=cover_letter,
        org_summary=org_summary,
        problem_statement=problem_statement,
        activities=activities,
        measurement=measurement,
        budget=budget,
        attachments=attachments,
    )

    return DraftGrant(alignment=alignment, content=content)


def batch_build(alignments: Iterable[AlignmentResult], max_results: int = 5) -> List[DraftGrant]:
    drafts: List[DraftGrant] = []
    for alignment in alignments:
        if len(drafts) >= max_results:
            break
        drafts.append(build_draft(alignment))
    return drafts
