"""Merge our hooks into a Claude Code settings dict. Idempotent, additive."""
HOOK_EVENTS = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
               "PostToolUseFailure", "Notification", "Stop", "SessionEnd"]

def hook_command(bin_dir, event):
    return f"python3 {bin_dir}/claude-status-hook.py {event}"

def merge(settings, bin_dir):
    hooks = settings.setdefault("hooks", {})
    for event in HOOK_EVENTS:
        cmd = hook_command(bin_dir, event)
        groups = hooks.setdefault(event, [])
        # dedup: skip if any group already has this exact command
        if any(h.get("command") == cmd
               for g in groups for h in g.get("hooks", [])):
            continue
        groups.append({"matcher": "*", "hooks": [{"type": "command", "command": cmd}]})
    return settings
