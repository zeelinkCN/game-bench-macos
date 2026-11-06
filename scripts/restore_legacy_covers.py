#!/usr/bin/env python3
"""Restore the numbered cover mapping omitted from the legacy ROM repository."""

from __future__ import annotations

import html
import json
import os
from pathlib import Path
import re
import shutil


ROOT = Path(__file__).resolve().parents[1]
LIBRARY = Path(os.environ.get("GAMEBENCH_LIBRARY_DIR", ROOT / "Resources" / "Games"))
SCRIPT = ROOT / ".cache" / "kuangyx-game.js"
IMAGES = ROOT / ".cache" / "nesRoms2" / "img"
SOURCE_PAGE = "https://kuangyx.cn/pages/game.html"

FAMILY_FALLBACKS = {
    "勇者斗恶龙3_(J)": "831a.png",
    "吞食天地2": "733a.png",
    "热血！街头篮球 - 加油吧！灌篮高手们！ (简)": "942a.png",
    "皮卡丘": "307a.png",
    "风云 (简)": "619a.png",
    "馬里奧醫生": "546a.png",
    "龙珠英雄": "118a.png",
}


PATTERN = re.compile(
    r"\{id:`([^`]*)`,title:`([^`]*)`,cover:`([^`]*)`,image:`([^`]*)`,"
    r"language:`([^`]*)`,type:`([^`]*)`,source:`([^`]*)`,comment:`([^`]*)`,"
    r"location:`([^`]*)`,size:`([^`]*)`,publisher:`([^`]*)`,url:`([^`]*)`\}"
)


def main() -> None:
    entries = []
    for values in PATTERN.findall(SCRIPT.read_text()):
        keys = ("legacyID", "title", "cover", "image", "language", "type", "translator", "comment", "location", "size", "publisher", "url")
        entry = {key: html.unescape(value) for key, value in zip(keys, values)}
        entry["size"] = int(entry["size"])
        entries.append(entry)
    if len(entries) < 390:
        raise SystemExit(f"Legacy mapping incomplete: {len(entries)} entries")

    target_images = LIBRARY / "legacy-images"
    if not target_images.exists():
        shutil.copytree(IMAGES, target_images)

    games = json.loads((LIBRARY / "catalog.json").read_text())
    by_name: dict[str, list[dict]] = {}
    for entry in entries:
        by_name.setdefault(entry["title"], []).append(entry)
        by_name.setdefault(entry["url"], []).append(entry)

    used_ids: set[str] = set()
    restored = []
    for game in games:
        names = [game["title"], *game.get("sourceNames", [])]
        candidates = []
        for name in names:
            candidates.extend(by_name.get(name, []))
        size = (LIBRARY / game["filename"]).stat().st_size
        exact = [item for item in candidates if item["size"] == size and item["legacyID"] not in used_ids]
        if not exact:
            continue
        entry = exact[0]
        if not (target_images / entry["cover"]).is_file():
            continue
        game["cover"] = "legacy-images/" + entry["cover"]
        game["legacyCoverID"] = entry["legacyID"]
        used_ids.add(entry["legacyID"])
        restored.append({"gameID": game["id"], **entry})

    for game in games:
        if game.get("cover") or game["title"] not in FAMILY_FALLBACKS:
            continue
        filename = FAMILY_FALLBACKS[game["title"]]
        if (target_images / filename).is_file():
            game["cover"] = "legacy-images/" + filename
            game["legacyCoverMatch"] = "同一作品的其他版本封面"

    (LIBRARY / "catalog.json").write_text(json.dumps(games, ensure_ascii=False, indent=2) + "\n")
    (LIBRARY / "legacy-cover-index.json").write_text(
        json.dumps(
            {
                "source": SOURCE_PAGE,
                "description": "Recovered numbered cover mapping from the legacy site's published JavaScript bundle.",
                "mappedGames": restored,
                "allPublishedEntries": entries,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n"
    )
    print(f"Restored original numbered covers: {len(restored)}/{len(games)}; preserved {len(list(target_images.glob('*.png')))} legacy images")


if __name__ == "__main__":
    main()
