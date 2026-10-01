#!/usr/bin/env python3
"""~/.claude/settings.json 에 Clawd Touch Bar 훅과 statusLine을 연결한다.

이 저장소를 받은 위치를 기준으로 경로를 넣기 때문에, 누가 어디에 받아도 그 사람 맥에 맞게 설정된다.
이미 있는 다른 설정은 그대로 두고, 바꾸기 전 원본은 settings.json.bak-clawd 로 남긴다.
"""
import json
import os
import sys

root = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), ".."))
path = os.path.expanduser("~/.claude/settings.json")
os.makedirs(os.path.dirname(path), exist_ok=True)

settings = {}
if os.path.exists(path):
    with open(path, encoding="utf-8") as f:
        settings = json.load(f)
    with open(path + ".bak-clawd", "w", encoding="utf-8") as f:
        json.dump(settings, f, indent=2, ensure_ascii=False)

hook = os.path.join(root, "hooks", "clawd-hook.sh")
hooks = settings.setdefault("hooks", {})
events = [("UserPromptSubmit", None), ("PreToolUse", "*"), ("PostToolUse", "*"),
          ("Notification", None), ("Stop", None), ("SessionEnd", None)]
for event, matcher in events:
    groups = hooks.setdefault(event, [])
    found = False
    for group in groups:
        for entry in group.get("hooks", []):
            if entry.get("command", "").endswith("clawd-hook.sh"):
                entry["command"] = hook   # 예전 위치를 가리키고 있으면 지금 위치로
                found = True
    if not found:
        group = {"hooks": [{"type": "command", "command": hook, "timeout": 5}]}
        if matcher:
            group["matcher"] = matcher
        groups.append(group)

status_line = os.path.join(root, "hooks", "clawd-statusline.sh")
current = (settings.get("statusLine") or {}).get("command", "")
if not current or current.endswith("clawd-statusline.sh"):
    settings["statusLine"] = {"type": "command", "command": status_line}
else:
    print(f"이미 다른 statusLine이 있어서 그대로 뒀어요: {current}")

with open(path, "w", encoding="utf-8") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write("\n")
print(f"Claude Code 연결 완료: {path}")
