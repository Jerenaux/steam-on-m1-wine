#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
launcher="$repo_root/scripts/launch-steam.sh"

grep -Fq 'export ROSETTA_ADVERTISE_AVX=1' "$launcher" || {
    printf 'Steam launcher must advertise Rosetta AVX support\n' >&2
    exit 1
}

echo "Rosetta AVX advertisement regression check passed"
