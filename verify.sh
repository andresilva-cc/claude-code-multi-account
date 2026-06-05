#!/usr/bin/env bash
# claude-code-multi-account: prove isolation holds.
#
# Model: your PRIMARY account owns the keychain via `claude /login` (no env vars);
# each work dir overrides it with a CLAUDE_CODE_OAUTH_TOKEN in its .envrc. So a correct
# setup means:
#   - the work dir resolves a non-empty token + its own CLAUDE_CONFIG_DIR
#   - the default ($HOME) resolves NO token + NO CLAUDE_CONFIG_DIR (falls through to the
#     keychain /login session)
#
# It does NOT use `claude -p '/status'` — slash commands don't run in headless (`-p`) mode.
# Offline, no quota.
#
# Usage: ./verify.sh <work-dir>      e.g. ./verify.sh ~/work
set -euo pipefail

WORK_DIR="${1:-}"
[ -n "$WORK_DIR" ] || { echo "usage: ./verify.sh <work-dir>" >&2; exit 2; }
[ -d "$WORK_DIR" ] || { echo "verify: $WORK_DIR does not exist" >&2; exit 2; }
command -v direnv >/dev/null 2>&1 || { echo "verify: direnv not installed" >&2; exit 2; }

# Read what each location resolves to, loaded exactly as direnv would load its .envrc.
get() { direnv exec "$1" sh -c "printf %s \"\${$2:-}\"" 2>/dev/null || true; }
sha() { if [ -n "${1:-}" ]; then printf %s "$1" | shasum | awk '{print $1}'; else echo "<unset>"; fi; }

WORK_TOKEN="$(get "$WORK_DIR" CLAUDE_CODE_OAUTH_TOKEN)"
WORK_CFG="$(get "$WORK_DIR" CLAUDE_CONFIG_DIR)"
HOME_TOKEN="$(get "$HOME" CLAUDE_CODE_OAUTH_TOKEN)"
HOME_CFG="$(get "$HOME" CLAUDE_CONFIG_DIR)"

echo "==> work dir: $WORK_DIR"
echo "    CLAUDE_CONFIG_DIR : ${WORK_CFG:-<unset>}"
echo "    token (sha)       : $(sha "$WORK_TOKEN")"
echo "==> default (\$HOME) — should use the keychain /login session"
echo "    CLAUDE_CONFIG_DIR : ${HOME_CFG:-<unset>}"
echo "    token (sha)       : $(sha "$HOME_TOKEN")"
echo

fail=0
[ -n "$WORK_TOKEN" ] || { echo "FAIL — work dir resolved NO token (direnv allow'd? keychain item name/casing right?)"; fail=1; }
[ -n "$WORK_CFG" ]   || { echo "FAIL — work dir set no CLAUDE_CONFIG_DIR (check the .envrc)"; fail=1; }
[ -z "$HOME_TOKEN" ] || { echo "FAIL — \$HOME resolves a token; the default should be keychain /login, not env auth. Remove the token export from your shell rc."; fail=1; }
[ -z "$HOME_CFG" ]   || { echo "WARN — \$HOME sets CLAUDE_CONFIG_DIR ($HOME_CFG); the default should leave it unset."; }
if [ -n "$WORK_TOKEN" ] && [ "$WORK_TOKEN" = "$HOME_TOKEN" ]; then
  echo "FAIL — work and default resolve the SAME token; not isolated."
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "PASS — work dir overrides via token; default falls through to the keychain login."
fi
exit "$fail"
