#!/usr/bin/env bash
# PreToolUse hook (decision D19): before a `git commit`, run the docs guard
# (`rake docs:check`). On failure, deny the commit and feed the check output
# back as the reason, so the docs are fixed before the commit lands.
#
# The hook is registered on the Bash matcher with NO `if` gate (that only
# prefix-matches, so `git add … && git commit …` would slip past). Instead we
# read the command from stdin and detect a real `git commit` invocation
# ourselves — robust to compound commands, multi-line scripts, and subshells —
# then exit 0 (allow) for everything else.
set -uo pipefail

# Repo root = two levels up from this script (.claude/hooks/).
cd "$(dirname "$0")/../.." || exit 0

command=$(cat | jq -r '.tool_input.command // ""')

# Match `git [global-flags] commit` as a real command, anywhere on any line:
#   - grep runs per line, so `^` also anchors statements after a newline
#     (e.g. `git add -A` then `git commit …` on the next line);
#   - `(^|[;&|(])` anchors statements after `;`, `&&`, `||`, `|`, or `(`;
#   - optional `-flag` tokens may sit between `git` and `commit`;
#   - `commit` must be followed by a command delimiter or end-of-line, so
#     `git commit-tree` and quoted prose like `echo "git commit"` don't match.
# (We keep the git→commit gap to flags only on purpose: matching arbitrary
# tokens there would false-block innocent commands like
# `git diff -- commit_helper.rb`. The rare `git -c k=v commit` form isn't caught.)
if ! printf '%s' "$command" |
  grep -Eq '(^|[;&|(])[[:space:]]*git([[:space:]]+-[^[:space:]]+)*[[:space:]]+commit([[:space:];)&|]|$)'; then
  exit 0 # not a git commit — allow
fi

if out=$(bundle exec rake docs:check 2>&1); then
  exit 0 # check passed — allow the commit
fi

# Failed — emit a PreToolUse deny with the check output as the reason.
reason=$(printf '%s' "$out" | jq -Rsa .)
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}' "$reason"
exit 0
