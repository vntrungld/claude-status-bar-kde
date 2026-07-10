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

def _is_our_hook(command, bin_dir):
    return f"{bin_dir}/claude-status-hook.py" in (command or "")

def unmerge(settings, bin_dir):
    """Remove only our hook entries; preserve foreign hooks even when they
    share a matcher-group's hooks list. Drop groups/events left empty."""
    hooks = settings.get("hooks", {})
    for event in list(hooks.keys()):
        new_groups = []
        for group in hooks[event]:
            group["hooks"] = [h for h in group.get("hooks", [])
                              if not _is_our_hook(h.get("command", ""), bin_dir)]
            if group["hooks"]:
                new_groups.append(group)
        if new_groups:
            hooks[event] = new_groups
        else:
            del hooks[event]
    return settings
