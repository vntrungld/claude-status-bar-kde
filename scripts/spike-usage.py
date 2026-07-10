#!/usr/bin/env python3
"""Throwaway spike: does /api/oauth/usage work with the local token + UA header?"""
import json, os, sys, urllib.request, urllib.error

CRED = os.path.expanduser("~/.claude/.credentials.json")
URL = "https://api.anthropic.com/api/oauth/usage"
UA = "claude-code/2.1.197"

def main():
    tok = json.load(open(CRED))["claudeAiOauth"]["accessToken"]
    for with_ua in (True, False):
        headers = {"Authorization": f"Bearer {tok}"}
        if with_ua:
            headers["User-Agent"] = UA
        req = urllib.request.Request(URL, headers=headers)
        label = "WITH ua" if with_ua else "NO ua"
        try:
            with urllib.request.urlopen(req, timeout=15) as r:
                body = r.read().decode()
                print(f"[{label}] HTTP {r.status}")
                print(json.dumps(json.loads(body), indent=2)[:1500])
        except urllib.error.HTTPError as e:
            print(f"[{label}] HTTP {e.code}: {e.read().decode()[:300]}")
        except Exception as e:
            print(f"[{label}] ERROR {type(e).__name__}: {e}")

if __name__ == "__main__":
    main()
