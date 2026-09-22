#!/usr/bin/env python3
"""Builds a demo history folder for the store-listing screenshots.

    python3 make_demo_history.py <demo-images-dir> <output-dir>

Everything is invented: no real clipboard content is used.
"""
import hashlib, json, shutil, subprocess, sys, uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

images_dir, out = Path(sys.argv[1]), Path(sys.argv[2])
shutil.rmtree(out, ignore_errors=True)
(out / "images").mkdir(parents=True)

# Newest first: row 1 is the first entry.
ITEMS = [
    ("text", "https://developer.apple.com/documentation/appkit/nspasteboard", "Safari"),
    ("text", "func poll() {\n    guard change != last else { return }\n    record(pasteboard)\n}", "Xcode"),
    ("image", "design.png", "Preview"),
    ("text", "Ship the changelog before Friday. Ask Sam to review the release notes.", "Notes"),
    ("text", "ssh -L 5432:db.internal:5432 bastion.example.com", "Terminal"),
    ("image", "chart.png", "Preview"),
    ("text", "git log --oneline --since='2 weeks ago'", "Terminal"),
    ("text", "#5B6CF0", "Notes"),
    ("text", "git rebase -i HEAD~3", "Terminal"),
    ("text", "Meeting moved to Thursday 14:30, room 4B.", "Notes"),
    ("image", "landscape.png", "Preview"),
    ("text", "kubectl rollout restart deployment/api -n staging", "Terminal"),
    ("text", "git push --force-with-lease origin main", "Terminal"),
    ("text", "SELECT id, name FROM customers WHERE active = true ORDER BY name;", "Terminal"),
    ("text", "https://example.com/docs/getting-started", "Safari"),
]

def dims(path):
    r = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(path)], capture_output=True, text=True).stdout
    vals = {l.split(":")[0].strip(): int(l.split(":")[1]) for l in r.splitlines() if ":" in l}
    return vals["pixelWidth"], vals["pixelHeight"]

now = datetime.now(timezone.utc).replace(microsecond=0)
history = []
for i, (kind, payload, app) in enumerate(ITEMS):
    item_id = str(uuid.uuid4()).upper()
    entry = {"id": item_id, "kind": kind, "text": None, "imageFile": None,
             "pixelWidth": None, "pixelHeight": None, "sourceBundleID": None,
             "sourceAppName": app, "createdAt": (now - timedelta(minutes=7 * i)).strftime("%Y-%m-%dT%H:%M:%SZ")}
    if kind == "text":
        entry["text"] = payload
        entry["fingerprint"] = hashlib.sha256(payload.encode()).hexdigest()
    else:
        data = (images_dir / payload).read_bytes()
        entry["imageFile"] = f"{item_id}.png"
        (out / "images" / entry["imageFile"]).write_bytes(data)
        entry["pixelWidth"], entry["pixelHeight"] = dims(images_dir / payload)
        entry["fingerprint"] = hashlib.sha256(data).hexdigest()
    history.append(entry)

(out / "history.json").write_text(json.dumps(history, ensure_ascii=False))
print(f"wrote {len(history)} items ({sum(1 for h in history if h['kind']=='image')} images) to {out}")
