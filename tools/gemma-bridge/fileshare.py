"""Shared folder for the phone: list, download, upload. Used by gemma_bridge.py.

The shared folder is ~/KOS-Share (or "share_dir" in ~/.gemma-bridge/config.json).
Everything is relative to it; paths that leave it (.., links) are refused.
"""
import os
import shutil
import tempfile

MAX_UPLOAD = 2 * 1024 * 1024 * 1024  # 2 GB, a sanity limit


def share_root(cfg):
    root = os.path.expanduser(cfg.get("share_dir") or "~/KOS-Share")
    os.makedirs(root, exist_ok=True)
    return os.path.realpath(root)


def safe_path(root, rel):
    """Absolute path inside root for a relative path, or None if it would escape."""
    rel = (rel or "").lstrip("/")
    full = os.path.realpath(os.path.join(root, rel))
    if full != root and not full.startswith(root + os.sep):
        return None
    return full


def listing(root, rel):
    full = safe_path(root, rel)
    if full is None or not os.path.isdir(full):
        return None
    items = []
    for name in sorted(os.listdir(full), key=str.lower):
        if name.startswith("."):
            continue
        p = os.path.join(full, name)
        try:
            st = os.stat(p)
        except OSError:
            continue
        items.append({"name": name, "dir": os.path.isdir(p), "size": 0 if os.path.isdir(p) else st.st_size,
                      "mtime": int(st.st_mtime)})
    # folders first
    items.sort(key=lambda i: (not i["dir"], i["name"].lower()))
    return items


def save_upload(root, rel, rfile, length):
    """Writes the request body to rel under root (via a temp file). Returns (ok, message)."""
    full = safe_path(root, rel)
    if full is None or full == root:
        return False, "bad path"
    if length < 0 or length > MAX_UPLOAD:
        return False, "too large"
    os.makedirs(os.path.dirname(full), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(full), prefix=".part-")
    try:
        with os.fdopen(fd, "wb") as out:
            left = length
            while left > 0:
                chunk = rfile.read(min(65536, left))
                if not chunk:
                    return False, "connection closed early"
                out.write(chunk)
                left -= len(chunk)
        shutil.move(tmp, full)
        return True, "ok"
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)
