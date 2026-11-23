#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
launcher="$repo_root/scripts/launch-steam.sh"

grep -Fq "with timeout of 3 seconds" "$launcher"
grep -Fq "end timeout" "$launcher"

echo "Launch display timeout regression check passed"
