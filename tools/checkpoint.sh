#!/bin/bash
# Creates checkpoint artifacts for syncing to the user's Mac:
#   /mnt/user-data/outputs/gearforge/Gearforge-src.tar.gz  (working tree, no .git/.build)
#   /mnt/user-data/outputs/gearforge/Gearforge.bundle      (full git history)
set -e
cd /home/claude/Gearforge
OUT=/mnt/user-data/outputs/gearforge
mkdir -p $OUT
TS=$(date +%Y%m%d-%H%M)
# Xcode project is generated (source of truth: tools/ios/gen_xcodeproj.py) — refresh it so new Swift files are in it.
python3 tools/ios/gen_xcodeproj.py
if ! git diff --quiet -- App/Gearforge.xcodeproj App/Resources/Assets.xcassets; then
  echo "WARNING: Xcode project was regenerated — commit App/Gearforge.xcodeproj so the git bundle matches the tarball."
fi
git bundle create $OUT/Gearforge-$TS.bundle --all >/dev/null 2>&1
tar --exclude=.git --exclude='.build*' --exclude=.claude --exclude='*.xcuserdata' -czf $OUT/Gearforge-src-$TS.tar.gz .
ls -la $OUT
