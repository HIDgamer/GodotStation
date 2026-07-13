#!/usr/bin/env python3
"""DMI -> Godot asset converter.

DMI is BYOND's icon sheet format: a plain PNG whose zTXt "Description" chunk
lists icon states (name, direction count, frame count, delay), with the
actual frames packed left-to-right/top-to-bottom in the image in a fixed,
documented order. This is a generic, public file format (used by every BYOND
game, not something specific to or copyrighted by ucfss13/CM-SS13) - parsing
it is a format-compatibility concern, not a code-reuse one. See
feedback-copyright-constraint / feedback-noncommercial-fangame: reusing the
*asset files themselves* was already explicitly approved; this tool exists
to make hundreds of them usable in Godot without hand-slicing each one.

For every source .dmi this produces two files at the destination, image data
untouched:
  <name>.png        - the exact same pixel data, just re-extensioned so
                       Godot's own PNG importer picks it up as a Texture2D.
  <name>.icon.json   - parsed layout metadata (states, directions, frame
                       delays, and the pixel grid cell each frame lives at)
                       for Scripts/Core/Assets/DmiSheet.cs to slice at runtime.

Usage:
    python dmi_convert.py <source_dir> <dest_dir> [--dry-run]

Run once per source subtree (see the "included" folder list in the M2
project memory) or re-run any time ucfss13 gains new icons worth pulling in -
it's idempotent, always overwriting with a fresh parse.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image

# BYOND's fixed direction ordering per dirs count - frames in the sheet are
# laid out in exactly this order, one full pass per state.
DIR_ORDER = {
    1: ["south"],
    4: ["south", "north", "east", "west"],
    8: ["south", "north", "east", "west", "southeast", "southwest", "northeast", "northwest"],
}


class DmiParseError(Exception):
    pass


def parse_description(text: str) -> tuple[dict, list[dict]]:
    header: dict = {}
    states: list[dict] = []
    current: dict | None = None

    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue

        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip()

        if key == "state":
            current = {
                "name": value.strip('"'),
                "dirs": 1,
                "frames": 1,
                "delay": [],
                "movement": False,
                "rewind": False,
                "loop": 0,
            }
            states.append(current)
            continue

        if current is None:
            if key in ("width", "height"):
                header[key] = int(value)
            continue

        if key == "dirs":
            current["dirs"] = int(value)
        elif key == "frames":
            current["frames"] = int(value)
        elif key == "delay":
            current["delay"] = [float(v) for v in value.split(",") if v.strip()]
        elif key == "movement":
            current["movement"] = value in ("1", "true")
        elif key == "rewind":
            current["rewind"] = value in ("1", "true")
        elif key == "loop":
            try:
                current["loop"] = int(float(value))
            except ValueError:
                pass

    # BYOND defaults both to 32 when the header omits them (seen in a handful
    # of real ucfss13 files, e.g. icons/obj/pipes/regular.dmi) - not a parse
    # error, just an implicit default worth keeping explicit here.
    header.setdefault("width", 32)
    header.setdefault("height", 32)

    return header, states


def compute_layout(img_width: int, img_height: int, icon_w: int, icon_h: int, states: list[dict]) -> dict:
    if icon_w <= 0 or icon_h <= 0 or img_width % icon_w or img_height % icon_h:
        raise DmiParseError(f"image size {img_width}x{img_height} not a clean multiple of icon size {icon_w}x{icon_h}")

    columns = img_width // icon_w
    rows_available = img_height // icon_h
    index = 0
    out_states = {}

    for st in states:
        dirs = DIR_ORDER.get(st["dirs"])
        if dirs is None:
            # Non-standard dirs count (rare) - fall back to just enumerating
            # generic slots rather than guessing facing names.
            dirs = [f"dir{i}" for i in range(st["dirs"])]

        frames_by_dir: dict[str, list[list[int]]] = {}
        for d in dirs:
            cells = []
            for _f in range(st["frames"]):
                col = index % columns
                row = index // columns
                if row >= rows_available:
                    raise DmiParseError(f"state '{st['name']}' overflows sheet bounds")
                cells.append([col, row])
                index += 1
            frames_by_dir[d] = cells

        out_states[st["name"]] = {
            "dirs": st["dirs"],
            "frames": st["frames"],
            "delay": st["delay"],
            "movement": st["movement"],
            "rewind": st["rewind"],
            "loop": st["loop"],
            "framesByDir": frames_by_dir,
        }

    return {
        "width": icon_w,
        "height": icon_h,
        "columns": columns,
        "states": out_states,
    }


def convert_one(src: Path, dst_png: Path, dst_json: Path, dry_run: bool) -> None:
    with Image.open(src) as img:
        img.load()
        description = img.text.get("Description") if hasattr(img, "text") else None
        if not description:
            raise DmiParseError("no DMI Description metadata found (not a DMI or malformed)")

        header, states = parse_description(description)
        layout = compute_layout(img.width, img.height, header["width"], header["height"], states)

        if dry_run:
            return

        dst_png.parent.mkdir(parents=True, exist_ok=True)
        img.save(dst_png)

    dst_json.write_text(json.dumps(layout, indent=2), encoding="utf-8")


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 1

    src_root = Path(sys.argv[1]).resolve()
    dst_root = Path(sys.argv[2]).resolve()
    dry_run = "--dry-run" in sys.argv[3:]

    dmi_files = sorted(src_root.rglob("*.dmi"))
    if not dmi_files:
        print(f"No .dmi files found under {src_root}")
        return 1

    converted = 0
    failed = []

    for src in dmi_files:
        rel = src.relative_to(src_root)
        dst_png = dst_root / rel.with_suffix(".png")
        dst_json = dst_root / rel.parent / f"{rel.stem}.icon.json"

        try:
            convert_one(src, dst_png, dst_json, dry_run)
            converted += 1
        except DmiParseError as e:
            failed.append((rel, str(e)))
        except Exception as e:  # noqa: BLE001 - report and keep going
            failed.append((rel, f"unexpected: {e}"))

    print(f"Converted {converted}/{len(dmi_files)} icon(s) from {src_root} -> {dst_root}")
    if failed:
        print(f"\n{len(failed)} failed:")
        for rel, reason in failed:
            print(f"  {rel}: {reason}")

    return 0 if not failed else 2


if __name__ == "__main__":
    raise SystemExit(main())
