"""Command line interface for HPG Grant STW."""

import argparse
import json
from pathlib import Path
from typing import Iterable, List

from hpg_grant_stw import data, matcher, scraper, writer
from hpg_grant_stw.models import AlignmentResult, DraftGrant, GrantOpportunity, NGO


def _print_ngos(ngos: Iterable[NGO]) -> None:
    for ngo in ngos:
        print(f"[{ngo.id}] {ngo.name} ({ngo.region})")
        print(f"  Mission: {ngo.mission}")
        print(f"  Focus areas: {', '.join(ngo.focus_areas)}")
        print()


def _serialize_alignment(result: AlignmentResult) -> dict:
    return {
        "ngo": result.ngo.id,
        "grant": result.grant.id,
        "score": result.score,
        "theme_matches": result.theme_matches,
        "region_match": result.region_match,
        "notes": result.notes,
    }


def _save_drafts(drafts: Iterable[DraftGrant], directory: Path) -> List[Path]:
    directory.mkdir(parents=True, exist_ok=True)
    saved_paths: List[Path] = []

    for draft in drafts:
        filename = f"{draft.alignment.ngo.id}__{draft.alignment.grant.id}.md"
        path = directory / filename
        path.write_text(draft.content)
        draft.filename = filename
        saved_paths.append(path)

    return saved_paths


def _align_and_report(ngos: Iterable[NGO], grants: Iterable[GrantOpportunity]) -> List[AlignmentResult]:
    results = matcher.align(ngos, grants)
    print("Top matches:")
    for result in results:
        print(
            f"- NGO {result.ngo.name} <> {result.grant.name}: "
            f"score {result.score:.2f} | themes {', '.join(result.theme_matches) or 'None'}"
        )
    print()
    return results


def run_demo(output_dir: Path) -> None:
    print("Running HPG Grant STW demo pipeline...\n")
    ngos = data.HPG_NGOS
    _print_ngos(ngos)

    grants = list(scraper.scrape())
    print(f"Loaded {len(grants)} grant opportunities from demo source.\n")

    alignments = _align_and_report(ngos, grants)
    drafts = writer.batch_build(alignments)
    saved = _save_drafts(drafts, output_dir)

    print("Drafts generated:")
    for path in saved:
        print(f"- {path}")
    print()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="HPG Grant Seeker/Tracker/Writer (HPG Grant STW)")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("output"),
        help="Directory to store drafted grant markdown files.",
    )

    subparsers = parser.add_subparsers(dest="command")

    subparsers.add_parser("list-ngos", help="List configured HPG NGOs.")

    scrape_parser = subparsers.add_parser("scrape", help="Scrape grant opportunities.")
    scrape_parser.add_argument("--source", default="demo", help="Which source to scrape (default: demo).")

    align_parser = subparsers.add_parser("align", help="Score NGO <> grant matches and output JSON.")
    align_parser.add_argument("--source", default="demo", help="Which source to scrape (default: demo).")

    write_parser = subparsers.add_parser("write", help="Generate draft grants for top matches.")
    write_parser.add_argument("--source", default="demo", help="Which source to scrape (default: demo).")
    write_parser.add_argument("--max", type=int, default=5, help="Maximum drafts to generate.")

    parser.add_argument(
        "--demo",
        action="store_true",
        help="Run the full demo pipeline: list NGOs, scrape demo grants, align, and write drafts.",
    )

    return parser


def main(argv: List[str] | None = None) -> None:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.demo:
        run_demo(args.output)
        return

    ngos = data.HPG_NGOS

    if args.command == "list-ngos":
        _print_ngos(ngos)
        return

    if args.command == "scrape":
        grants = list(scraper.scrape(args.source))
        for grant in grants:
            print(f"[{grant.id}] {grant.name} | {grant.funder} | {grant.deadline} | {grant.region}")
        return

    if args.command == "align":
        grants = list(scraper.scrape(args.source))
        alignments = matcher.align(ngos, grants)
        print(json.dumps([_serialize_alignment(result) for result in alignments], indent=2))
        return

    if args.command == "write":
        grants = list(scraper.scrape(args.source))
        alignments = matcher.align(ngos, grants)
        drafts = writer.batch_build(alignments, max_results=args.max)
        saved_paths = _save_drafts(drafts, args.output)
        print("Drafts saved:")
        for path in saved_paths:
            print(f"- {path}")
        return

    parser.print_help()


if __name__ == "__main__":  # pragma: no cover
    main()
