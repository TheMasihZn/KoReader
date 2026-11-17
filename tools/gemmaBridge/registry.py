#!/usr/bin/env python3
"""Registry: who is who, and what each one may do.

One file, ~/.gemmaBridge/registry.json. Every app, device or other client that talks to the bridge is an
entry with an id, a kind, the address it was last seen at, an owner, whether it is approved, and its grants
(scopes). Every request is checked against it; every decision goes to ~/.gemmaBridge/access.log.

Scopes:  info  chat  audio  files.read  files.write
The laptop itself (localhost) is always allowed. A phone needs the PIN *and* an approved entry. A client the
registry has not seen is added as "waiting for approval" with no grants, and refused until you approve it:

    python3 registry.py list
    python3 registry.py approve <id> [scope ...]     (no scopes = all)
    python3 registry.py grant <id> <scope> [scope ...]
    python3 registry.py revoke <id> [scope ...]      (no scopes = remove all access, keep the entry)
    python3 registry.py forget <id>

The file is plain JSON; editing it by hand works too.
"""
import json
import os
import sys
import threading
import time

APP_DIR = os.path.expanduser("~/.gemmaBridge")
SCOPES = ("info", "chat", "audio", "files.read", "files.write")


class Registry:
    def __init__(self, path=None, log_path=None):
        self.path = path or os.path.join(APP_DIR, "registry.json")
        self.log_path = log_path or os.path.join(APP_DIR, "access.log")
        self.lock = threading.Lock()
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        self.entries = {}
        self._load()

    def _load(self):
        try:
            with open(self.path, encoding="utf-8") as f:
                self.entries = json.load(f).get("entries", {})
        except (OSError, ValueError):
            self.entries = {}

    def _save(self):
        tmp = self.path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"entries": self.entries}, f, indent=2, ensure_ascii=False, sort_keys=True)
        os.replace(tmp, self.path)

    def log(self, client, scope, allowed, reason, address=""):
        line = {"time": time.strftime("%Y-%m-%d %H:%M:%S"), "client": client, "scope": scope,
                "allowed": allowed, "reason": reason, "address": address}
        try:
            with open(self.log_path, "a", encoding="utf-8") as f:
                f.write(json.dumps(line, ensure_ascii=False) + "\n")
        except OSError:
            pass

    def check(self, client, address, scope, kind="app"):
        """Returns (allowed, reason). Adds an unknown client as waiting for approval."""
        with self.lock:
            self._load()  # a hand edit or the CLI takes effect on the next request
            e = self.entries.get(client)
            if e is None:
                e = {"kind": kind, "address": address, "owner": "user", "approved": False, "grants": [],
                     "first_seen": time.strftime("%Y-%m-%d %H:%M:%S")}
                self.entries[client] = e
                e["last_seen"] = e["first_seen"]
                self._save()
                allowed, reason = False, "waiting for approval: run  python3 registry.py approve " + client
            else:
                if e.get("address") != address:
                    e["address"] = address
                e["last_seen"] = time.strftime("%Y-%m-%d %H:%M:%S")
                self._save()
                if not e.get("approved"):
                    allowed, reason = False, "waiting for approval: run  python3 registry.py approve " + client
                elif scope not in e.get("grants", []):
                    allowed, reason = False, "no grant for " + scope
                else:
                    allowed, reason = True, "granted"
        self.log(client, scope, allowed, reason, address)
        return allowed, reason

    # --- changes made by you -------------------------------------------------
    def approve(self, client, scopes=None):
        with self.lock:
            self._load()
            e = self.entries.setdefault(client, {"kind": "app", "address": "", "owner": "user",
                                                 "grants": [], "first_seen": time.strftime("%Y-%m-%d %H:%M:%S")})
            wanted = list(scopes) if scopes else list(SCOPES)
            bad = [s for s in wanted if s not in SCOPES]
            if bad:
                raise ValueError("unknown scope: " + ", ".join(bad))
            e["approved"] = True
            e["grants"] = sorted(set(e.get("grants", [])) | set(wanted))
            self._save()
        self.log(client, ",".join(wanted), True, "approved by the user")

    def grant(self, client, scopes):
        self.approve(client, scopes)

    def revoke(self, client, scopes=None):
        with self.lock:
            self._load()
            if client not in self.entries:
                raise KeyError(client)
            e = self.entries[client]
            if scopes:
                e["grants"] = [s for s in e.get("grants", []) if s not in scopes]
            else:
                e["grants"] = []
                e["approved"] = False
            self._save()
        self.log(client, ",".join(scopes or ["all"]), False, "revoked by the user")

    def forget(self, client):
        with self.lock:
            self._load()
            self.entries.pop(client, None)
            self._save()

    def pending(self):
        with self.lock:
            self._load()
            return [k for k, v in self.entries.items() if not v.get("approved")]

    def listing(self):
        with self.lock:
            self._load()
            return dict(self.entries)


def main(argv):
    reg = Registry()
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print(__doc__)
        return 0
    cmd, args = argv[1], argv[2:]
    try:
        if cmd == "list":
            entries = reg.listing()
            if not entries:
                print("Nothing registered yet. A phone shows up here after its first request.")
            for k, v in sorted(entries.items()):
                state = "approved" if v.get("approved") else "WAITING FOR APPROVAL"
                print(f"{k}  [{v.get('kind', '?')}]  {v.get('address', '')}  {state}  grants: {', '.join(v.get('grants', [])) or 'none'}")
        elif cmd == "approve" and args:
            reg.approve(args[0], args[1:])
            print("Approved " + args[0])
        elif cmd == "grant" and len(args) > 1:
            reg.grant(args[0], args[1:])
            print("Granted")
        elif cmd == "revoke" and args:
            reg.revoke(args[0], args[1:])
            print("Revoked")
        elif cmd == "forget" and args:
            reg.forget(args[0])
            print("Forgotten")
        else:
            print(__doc__)
            return 1
    except (ValueError, KeyError) as e:
        print("Stopped:", e)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
