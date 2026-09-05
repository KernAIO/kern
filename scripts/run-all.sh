#!/usr/bin/env bash
# Runs a pnpm script in every checked-out Kern repository, in dependency order.
#
# The umbrella cannot own a turbo task graph: each repo carries its own turbo.json
# and CI clones it alone, so that file has to be a *root* config — and turbo rejects
# the `extends: ["//"]` a package-level config inside this workspace would need.
# Rather than keep two incompatible shapes in one file, the umbrella just drives
# each repo's own scripts.
#
#   scripts/run-all.sh typecheck            # sequential, stops nothing, reports every failure
#   scripts/run-all.sh dev --parallel       # all at once, Ctrl-C kills the group
set -uo pipefail
cd "$(dirname "$0")/.."

TASK="${1:?usage: run-all.sh <task> [--parallel]}"
MODE="${2:-}"

# The build order lives in scripts/repos.mjs, with dev-setup.sh reading the same list. Keeping a
# second copy here is what let `shell` fall out of one of them: every aggregate command skipped the
# entire user interface, silently, for months.
ORDER=()
while IFS= read -r r; do
  [ -n "$r" ] && ORDER+=("$r")
done < <(node scripts/repos.mjs)
if [ ${#ORDER[@]} -eq 0 ]; then
  echo "scripts/repos.mjs listed no repositories — nothing to run" >&2
  exit 1
fi

has_script() {
  node -e "const s=require('./repos/$1/package.json').scripts||{};process.exit(s['$TASK']?0:1)" 2>/dev/null
}

targets=()
absent=()
for r in "${ORDER[@]}"; do
  if [ ! -f "repos/$r/package.json" ]; then
    absent+=("$r")
    continue
  fi
  has_script "$r" && targets+=("$r")
done

# A repository that is not checked out is skipped — that is how a partial workspace stays usable —
# but never silently: an unnoticed skip is exactly how the interface went unbuilt.
if [ ${#absent[@]} -gt 0 ]; then
  printf '\033[33m! not checked out, so not part of this %s: %s\033[0m\n' "$TASK" "${absent[*]}"
  printf '\033[2m  run pnpm setup to clone them\033[0m\n'
fi

if [ ${#targets[@]} -eq 0 ]; then
  echo "no repository has a \"$TASK\" script — nothing to run"
  exit 0
fi

fail=0
failed=()

if [ "$MODE" = "--parallel" ]; then
  trap 'kill 0' INT TERM
  pids=()
  for r in "${targets[@]}"; do
    (cd "repos/$r" && pnpm "$TASK" 2>&1 | sed "s/^/[$r] /") &
    pids+=("$!")
  done
  for p in "${pids[@]}"; do wait "$p" || fail=1; done
else
  for r in "${targets[@]}"; do
    printf '\n\033[1m▸ %s — %s\033[0m\n' "$r" "$TASK"
    if ! (cd "repos/$r" && pnpm "$TASK"); then
      fail=1
      failed+=("$r")
    fi
  done
fi

if [ "$fail" -ne 0 ] && [ ${#failed[@]} -gt 0 ]; then
  printf '\n\033[31m✗ %s failed in: %s\033[0m\n' "$TASK" "${failed[*]}"
fi
exit "$fail"
