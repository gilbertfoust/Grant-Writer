# HPG Grant STW (Seeker / Tracker / Writer)

HPG Grant STW is a lightweight, offline-friendly grant seeker, tracker, and
writer for HPG NGOs. It ships with demo data, alignment scoring, and proposal
draft generation so you can run the entire pipeline without external
dependencies.

## Features
- **Scrape (demo data):** Pull a curated list of major grants without relying on
  network access.
- **Track & align:** Score each HPG NGO against available grants using mission,
  region, and thematic overlap.
- **Write drafts:** Generate ready-to-edit markdown grant drafts for the top
  matches.

## Quickstart
Run the end-to-end demo, which lists NGOs, loads demo grant opportunities,
calculates alignments, and writes draft proposals to `./output`:

```bash
python -m hpg_grant_stw.cli --demo
```

### Useful commands
- List NGOs: `python -m hpg_grant_stw.cli list-ngos`
- View grants (demo source): `python -m hpg_grant_stw.cli scrape --source demo`
- Output alignments as JSON: `python -m hpg_grant_stw.cli align --source demo`
- Generate top drafts (default 5): `python -m hpg_grant_stw.cli write --max 3`

Drafts are stored as Markdown files in the directory passed to `--output`
(default: `./output`).

## Extending
- Add more NGOs in `hpg_grant_stw/data.py`.
- Implement real scraping logic in `hpg_grant_stw/scraper.py` by replacing the
  demo source with API or HTML collection.
- Adjust matching logic in `hpg_grant_stw/matcher.py` to reflect new scoring
  heuristics.
- Customize proposal language in `hpg_grant_stw/writer.py`.
