#!/usr/bin/env python3
"""Generate the lightweight online-store index from the private resource catalog."""

from __future__ import annotations

import json
import os
from datetime import date
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LIBRARY = Path(os.environ.get("GAMEBENCH_LIBRARY_DIR", ROOT / "Resources" / "Games"))


def ids(games, predicate):
    return [game["id"] for game in games if predicate(game)]


def has(game, *words):
    title = game["title"].lower()
    return any(word.lower() in title for word in words)


def main() -> None:
    games = json.loads((LIBRARY / "catalog.json").read_text())
    collections = [
        {"id": "childhood", "title": "童年经典", "description": "精选的小霸王与红白机回忆", "gameIDs": ids(games, lambda g: g.get("featuredRank") is not None)},
        {"id": "contra", "title": "魂斗罗系列", "description": "魂斗罗正作、中文版本与经典改版", "gameIDs": ids(games, lambda g: has(g, "魂斗罗", "魂斗羅", "contra"))},
        {"id": "mario", "title": "超级玛丽系列", "description": "超级玛丽、马里奥与水管工系列", "gameIDs": ids(games, lambda g: has(g, "超级玛丽", "超级玛莉", "马里奥", "馬里奧", "玛利欧", "mario"))},
        {"id": "hotblood", "title": "热血系列", "description": "热血物语、足球、篮球、躲避球与运动会", "gameIDs": ids(games, lambda g: has(g, "热血", "国夫"))},
        {"id": "double-dragon", "title": "双截龙系列", "description": "经典双人清版动作游戏", "gameIDs": ids(games, lambda g: has(g, "双截龙"))},
        {"id": "adventure-island", "title": "冒险岛系列", "description": "高桥名人的冒险岛", "gameIDs": ids(games, lambda g: has(g, "冒险岛"))},
        {"id": "ninja", "title": "忍者经典", "description": "忍者龙剑传、忍者神龟等动作游戏", "gameIDs": ids(games, lambda g: has(g, "忍者龙剑传", "忍者神龟"))},
    ]
    manifest = {
        "schemaVersion": 1,
        "libraryVersion": date.today().isoformat(),
        "title": "拾光游戏市场",
        "catalog": "catalog.json",
        "contentBaseURL": "https://raw.githubusercontent.com/zeelinkCN/game-bench-library/main/",
        "collections": collections,
    }
    (LIBRARY / "store.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print("Store collections:", ", ".join(f"{item['title']} {len(item['gameIDs'])}" for item in collections))


if __name__ == "__main__":
    main()
