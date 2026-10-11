#!/bin/bash
# Creates checkpoint artifacts for syncing to the user's Mac:
#   /mnt/user-data/outputs/gearforge/Gearforge-src.tar.gz  (working tree, no .git/.build)
#   /mnt/user-data/outputs/gearforge/Gearforge.bundle      (full git history)
set -e
cd /home/claude/Gearforge
OUT=/mnt/user-data/outputs/gearforge
mkdir -p $OUT
git bundle create $OUT/Gearforge.bundle --all >/dev/null 2>&1
tar --exclude=.git --exclude='.build*' --exclude=.claude --exclude='*.xcuserdata' -czf $OUT/Gearforge-src.tar.gz .
ls -la $OUT
