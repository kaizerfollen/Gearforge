#!/bin/bash
# Usage: tools/patch.sh <since-commit>  → tarball of files changed since that commit (for quick Mac sync).
set -e
cd "$(dirname "$0")/.."
TS=$(date +%Y%m%d-%H%M%S)
OUT=/mnt/user-data/outputs/gearforge/patch-$TS.tar.gz
git diff --name-only --diff-filter=ACMR "$1" HEAD > /tmp/patch-files.txt
tar -czf "$OUT" -T /tmp/patch-files.txt
cat /tmp/patch-files.txt
echo "$OUT"
