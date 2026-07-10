#!/usr/bin/env python3
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from settings_merge import merge
settings_path, bin_dir = sys.argv[1], sys.argv[2]
try:
    settings = json.load(open(settings_path))
except (OSError, ValueError):
    settings = {}
merge(settings, bin_dir)
os.makedirs(os.path.dirname(settings_path), exist_ok=True)
with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
print(f"Merged hooks into {settings_path}")
