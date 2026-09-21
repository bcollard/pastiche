#!/usr/bin/env python3
"""Import clipboard history from Copy 'Em into Pastiche.

Copy 'Em keeps its history in a sandboxed Core Data store. This reads the most
recent entries from it and writes them into Pastiche's history.json,
copying images out as PNGs.

Copy 'Em's own files are never modified: the store is copied to a temporary
directory and opened read-only.

    python3 Tools/import_copyem.py --limit 200
    python3 Tools/import_copyem.py --limit 200 --dry-run

Pastiche must not be running, or it will overwrite the imported file
with its own in-memory history when it next saves.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import plistlib
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import uuid
from datetime import datetime, timezone
from pathlib import Path

COPYEM_DIR = Path.home() / (
    "Library/Containers/Copy-em-Paste/Data/Library/Application Support/Copy-em-Paste"
)
STORE_NAME = "Copy-em-Paste.storedata"
TARGET_DIR = Path.home() / "Library/Application Support/Pastiche"

# Core Data timestamps count from 2001-01-01, not the Unix epoch.
CORE_DATA_EPOCH_OFFSET = 978307200

TEXT_TYPES = {"public.utf8-plain-text", "public.plain-text", "NSStringPboardType"}
IMAGE_TYPES = {"public.png", "public.tiff", "public.jpeg", "com.compuserve.gif"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--limit", type=int, default=200, help="how many recent entries to import (default: 200)")
    parser.add_argument("--max-items", type=int, default=500, help="cap on the merged history (default: 500)")
    parser.add_argument("--dry-run", action="store_true", help="report what would be imported, write nothing")
    parser.add_argument("--copyem-dir", type=Path, default=COPYEM_DIR, help="override Copy 'Em's data directory")
    parser.add_argument("--target-dir", type=Path, default=TARGET_DIR, help="override Pastiche's data directory")
    return parser.parse_args()


def ensure_app_not_running() -> None:
    result = subprocess.run(
        ["pgrep", "-f", "Pastiche.app/Contents/MacOS"],
        capture_output=True,
        text=True,
    )
    if result.stdout.strip():
        sys.exit(
            "Pastiche is running; it would overwrite the import.\n"
            "Quit it first:  pkill -f 'Pastiche.app'"
        )


def snapshot_store(source_dir: Path, workdir: Path) -> Path:
    """Copy the store (plus its WAL and SHM) so the original is never touched."""
    store = source_dir / STORE_NAME
    if not store.exists():
        sys.exit(f"No Copy 'Em store at {store}")
    target = workdir / "store.sqlite"
    for suffix in ("", "-wal", "-shm"):
        candidate = store.with_name(store.name + suffix)
        if candidate.exists():
            shutil.copy2(candidate, target.with_name(target.name + suffix))
    return target


def decode_payloads(blob: bytes) -> list[tuple[str, object]]:
    """Unpack Copy 'Em's NSKeyedArchiver blob into (uti, payload) pairs.

    The archive holds an NSArray of PasteboardContentsItemTypeAndData objects,
    a private class, so the UID graph is walked directly rather than handed to
    a keyed unarchiver.
    """
    archive = plistlib.load(io.BytesIO(blob))
    objects = archive["$objects"]
    root = objects[archive["$top"]["root"].data]

    pairs: list[tuple[str, object]] = []
    for ref in root.get("NS.objects", []):
        entry = objects[ref.data]
        uti = objects[entry["type"].data]
        payload = objects[entry["data"].data]
        pairs.append((uti, payload))
    return pairs


def resolve_payload(uti: str, payload: object, asset_root: Path) -> tuple[str, bytes] | None:
    """Return (normalised uti, bytes), following out-of-line asset references."""
    clean_uti = uti.replace("@DATA_IN_FILE", "").strip()

    if isinstance(payload, bytes):
        return clean_uti, payload

    # Large payloads live beside the store as local:///<dir>/<file>?<query>.
    if isinstance(payload, dict) and "NS.data" in payload:
        reference = payload["NS.data"]
        if isinstance(reference, bytes):
            reference = reference.decode("utf-8", "replace")
        if not reference.startswith("local:///"):
            return None
        relative = reference[len("local:///") :].split("?", 1)[0]
        asset = asset_root / relative
        if not asset.exists():
            return None
        return clean_uti, asset.read_bytes()

    return None


def to_png(data: bytes, uti: str, workdir: Path) -> bytes | None:
    """Normalise an image payload to PNG, matching what the app stores."""
    if uti == "public.png":
        return data
    suffix = {"public.tiff": ".tiff", "public.jpeg": ".jpg", "com.compuserve.gif": ".gif"}.get(uti)
    if suffix is None:
        return None
    source = workdir / f"convert{suffix}"
    destination = workdir / "convert.png"
    source.write_bytes(data)
    destination.unlink(missing_ok=True)
    result = subprocess.run(
        ["sips", "-s", "format", "png", str(source), "--out", str(destination)],
        capture_output=True,
    )
    if result.returncode != 0 or not destination.exists():
        return None
    return destination.read_bytes()


def png_dimensions(path: Path) -> tuple[int, int]:
    result = subprocess.run(
        ["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(path)],
        capture_output=True,
        text=True,
    )
    width = height = 0
    for line in result.stdout.splitlines():
        line = line.strip()
        if line.startswith("pixelWidth:"):
            width = int(line.split(":")[1])
        elif line.startswith("pixelHeight:"):
            height = int(line.split(":")[1])
    return width, height


def iso8601(core_data_timestamp: float | None) -> str:
    if core_data_timestamp is None:
        moment = datetime.now(timezone.utc)
    else:
        moment = datetime.fromtimestamp(core_data_timestamp + CORE_DATA_EPOCH_OFFSET, timezone.utc)
    # Match Swift's JSONEncoder .iso8601 output exactly.
    return moment.strftime("%Y-%m-%dT%H:%M:%SZ")


def read_rows(store: Path, limit: int) -> list[sqlite3.Row]:
    connection = sqlite3.connect(f"file:{store}?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    return connection.execute(
        """
        SELECT c.Z_PK            AS pk,
               c.ZCREATIONDATE   AS created,
               a.ZNAME           AS app_name,
               a.ZBUNDLEID       AS bundle_id,
               i.ZTYPESANDDATA   AS payload
          FROM ZPASTEBOARDCONTENTS c
          LEFT JOIN ZPASTEBOARDCONTENTSAPP  a ON a.Z_PK    = c.ZAPPLICATION
          LEFT JOIN ZPASTEBOARDCONTENTSITEM i ON i.Z5ITEMS = c.ZITEMSWRAPPER
         WHERE c.ZTRASHDATE IS NULL
           AND i.ZTYPESANDDATA IS NOT NULL
         ORDER BY c.ZCREATIONDATE DESC
         LIMIT ?
        """,
        (limit,),
    ).fetchall()


def build_item(row, asset_root: Path, workdir: Path):
    """Convert one Copy 'Em row into a Pastiche item, or None to skip."""
    try:
        payloads = decode_payloads(row["payload"])
    except Exception:
        return None, "unreadable"

    resolved = []
    for uti, payload in payloads:
        item = resolve_payload(uti, payload, asset_root)
        if item is not None:
            resolved.append(item)

    created = iso8601(row["created"])
    common = {
        "sourceBundleID": row["bundle_id"],
        "sourceAppName": row["app_name"],
        "createdAt": created,
    }

    # Text wins over an accompanying image, matching PasteboardMonitor's rule.
    for uti, data in resolved:
        if uti in TEXT_TYPES:
            text = data.decode("utf-8", "replace")
            if not text.strip():
                return None, "empty"
            return {
                "id": str(uuid.uuid4()).upper(),
                "kind": "text",
                "text": text,
                "imageFile": None,
                "pixelWidth": None,
                "pixelHeight": None,
                "fingerprint": hashlib.sha256(text.encode("utf-8")).hexdigest(),
                **common,
            }, "text"

    for uti, data in resolved:
        if uti not in IMAGE_TYPES:
            continue
        png = to_png(data, uti, workdir)
        if png is None:
            continue
        item_id = str(uuid.uuid4()).upper()
        return {
            "id": item_id,
            "kind": "image",
            "text": None,
            "imageFile": f"{item_id}.png",
            "pixelWidth": 0,
            "pixelHeight": 0,
            "fingerprint": hashlib.sha256(png).hexdigest(),
            "_png": png,
            **common,
        }, "image"

    return None, "unsupported"


def main() -> None:
    args = parse_args()
    if not args.dry_run:
        ensure_app_not_running()

    images_dir = args.target_dir / "images"
    history_file = args.target_dir / "history.json"
    if not args.dry_run:
        images_dir.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as tmp:
        workdir = Path(tmp)
        store = snapshot_store(args.copyem_dir, workdir)
        rows = read_rows(store, args.limit)

        imported, counts = [], {"text": 0, "image": 0, "empty": 0, "unsupported": 0, "unreadable": 0}
        for row in rows:
            item, outcome = build_item(row, args.copyem_dir / "Asset", workdir)
            counts[outcome] = counts.get(outcome, 0) + 1
            if item:
                imported.append(item)

    existing = []
    if history_file.exists():
        try:
            existing = json.loads(history_file.read_text())
        except json.JSONDecodeError:
            print(f"warning: {history_file} was unreadable and will be replaced", file=sys.stderr)

    # Existing entries win on a fingerprint clash: they are the live ones the
    # app already has open.
    seen = {entry["fingerprint"] for entry in existing}
    merged = list(existing)
    for item in imported:
        if item["fingerprint"] in seen:
            counts["duplicate"] = counts.get("duplicate", 0) + 1
            continue
        seen.add(item["fingerprint"])
        merged.append(item)

    merged.sort(key=lambda entry: entry["createdAt"], reverse=True)
    dropped = merged[args.max_items :]
    merged = merged[: args.max_items]

    print(f"read {len(rows)} entries from Copy 'Em")
    for label in ("text", "image", "duplicate", "empty", "unsupported", "unreadable"):
        if counts.get(label):
            print(f"  {counts[label]:4d}  {label}")
    print(f"history: {len(existing)} existing + {len(imported)} imported -> {len(merged)} (cap {args.max_items})")

    if args.dry_run:
        print("\ndry run: nothing written")
        return

    images_dir.mkdir(parents=True, exist_ok=True)

    # Only now that the survivors are known are their PNGs written, so a
    # duplicate or a capped-off entry never leaves a file behind.
    for entry in merged:
        png = entry.pop("_png", None)
        if png is None:
            continue
        destination = images_dir / entry["imageFile"]
        destination.write_bytes(png)
        entry["pixelWidth"], entry["pixelHeight"] = png_dimensions(destination)
    for entry in dropped:
        entry.pop("_png", None)

    history_file.write_text(json.dumps(merged, indent=None, ensure_ascii=False))
    print(f"wrote {history_file} ({sum(1 for e in merged if e.get('imageFile'))} images)")


if __name__ == "__main__":
    main()
