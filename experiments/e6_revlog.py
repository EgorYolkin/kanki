"""
Export synthetic SM-2 and FSRS reviews using Anki's 26.09.3 backend.
"""

import argparse
import json
import sqlite3
import tempfile
from pathlib import Path

from anki.collection import Collection
from anki.decks import UpdateDeckConfigs
from anki.exporting import ExportAnkiPackageOptions
from anki.importing import ImportAnkiPackageOptions, ImportAnkiPackageRequest
from anki.scheduler.v3 import CardAnswer

from e1_product_input import extract


def run(source: Path, export: Path, *, use_fsrs: bool) -> None:
    with tempfile.TemporaryDirectory(prefix="kanki-e6-") as work:
        collection = Collection(str(Path(work) / "collection.anki2"))
        try:
            collection.import_anki_package(ImportAnkiPackageRequest(
                package_path=str(source), options=ImportAnkiPackageOptions(with_scheduling=True),
            ))
            deck = collection.decks.id("Kanki E1 experiment", create=False)
            assert deck is not None
            collection.decks.select(deck)
            configs = collection.decks.get_deck_configs_for_update(deck)
            collection.decks.update_deck_configs(UpdateDeckConfigs(
                target_deck_id=deck, configs=[entry.config for entry in configs.all_config], fsrs=use_fsrs,
            ))
            assert collection.decks.get_deck_configs_for_update(deck).fsrs == use_fsrs
            queue = collection.sched.get_queued_cards(fetch_limit=2).cards
            assert len(queue) == 2
            for queued, rating in zip(queue, (CardAnswer.Rating.GOOD, CardAnswer.Rating.EASY), strict=True):
                card = collection.get_card(queued.card.id)
                card.start_timer()
                collection.sched.answer_card(collection.sched.build_answer(card=card, states=queued.states, rating=rating))

            collection.sched.suspend_cards([queue[1].card.id])
            connection = sqlite3.connect(f"file:{collection.path}?mode=ro", uri=True)
            with connection:
                columns = [info[1] for info in connection.execute("PRAGMA table_info(revlog)")]
            connection.close()
            assert columns == ["id", "cid", "usn", "ease", "ivl", "lastIvl", "factor", "time", "type"]
            collection.export_anki_package(
                out_path=str(export),
                options=ExportAnkiPackageOptions(with_scheduling=True, with_media=False, legacy=True),
                limit=None,
            )
        finally:
            collection.close()

    payload = extract(export, reviewed=True)
    rows = {entry["progress"]["reviews"][0]["ease"]: entry for entry in payload["cards"]}
    assert set(rows) == {3, 4}
    assert all(entry["ord"] == 0 and len(entry["progress"]["reviews"]) == 1 for entry in rows.values())
    good = rows[3]["progress"]
    easy = rows[4]["progress"]
    assert good["queue"] == 1 and easy["queue"] == -1
    assert good["due"] > 1_000_000_000 and easy["due"] < 1_000_000_000
    assert good["reviews"][0]["ivl"] < 0 < easy["reviews"][0]["ivl"]
    export.with_suffix(".json").write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
    print(f"{export.stem}: columns={','.join(columns)}")
    for ease, entry in sorted(rows.items()):
        progress = entry["progress"]
        row = progress["reviews"][0]
        print(f"{export.stem}: ease={ease} queue={progress['queue']} due={progress['due']} "
              f"cards.ivl={progress['ivl']} revlog.ivl={row['ivl']} factor={row['factor']} type={row['type']}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path, help="E1 fixture directory outside the repository")
    args = parser.parse_args()
    for name, use_fsrs in (("sm2", False), ("fsrs", True)):
        run(args.directory / "test1.apkg", args.directory / f"{name}.apkg", use_fsrs=use_fsrs)


if __name__ == "__main__":
    main()
