#!/bin/bash
# 처음 받았을 때 한 번 실행: 앱을 빌드하고, 내 Claude Code에 훅을 연결하고, 앱을 띄운다.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh
chmod +x hooks/*.sh
/usr/bin/python3 hooks/install-hooks.py "$(pwd)"
open build/ClawdTouchBar.app
echo "완료! Touch Bar에 Clawd가 나타나요. Claude Code 세션은 새로 열어야 연동돼요."
