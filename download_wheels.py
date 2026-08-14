# -*- coding: utf-8 -*-
"""绕过 pip，用 urllib 直连 PyPI JSON API 下载所需 wheel（配合 --no-index 离线安装）。"""
import json
import os
import sys
import urllib.request

DEST = sys.argv[1] if len(sys.argv) > 1 else "_tmpdl"
PKGS = sys.argv[2:] or ["proxy_tools", "typing_extensions", "cffi"]
os.makedirs(DEST, exist_ok=True)


def fetch_json(pkg):
    url = f"https://pypi.org/pypi/{pkg}/json"
    with urllib.request.urlopen(url, timeout=15) as r:
        return json.load(r)


def pick_wheel(files):
    wheels = [f for f in files if f.get("packagetype") == "bdist_wheel"]
    pref64 = [f for f in wheels if "cp311" in f["filename"] and "win_amd64" in f["filename"]]
    if pref64:
        return pref64[0]
    pref_any = [f for f in wheels if "win_amd64" in f["filename"]]
    if pref_any:
        return pref_any[0]
    any_py = [f for f in wheels if f["filename"].endswith("py3-none-any.whl") or "py2.py3" in f["filename"]]
    if any_py:
        return any_py[0]
    return wheels[0] if wheels else None


for pkg in PKGS:
    try:
        data = fetch_json(pkg)
        chosen = pick_wheel(data["urls"])
        if not chosen:
            print(f"ERR {pkg}: no wheel found")
            continue
        fn = os.path.join(DEST, chosen["filename"])
        if os.path.exists(fn):
            print(f"SKIP {pkg}: {chosen['filename']} already present")
            continue
        print(f"GET  {pkg}: {chosen['filename']}")
        with urllib.request.urlopen(chosen["url"], timeout=60) as r:
            blob = r.read()
        with open(fn, "wb") as f:
            f.write(blob)
        print(f"OK   {pkg}: {fn} ({len(blob)} bytes)")
    except Exception as e:  # noqa: BLE001
        print(f"ERR  {pkg}: {type(e).__name__}: {e}")
