#!/usr/bin/env bash
# claude-code-multi-account: prove a work directory resolves to a DIFFERENT
# account than your personal default.
#
# It does NOT use `claude -p '/status'` — slash commands don't run in headless
# (`-p`) mode. Instead it compares the OAuth token + config dir that each
# location actually resolves to, which is the real switching mechanism. Offline,
# no quota used.
#
# Usage: ./verify.sh <work-dir> [personal-keychain-item]
#   e.g. ./verify.sh ~/work
#   personal-keychain-item defaults to "Claude-Personal-Token"
set -euo pipefail

WORK_DIR="${1:-}"
PERSONAL_ITEM="${2:-Claude-Personal-Token}"

[ -n "$WORK_DIR" ] || { echo "usage: ./verify.sh <work-dir> [personal-keychain-item]" >&2; exit 2; }
[ -d "$WORK_DIR" ] || { echo "verify: $WORK_DIR does not exist" >&2; exit 2; }
command -v direnv >/dev/null 2>&1 || { echo "verify: direnv not installed" >&2; exit 2; }

sha() { if [ -n "${1:-}" ]; then printf %s "$1" | shasum | awk '{print $1}'; else echo "<empty>"; fi; }

# What the work dir resolves to, loaded exactly as direnv would load its .envrc.
WORK_TOKEN="$(direnv exec "$WORK_DIR" sh -c 'printf %s "${CLAUDE_CODE_OAUTH_TOKEN:-}"' 2>/dev/null || true)"
WORK_CFG="$(direnv exec "$WORK_DIR" sh -c 'printf %s "${CLAUDE_CONFIG_DIR:-}"' 2>/dev/null || true)"

# Personal default token, read straight from its keychain item.
PERSONAL_TOKEN="$(security find-generic-password -s "$PERSONAL_ITEM" -w 2>/dev/null || true)"

echo "==> work dir: $WORK_DIR"
echo "    CLAUDE_CONFIG_DIR : ${WORK_CFG:-<unset>}"
echo "    token (sha)       : $(sha "$WORK_TOKEN")"
echo "==> personal ($PERSONAL_ITEM)"
echo "    token (sha)       : $(sha "$PERSONAL_TOKEN")"
echo

fail=0
if [ -z "$WORK_TOKEN" ]; then
  echo "FAIL — the work dir resolved NO token."
  echo "       Did you 'direnv allow' its .envrc, and is the Claude-<profile>-Token keychain item set?"
  fail=1
fi
if [ -z "$PERSONAL_TOKEN" ]; then
  echo "WARN — personal keychain item '$PERSONAL_ITEM' is empty."
  echo "       If you named it differently, pass it as arg 2: ./verify.sh $WORK_DIR <item-name>"
fi
if [ -n "$WORK_TOKEN" ] && [ "$WORK_TOKEN" = "$PERSONAL_TOKEN" ]; then
  echo "FAIL — work and personal resolve the SAME token; not isolated."
  fail=1
fi

if [ "$fail" -eq 0 ] && [ -n "$WORK_TOKEN" ] && [ -n "$PERSONAL_TOKEN" ]; then
  echo "PASS — the work dir loads a distinct account token from personal."
elif [ "$fail" -eq 0 ]; then
  echo "OK — the work dir loads a token; couldn't compare against personal (see WARN)."
fi
exit "$fail"
