"""Extract read-only input for Kanki's E1 importer from a synthetic .apkg."""

import argparse
import json
import sqlite3
from collections import defaultdict
from pathlib import Path

from e1_restore import package_database


def model_fields(database: sqlite3.Connection) -> dict[str, list[str]]:
    """Read actual field order, including for the incompatible model."""
    if database.execute(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'fields'"
    ).fetchone():
        models = defaultdict(list)
        for model, name in database.execute(
            "SELECT ntid, name FROM fields ORDER BY ntid, ord"
        ):
            models[str(model)].append(name)
        return dict(models)

    (raw,) = database.execute("SELECT models FROM col").fetchone()
    return {
        model_id: [field["name"] for field in sorted(model["flds"], key=lambda f: f["ord"])]
        for model_id, model in json.loads(raw).items()
    }


def extract(package: Path, *, reviewed: bool) -> dict:
    """Keep the collection's raw values, resolving NID/CID only within it."""
    with package_database(package) as database:
        models = model_fields(database)
        notes_by_id = {
            nid: dict(guid=guid, modelID=model, mod=mod, fields=fields.split("\x1f"))
            for nid, guid, model, mod, fields in database.execute(
                "SELECT id, guid, mid, mod, flds FROM notes ORDER BY id"
            )
        }
        cards = {}
        for cid, nid, ord_, due, ivl, queue in database.execute(
            "SELECT id, nid, ord, due, ivl, queue FROM cards ORDER BY id"
        ):
            card = dict(guid=notes_by_id[nid]["guid"], ord=ord_)
            if reviewed:
                card["progress"] = dict(due=due, ivl=ivl, queue=queue, reviews=[])
            cards[cid] = card
        if reviewed:
            for rid, cid, ease, ivl, last_ivl, factor, time, kind in database.execute(
                "SELECT id, cid, ease, ivl, lastIvl, factor, time, type FROM revlog ORDER BY id"
            ):
                cards[cid]["progress"]["reviews"].append(dict(
                    id=rid, ease=ease, ivl=ivl, lastIvl=last_ivl, factor=factor,
                    time=time, type=kind,
                ))
    return dict(models=models, notes=list(notes_by_id.values()), cards=list(cards.values()))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--reviewed", action="store_true")
    args = parser.parse_args()
    payload = extract(args.package, reviewed=args.reviewed)
    args.output.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")


if __name__ == "__main__":
    main()
