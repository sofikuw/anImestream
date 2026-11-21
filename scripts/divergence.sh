#!/usr/bin/env bash
# Prints the divergence meter: the fork's distance from upstream, as a
# Steins;Gate-style worldline number.
#
# The digits are real: the number after the `1.` is the count of lines added and
# removed since the fork point, zero-padded to six. So 1.048596 means 48,596
# lines have moved. It only ever grows, and it is reproducible from the repo.
set -euo pipefail

# merge-base of `divergent` and frostnova721/animestream at the fork point.
ANCHOR=7813ca07dddb19ff644f1dac27ba97c84c5b6d34

if ! git cat-file -e "${ANCHOR}^{commit}" 2>/dev/null; then
  echo "divergence: ${ANCHOR} is not in this clone (needs full history)" >&2
  echo "1.000000"
  exit 0
fi

churn=$(git diff --numstat "$ANCHOR" HEAD | awk '{ added += $1; removed += $2 } END { print added + removed + 0 }')

printf '1.%06d\n' "$churn"
