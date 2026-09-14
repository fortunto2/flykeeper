#!/usr/bin/env python3
"""Upload App Store screenshots through the App Store Connect API.

    python3 scripts/upload-screenshots.py <version-id> <locale> <displayType> <file>...

The API wants a three-step dance per image: reserve (which returns signed upload
operations), PUT the bytes at each operation, then commit with the file's MD5. Anything
short of the commit leaves an empty placeholder in the store listing, so the commit is
what this script treats as "done".

Auth comes from `asc --profile admin auth token`, so no key material is handled here.
"""
import hashlib
import json
import subprocess
import sys
import urllib.request
from pathlib import Path

API = "https://api.appstoreconnect.apple.com/v1"
TOKEN = subprocess.run(["asc", "--profile", "admin", "auth", "token", "--confirm", "--output", "text"],
                       capture_output=True, text=True, check=True).stdout.strip()


def call(method, url, body=None, headers=None):
    req = urllib.request.Request(url, method=method)
    req.add_header("Authorization", f"Bearer {TOKEN}")
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        req.add_header("Content-Type", "application/json")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    with urllib.request.urlopen(req, data) as r:
        raw = r.read()
    return json.loads(raw) if raw else {}


def screenshot_set(localization_id: str, display_type: str) -> str:
    sets = call("GET", f"{API}/appStoreVersionLocalizations/{localization_id}/appScreenshotSets")
    for s in sets.get("data", []):
        if s["attributes"]["screenshotDisplayType"] == display_type:
            return s["id"]
    made = call("POST", f"{API}/appScreenshotSets", {
        "data": {"type": "appScreenshotSets",
                 "attributes": {"screenshotDisplayType": display_type},
                 "relationships": {"appStoreVersionLocalization": {
                     "data": {"type": "appStoreVersionLocalizations", "id": localization_id}}}}})
    return made["data"]["id"]


def upload(set_id: str, path: Path) -> str:
    blob = path.read_bytes()
    made = call("POST", f"{API}/appScreenshots", {
        "data": {"type": "appScreenshots",
                 "attributes": {"fileSize": len(blob), "fileName": path.name},
                 "relationships": {"appScreenshotSet": {
                     "data": {"type": "appScreenshotSets", "id": set_id}}}}})
    shot_id = made["data"]["id"]
    for op in made["data"]["attributes"]["uploadOperations"]:
        req = urllib.request.Request(op["url"], method=op["method"],
                                     data=blob[op["offset"]:op["offset"] + op["length"]])
        for h in op["requestHeaders"]:
            req.add_header(h["name"], h["value"])
        urllib.request.urlopen(req).read()
    call("PATCH", f"{API}/appScreenshots/{shot_id}", {
        "data": {"type": "appScreenshots", "id": shot_id,
                 "attributes": {"uploaded": True,
                                "sourceFileChecksum": hashlib.md5(blob).hexdigest()}}})
    return shot_id


def main():
    version_id, locale, display_type, *files = sys.argv[1:]
    locs = call("GET", f"{API}/appStoreVersions/{version_id}/appStoreVersionLocalizations")
    loc_id = next(l["id"] for l in locs["data"] if l["attributes"]["locale"] == locale)
    set_id = screenshot_set(loc_id, display_type)
    for f in files:
        print(f"{Path(f).name} -> {upload(set_id, Path(f))}", flush=True)


if __name__ == "__main__":
    main()
