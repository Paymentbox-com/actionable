#!/usr/bin/env bash
# PreToolUse hook (decision D19): before a `git commit`, run the docs guard
# (`rake docs:check`). On failure, deny the commit and feed the check's output
# back as the reason, so the docs are fixed before the commit lands. Gated to
# `git commit*` via the hook's `if` in .claude/settings.json, so other Bash
# commands never reach this script.
set -uo pipefail

# Repo root = two levels up from this script (.claude/hooks/).
cd "$(dirname "$0")/../.." || exit 0

if out=$(bundle exec rake docs:check 2>&1); then
  exit 0 # check passed — allow the commit (no output = default allow)
fi

# Failed — emit a PreToolUse deny with the check output as the reason.
reason=$(printf '%s' "$out" | jq -Rsa .)
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}' "$reason"
exit 0
