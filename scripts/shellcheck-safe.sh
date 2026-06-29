#!/bin/bash
#
# shellcheck-safe.sh — memory-capped shellcheck wrapper for this repo.
#
# Why this exists:
#   This repo has 700+ `# shellcheck source=` directives and a deep diamond
#   dependency graph (most lib/ files source lib/common.sh, several levels
#   deep). When shellcheck follows sources (-x / --external-sources), it
#   re-analyzes each sourced file along EVERY include path — an exponential
#   blowup. A single shellcheck process reached ~30 GB RAM and OOM-froze the
#   machine. See .cursor/rules/linting-formatting.mdc.
#
# What this does:
#   1. Hard-caps the process address space (ulimit -v) so a runaway aborts
#      instead of taking the machine down. Default 2 GB; override with
#      SHELLCHECK_MEM_MB.
#   2. Warns loudly when -x / --external-sources is requested (the dangerous
#      mode for this repo) but still runs — the cap makes it survivable.
#   3. Execs the real shellcheck with all arguments unchanged.
#
# Usage:
#   scripts/shellcheck-safe.sh --severity=error *.sh lib/*.sh lib/**/*.sh
#   SHELLCHECK_MEM_MB=4096 scripts/shellcheck-safe.sh -x somefile.sh
#
set -euo pipefail

mem_mb="${SHELLCHECK_MEM_MB:-2048}"

# Resolve the real shellcheck binary, skipping this wrapper (compare realpaths).
self="$(realpath "${BASH_SOURCE[0]}")"
real_shellcheck=""
while IFS= read -r candidate; do
	[ -n "$candidate" ] || continue
	if [ "$(realpath "$candidate" 2>/dev/null)" != "$self" ]; then
		real_shellcheck="$candidate"
		break
	fi
done < <(type -ap shellcheck 2>/dev/null)

if [ -z "$real_shellcheck" ]; then
	echo "shellcheck-safe: could not find the real shellcheck binary on PATH" >&2
	exit 127
fi

# Warn on source-following — the mode that blows up on this repo.
for arg in "$@"; do
	case "$arg" in
	-x | --external-sources)
		echo "shellcheck-safe: WARNING: '$arg' enables source-following, which can" >&2
		echo "shellcheck-safe: exponentially balloon memory on this repo. Capped at" >&2
		echo "shellcheck-safe: ${mem_mb} MB (SHELLCHECK_MEM_MB). Prefer linting one file at a time." >&2
		break
		;;
	esac
done

# Cap address space (KB) for this process and the exec'd shellcheck.
ulimit -v "$((mem_mb * 1024))" || {
	echo "shellcheck-safe: failed to set memory limit" >&2
	exit 1
}

exec "$real_shellcheck" "$@"
