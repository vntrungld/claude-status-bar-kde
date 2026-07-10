#!/usr/bin/env python3
"""Fetch Claude subscription usage from /api/oauth/usage; cache + print JSON.

Spike-confirmed shape: {"five_hour":{"utilization":N}, "seven_day":{"utilization":N}}
(adjust the keys here if Task 0 recorded different ones).
"""
import json, os, sys, time, urllib.request, urllib.error

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

CRED = os.path.expanduser("~/.claude/.credentials.json")
URL = "https://api.anthropic.com/api/oauth/usage"
UA = "claude-code/2.1.197"  # baked at install time from `claude --version`

def load_prev_cache():
    import statusbar_paths as p
    try:
        return json.load(open(p.usage_cache_path()))
    except (OSError, ValueError):
        return None

def build_result(now, http_status, body, prev_cache):
    prev = prev_cache or {}
    if http_status == 200:
        data = json.loads(body)
        return {"status": "ok", "fetched_at": now,
                "five_hour": data.get("five_hour", {}),
                "seven_day": data.get("seven_day", {})}
    if http_status == 401:
        status = "reauth"
    elif http_status == 429:
        status = "rate_limited"
    else:
        status = "error"
    return {"status": status, "fetched_at": prev.get("fetched_at"),
            "five_hour": prev.get("five_hour", {}),
            "seven_day": prev.get("seven_day", {})}

def read_token():
    try:
        creds = json.load(open(CRED))["claudeAiOauth"]
    except (OSError, ValueError, KeyError):
        return None, None
    return creds.get("accessToken"), creds.get("expiresAt")

def http_get(token):
    req = urllib.request.Request(
        URL, headers={"Authorization": f"Bearer {token}", "User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, ""
    except Exception:
        return 0, ""

def main():
    import statusbar_paths as p
    now = int(time.time())
    prev = load_prev_cache()
    token, expires_at = read_token()
    if not token or (expires_at and now * 1000 >= int(expires_at)):
        result = {"status": "reauth", "fetched_at": prev.get("fetched_at") if prev else None,
                  "five_hour": (prev or {}).get("five_hour", {}),
                  "seven_day": (prev or {}).get("seven_day", {})}
    else:
        code, body = http_get(token)
        result = build_result(now, code, body, prev)
    if result["status"] != "rate_limited":  # respect backoff: don't churn cache on 429
        p.atomic_write_json(p.usage_cache_path(), result)
    print(json.dumps(result))

if __name__ == "__main__":
    main()
