#!/usr/bin/env python3
"""Capture a verified title/game frame for each bundled ROM as its card cover."""

from __future__ import annotations

import concurrent.futures
import ctypes
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import zlib


ROOT = Path(__file__).resolve().parents[1]
LIBRARY = Path(os.environ.get("GAMEBENCH_LIBRARY_DIR", ROOT / "Resources" / "Games"))
CATALOG = LIBRARY / "catalog.json"
CORES = ROOT / ".cache" / "cores"
BRIDGE = ROOT / "build" / "libGameBenchTest.dylib"
os.environ["GAMEBENCH_NO_AUDIO"] = "1"


def png_chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def write_png(path: Path, width: int, height: int, pixels) -> None:
    rows = bytearray()
    for y in range(height):
        rows.append(0)
        for x in range(width):
            value = pixels[y * width + x]
            rows.extend(((value >> 16) & 255, (value >> 8) & 255, value & 255))
    data = b"\x89PNG\r\n\x1a\n"
    data += png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    data += png_chunk(b"IDAT", zlib.compress(bytes(rows), 9))
    data += png_chunk(b"IEND", b"")
    path.write_bytes(data)


def frame(c):
    width, height = ctypes.c_uint(), ctypes.c_uint()
    pointer = c.gb_frame(ctypes.byref(width), ctypes.byref(height))
    if not pointer or not width.value or not height.value:
        return None
    count = width.value * height.value
    pixels = [pointer[index] for index in range(count)]
    return width.value, height.value, pixels


def visual_score(snapshot) -> tuple[int, int]:
    if not snapshot:
        return (0, 0)
    width, height, pixels = snapshot
    sampled = pixels[:: max(1, len(pixels) // 12000)]
    colors = len(set(sampled))
    edges = sum(1 for a, b in zip(sampled, sampled[1:]) if a != b)
    return colors, edges


def capture(game: dict) -> int:
    c = ctypes.CDLL(str(BRIDGE))
    c.gb_load.argtypes = [ctypes.c_char_p] * 5
    c.gb_load.restype = ctypes.c_bool
    c.gb_frame.argtypes = [ctypes.POINTER(ctypes.c_uint), ctypes.POINTER(ctypes.c_uint)]
    c.gb_frame.restype = ctypes.POINTER(ctypes.c_uint32)
    c.gb_set_input.argtypes = [ctypes.c_uint, ctypes.c_uint16]
    core = {"nes": "fceumm", "gameboy": "gambatte", "snes": "snes9x", "sega": "genesis_plus_gx", "arcade": "fbneo"}[game["system"]]
    saves = ROOT / "build" / "CoverSaves"
    saves.mkdir(exist_ok=True)
    args = [CORES / f"{core}_libretro.dylib", LIBRARY / game["filename"], saves, saves, game["id"]]
    if not c.gb_load(*[str(value).encode() for value in args]):
        return 2
    snapshots = []
    for block in range(10):
        for _ in range(60):
            c.gb_run()
        if block in (1, 2, 4, 7, 9):
            snapshots.append(frame(c))
    if max((visual_score(item) for item in snapshots), default=(0, 0))[0] < 3:
        for block in range(12):
            c.gb_set_input(0, (1 << 3) | (1 << 8) if block % 2 == 0 else 0)
            for _ in range(60):
                c.gb_run()
            snapshots.append(frame(c))
        c.gb_set_input(0, 0)
    best = max(snapshots, key=visual_score, default=None)
    if visual_score(best)[0] < 3:
        c.gb_unload()
        return 3
    cover = LIBRARY / "covers" / (game["sha256"] + ".png")
    cover.parent.mkdir(parents=True, exist_ok=True)
    write_png(cover, *best)
    c.gb_unload()
    return 0


def test(game: dict) -> dict:
    try:
        result = subprocess.run(
            [sys.executable, __file__, "--one", json.dumps(game, ensure_ascii=False)],
            capture_output=True,
            text=True,
            timeout=20,
        )
        return {"id": game["id"], "title": game["title"], "passed": result.returncode == 0, "code": result.returncode}
    except subprocess.TimeoutExpired:
        return {"id": game["id"], "title": game["title"], "passed": False, "code": "timeout"}


def main() -> None:
    games = json.loads(CATALOG.read_text())
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(test, games))
    passed = {item["id"] for item in results if item["passed"]}
    for game in games:
        if game["id"] in passed:
            game["cover"] = "covers/" + game["sha256"] + ".png"
        else:
            game.pop("cover", None)
    CATALOG.write_text(json.dumps(games, ensure_ascii=False, indent=2) + "\n")
    (ROOT / "build" / "cover-validation.json").write_text(json.dumps(results, ensure_ascii=False, indent=2) + "\n")
    print(f"Generated verified covers: {len(passed)}/{len(games)}")
    for item in results:
        if not item["passed"]:
            print("NO COVER:", item["title"], item["code"])


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--one":
        raise SystemExit(capture(json.loads(sys.argv[2])))
    main()
