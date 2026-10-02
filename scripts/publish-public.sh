#!/bin/bash
# 공개 영어 저장소(github.com/suinegyzal/clawd-pet)에 지금 커밋된 코드를 올린다.
# 이 비공개 저장소의 커밋 기록(작성자 이메일 등)은 올리지 않고, 파일만 옮겨 공개 저장소에 새 커밋을 만든다.
# 공개 쪽에서는 영어 README가 기본(README.md)이고, 한국어는 README.ko.md 가 된다.
#
#   ./scripts/publish-public.sh "Add pet names"              # 올리기
#   TAG=v1.0.1 ./scripts/publish-public.sh "v1.0.1"          # 올리고 Release까지 (GitHub Actions가 앱을 빌드)
set -euo pipefail
cd "$(dirname "$0")/.."

PUBLIC_REPO="https://github.com/suinegyzal/clawd-pet.git"
DIR="$HOME/Documents/clawd-pet-public"
MESSAGE="${1:-Update}"

[ -d "$DIR/.git" ] || git clone -q "$PUBLIC_REPO" "$DIR"
case "$DIR" in */clawd-pet-public) ;; *) echo "공개 저장소 폴더가 이상해요: $DIR" >&2; exit 1 ;; esac
git -C "$DIR" pull -q --ff-only 2>/dev/null || true

# 공개 폴더를 비우고(.git 제외) 지금 커밋된 파일만 옮긴다. 커밋 안 한 변경은 빠진다.
find "$DIR" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
git archive HEAD | tar -x -C "$DIR"
rm -f "$DIR/scripts/publish-public.sh"
rmdir "$DIR/scripts" 2>/dev/null || true

mv "$DIR/README.md" "$DIR/README.ko.md"
mv "$DIR/README.en.md" "$DIR/README.md"
sed -i '' -e 's#README\.en\.md#README.md#g' -e 's#suinegyzal/clawd-touchbar#suinegyzal/clawd-pet#g' "$DIR/README.md" "$DIR/README.ko.md"

git -C "$DIR" add -A
if git -C "$DIR" diff --cached --quiet; then
  echo "공개 저장소에 바뀐 것이 없어요."
else
  git -C "$DIR" commit -q -m "$MESSAGE"
  git -C "$DIR" push -q origin HEAD:main
  echo "공개 저장소에 올렸어요: https://github.com/suinegyzal/clawd-pet"
fi

if [ -n "${TAG:-}" ]; then
  git -C "$DIR" tag "$TAG"
  git -C "$DIR" push -q origin "$TAG"
  echo "$TAG 태그를 올렸어요. 몇 분 뒤 Releases에 ClawdPet.zip이 생겨요."
fi
