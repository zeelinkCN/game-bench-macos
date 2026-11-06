#!/usr/bin/env python3
"""Build the private bundled library from the owner's two authorized backups."""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEST = Path(os.environ.get("GAMEBENCH_LIBRARY_DIR", ROOT / "Resources" / "Games"))
ROMS = DEST / "owned"
REPOSITORIES = [
    {
        "path": ROOT / ".cache" / "nesrom",
        "url": "https://github.com/mengfei523060/nesrom",
    },
    {
        "path": ROOT / ".cache" / "nesRoms2",
        "url": "https://github.com/tomiaa12/nesRoms",
    },
]

# Ordered from broad Chinese nostalgia lists and forum recollections. One clean-looking
# edition per rule is promoted; every other edition remains searchable in the library.
FEATURED = [
    ("超级玛丽", r"^(超级玛丽1|超级玛莉|超级玛丽|超级马里奥兄弟(?:1)?|超级玛利欧兄弟)$"),
    ("魂斗罗", r"^(魂斗罗1|魂斗罗|魂斗罗 ?\(简\))$"),
    ("赤色要塞", r"^赤色要塞"),
    ("雪人兄弟", r"^雪人兄弟(?:\s*\(简\))?$"),
    ("坦克大战", r"^坦克大战(?:\s*\(简\))?$"),
    ("松鼠大作战", r"^松鼠大作战(?:1|\s*\(简\))?$"),
    ("双截龙2", r"^双截龙2(?:\s*-\s*复仇\s*\(简\))?$"),
    ("热血物语", r"^热血物语(?:\s*\(简\)|中文版)?$"),
    ("热血足球", r"^热血足球$"),
    ("热血篮球", r"^热血篮球_?$"),
    ("冒险岛", r"^(冒险岛1|高桥名人的冒险岛\s*\(繁\))$"),
    ("忍者神龟", r"^忍者神龟2(?:\s*\(修正版\)\s*\(简\))?$"),
    ("沙罗曼蛇", r"^沙罗曼蛇(?:1)?$"),
    ("绿色兵团", r"^绿色兵团"),
    ("俄罗斯方块", r"^俄罗斯方块"),
    ("炸弹人", r"^(炸弹人1|炸弹人|轰炸超人)"),
    ("赤影战士", r"^赤影战士(?:_|\s*\(v[^)]*\)|\s*\(小字版\)\s*\(简\))?$"),
    ("忍者龙剑传", r"^忍者龙剑传1$"),
    ("洛克人", r"^洛克人1$"),
    ("古巴战士", r"^(古巴战士|古巴战争)"),
    ("快打旋风", r"^快打旋风(?:\s*\(简\)|中文版)?$"),
    ("三目童子", r"^三目童子"),
    ("星之卡比", r"^星之卡比"),
    ("马戏团", r"^马戏团"),
    ("气球大战", r"^气球大战"),
    ("淘金者", r"^(淘金者|挖金)"),
    ("影子传说", r"^影子传说"),
    ("魔界村", r"^魔界村"),
    ("成龙踢馆", r"^(成龙踢馆|成龙之龙)"),
    ("吞食天地2", r"^吞食天地2\(j\)$"),
    ("封神榜", r"^封神榜"),
    ("最终幻想", r"^最终幻想1"),
    ("勇者斗恶龙", r"^勇者斗恶龙3"),
    ("火焰纹章", r"^(火焰纹章|圣火徽章)"),
    ("踢王", r"^踢王"),
    ("小蜜蜂", r"^(小蜜蜂|大蜜蜂)"),
    ("大力水手", r"^大力水手"),
    ("敲冰块", r"^(敲冰块|打冰块)"),
    ("大金刚", r"^大金刚"),
    ("1943", r"^1943"),
]

# These files load in the bundled FCEUmm core but did not produce a non-blank
# frame during the automated boot-and-Start smoke test. Keep the owner's backup
# visible while labeling the compatibility status honestly.
KNOWN_CORE_ISSUES = {
    "8c2d24803049a9a834a81050137cab17734eec6943e3a3a3ab41946796768c94",
    "3e498dadded6b89cb3c2ecb84a25bd1fc5df23e2cecf52dcefe844ad8623d69d",
    "39d25922328d33e322eb3c606914daee70863ee313270d97acd47d1243393db0",
    "236581677cd3ed07e70121618cb055219c1ba7df32d749b88167a2fec2993d48",
    "636feaf63bd3b6e683fa8edcbfe26ac7445719d8aba075d66b73ba9525519c95",
    "1d6d1f710eb2d67e497f7dba9b79fcfa6f8a5d265bccac9618d7de70462f3354",
    "ef26e93568395b2b7b026033b22627c221409a157ffb66709084a1cdb5895754",
    "d9c0a056c7ef24d1c94675e49be85b7e284cdf2c82d439bf161cafbc8f56cd7f",
    "c49c9f0d527d197ad10a06d481d41a2eb17249b164342efbaffa1bdf76977ba5",
    "93912bd85334c7c9be304f15c4322541f01adf3b2d8b6f6721e670896a4a517b",
    "1791d519e1046d3fa834650b0dde96b389bb4195ec5807676e18728f8a5e0f55",
    "f2fa5c9e40dc68e25fc9d9a4d5f2d5c9179c393d16c0d4e76f843aa17a6df981",
    "cc29597551bc7bb74d5adbde50996f49be536eb8f2003667d8588aae3d09056d",
}


def commit(repo: Path) -> str:
    return subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()


def title_score(title: str) -> tuple[int, int, int, int, str]:
    noisy = ("无敌", "无限", "大跳", "改版", "变态", "hack", "金手指", "隐藏", "隐形", "30条命", "枪林弹雨", "龙珠版", "格斗")
    return (
        0 if any(word in title.lower() for word in noisy) else 1,
        0 if title.lower().startswith("z___") else 1,
        1 if any(mark in title for mark in ("(简)", "（简）", "简体", "汉化", "中文版", "(繁)", "（繁）")) else 0,
        -abs(len(title) - 6),
        title,
    )


def main() -> None:
    if DEST.exists() and any(DEST.iterdir()):
        raise SystemExit(f"Refusing to overwrite non-empty destination: {DEST}")
    ROMS.mkdir(parents=True, exist_ok=True)

    by_hash: dict[str, list[dict[str, object]]] = {}
    sources = []
    path_count = 0
    for repo in REPOSITORIES:
        root = repo["path"]
        if not root.is_dir():
            raise SystemExit(f"Missing clone: {root}")
        repo_commit = commit(root)
        repo_unique: set[str] = set()
        for path in root.rglob("*"):
            if not path.is_file() or ".git" in path.parts:
                continue
            with path.open("rb") as stream:
                header = stream.read(4)
            if header not in (b"NES\x1a", b"UNIF"):
                continue
            data = path.read_bytes()
            digest = hashlib.sha256(data).hexdigest()
            repo_unique.add(digest)
            path_count += 1
            title = path.stem if path.suffix.lower() == ".nes" else path.name
            by_hash.setdefault(digest, []).append(
                {"path": path, "title": title, "url": repo["url"], "commit": repo_commit}
            )
        sources.append({"url": repo["url"], "commit": repo_commit, "uniqueROMs": len(repo_unique)})

    games = []
    for digest, copies in by_hash.items():
        best = max(copies, key=lambda item: title_score(str(item["title"])))
        title = str(best["title"]).strip()
        source_path = Path(best["path"])
        output = ROMS / f"{digest}.nes"
        shutil.copyfile(source_path, output)
        game = {
            "id": "nes-" + digest,
            "title": title,
            "system": "nes",
            "filename": "owned/" + output.name,
            "favorite": False,
            "addedAt": 0,
            "playCount": 0,
            "isDemo": False,
            "bundled": True,
            "source": str(best["url"]),
            "author": "用户授权备份",
            "sha256": digest,
            "distribution": "Private bundle imported with repository owner's authorization",
            "sourceNames": sorted({str(item["title"]) for item in copies}),
        }
        if digest in KNOWN_CORE_ISSUES:
            game["compatibilityNote"] = "当前核心启动后未检测到有效画面；备份已保留"
        lower = title.lower()
        if any(mark in lower for mark in ("(简)", "（简）", "简体", "汉化", "中文版", "(ch)", "[ch]")):
            game["language"] = "zh-label"
            game["languageEvidence"] = "仓库文件名标注为简体中文或汉化版本"
        elif any(mark in lower for mark in ("(繁)", "（繁）", "繁体", "繁體", "日繁")):
            game["language"] = "zh-label"
            game["languageEvidence"] = "仓库文件名标注为繁体中文版本"
        games.append(game)

    used: set[str] = set()
    for rank, (_, pattern) in enumerate(FEATURED, start=1):
        candidates = [g for g in games if g["id"] not in used and re.search(pattern, str(g["title"]), re.I)]
        if not candidates:
            continue
        chosen = max(candidates, key=lambda g: title_score(str(g["title"])))
        chosen["featuredRank"] = rank
        used.add(str(chosen["id"]))

    games.sort(key=lambda game: (game.get("featuredRank", 9999), str(game["title"])))
    (DEST / "catalog.json").write_text(json.dumps(games, ensure_ascii=False, indent=2) + "\n")
    (DEST / "sources.json").write_text(
        json.dumps(
            {
                "authorization": "Repository owner explicitly authorized importing all game resources into this private app.",
                "repositories": sources,
                "inputPaths": path_count,
                "uniqueROMs": len(games),
                "duplicatesRemoved": path_count - len(games),
                "featuredGames": len(used),
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n"
    )
    print(f"Installed {len(games)} unique NES games; removed {path_count-len(games)} duplicate paths; featured {len(used)} classics")


if __name__ == "__main__":
    main()
