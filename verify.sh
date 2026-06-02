#!/usr/bin/env bash
# claude-code-multi-account: prove isolation holds.
#
# Checks, for a given work directory:
#   1. the work dir resolves to a DIFFERENT identity than the default (personal)
#   2. running the work account leaves the shared keychain slot BYTE-IDENTICAL
#      (proof the env token is bypassing the keychain, not rewriting it)
#
# Usage: ./verify.sh <work-dir>      e.g. ./verify.sh ~/work
set -euo pipefail

KEYCHAIN_SERVICE="Claude Code-credentials"
WORK_DIR="${1:-}"

if [ -z "$WORK_DIR" ]; then
  echo "usage: ./verify.sh <work-dir>" >&2
  exit 2
fi
if ! command -v claude >/dev/null 2>&1; then
  echo "verify: 'claude' not found in PATH" >&2
  exit 2
fi

keychain_hash() {
  security find-generic-password -s "$KEYCHAIN_SERVICE" -w 2>/dev/null | shasum | awk '{print $1}'
}

echo "==> personal (default, \$HOME)"
( cd "$HOME" && claude -p '/status' ) || true

echo
echo "==> work ($WORK_DIR)"
if [ ! -d "$WORK_DIR" ]; then
  echo "verify: $WORK_DIR does not exist" >&2
  exit 2
fi

BEFORE="$(keychain_hash)"
( cd "$WORK_DIR" && claude -p '/status' ) || true
AFTER="$(keychain_hash)"

echo
echo "==> keychain slot integrity"
echo "    before: ${BEFORE:-<empty>}"
echo "    after:  ${AFTER:-<empty>}"

if [ "$BEFORE" = "$AFTER" ]; then
  echo "    PASS — keychain untouched; the work env token bypassed it."
else
  echo "    FAIL — keychain changed. Something ran /login, or the work .envrc token was empty."
  echo "           Check: cd $WORK_DIR && env | grep -c CLAUDE_CODE_OAUTH_TOKEN   (must print 1)"
  exit 1
fi

echo
echo "Done. Confirm the two /status outputs above show DIFFERENT accounts."
