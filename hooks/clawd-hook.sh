#!/bin/sh
# Claude Code 훅 → Clawd Touch Bar.
# 훅 입력(JSON)을 ~/.clawd-touchbar/events 에 파일로 떨궈 두면 앱이 읽어 간다.
# 앱이 꺼져 있으면 아무것도 하지 않고, 어떤 경우에도 Claude Code를 막지 않는다.
pgrep -xq ClawdTouchBar || { cat >/dev/null; exit 0; }
dir="$HOME/.clawd-touchbar/events"
mkdir -p "$dir" 2>/dev/null
tmp="$dir/.tmp.$$"
cat > "$tmp" 2>/dev/null && mv "$tmp" "$dir/$$.json" 2>/dev/null
exit 0
