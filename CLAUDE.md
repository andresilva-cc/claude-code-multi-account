# CLAUDE.md

Runbook for Claude Code to set this up **for the user**. The README is the human explanation;
this is your operational guide. If a user drops this repo in and says "set this up for me," follow this.

## What you're building

Two Claude Code accounts on one Mac, auto-selected by directory. Two approaches:

- **A — HOME-overlay (recommended).** The secondary account gets its own `$HOME` (`~/<profile>-home`,
  a symlink overlay) → its own keychain + `~/.claude` → a real `/login` session (remote control,
  `/usage`, native toolchain). Driven by [`setup-overlay.sh`](setup-overlay.sh).
- **B — Token (lightweight).** Per-dir `CLAUDE_CONFIG_DIR` + `setup-token`; `CLAUDE_CODE_OAUTH_TOKEN`
  outranks the keychain. Simpler, but the secondary account shows "Claude API" and loses
  `/remote-control` + the in-CLI `/usage` meter.

Load-bearing fact for both: the macOS `/login` session lives in the keychain at
`$HOME/Library/Keychains/login.keychain-db`, resolved by `$HOME`, in one un-namespaced item
(`Claude Code-credentials`, [#20553](https://github.com/anthropics/claude-code/issues/20553)).

Load-bearing fact for cmux (Approach A only): cmux persists `CMUX_CUSTOM_CLAUDE_PATH` per workspace
but **not** `HOME`, so auto-resume replays that path under the real (personal) `HOME`. The wrapper
must therefore capture **itself** (not the real `claude`) as `CMUX_CUSTOM_CLAUDE_PATH`, so resume
re-enters the wrapper and re-overlays `HOME`; a `== $SELF` guard keeps it to one cmux-wrap pass.
Capturing the real binary makes resumed work sessions run as the **primary** account (untrusted tree
+ "No conversation found"). See `setup-overlay.sh` cmux block and README "Terminal multiplexers".

**Default to Approach A** unless the user explicitly wants the minimal-setup token path or doesn't
care about remote-control/usage on the secondary account.

## Hard rules

- **Never ask the user to paste a token/secret where you can see it.** Have them run interactive
  commands themselves. A secret that appeared in plaintext is burned — tell them to re-mint/rotate.
- **You cannot run interactive logins.** `claude /login` and `claude setup-token` open a browser.
  Hand the user the exact command (`! <cmd>`); don't run them yourself.
- **Don't commit secrets or real identity.** No tokens, emails, real org names, or the maintainer's
  real paths in anything you write to this repo. Keep examples generic (`work`, `~/work-home`).

## Approach A — procedure

1. **Preconditions** — macOS; `claude` at `~/.local/bin/claude`; `direnv` installed + hooked. Ask
   which directories map to which account.
2. **Run the setup** — `./setup-overlay.sh <profile>` (e.g. `work`). It builds the overlay, a separate
   keychain (password stashed in the personal login keychain), the `claude-<profile>` wrapper, and the
   direnv shim. Read it first; it's auditable.
3. **Log in** — have the user run `! claude-<profile>` then `/login` and pick that account (interactive).
4. **Auto-route** — in each work tree: `echo 'PATH_add "$HOME/.claude-shims/<profile>"' > .envrc` then
   `direnv allow`. (Template: `templates/envrc.overlay.example`.)
5. **Verify** — user runs `claude` in a work tree → `/status` shows the real account (not "Claude API"),
   `/usage` renders, `/remote-control` connects. Outside work trees, `claude` = primary account.
6. **Migrate (if moving off a token profile)** — see the README "Migrating" recipe: `rsync` everything
   except `.claude.json` into `~/<profile>-home/.claude/`, then `jq -s '.[0]*.[1]'` merge `.claude.json`
   (old base, new login overlaid). Back up first; verify before deleting the old dir.
7. **Blast-radius checks** — keyring tools (`gh`) are bridged by the wrapper; if another breaks in the
   overlay, bridge its credential via env in the wrapper. The `/doctor` PATH warning is cosmetic.

## Approach B — procedure (only if the user opts for it)

1. Primary account = normal `claude /login` (owns the keychain; set no env vars for it).
2. Per additional account: pick a `PROFILE`; config dir `~/.claude-$PROFILE` + keychain item
   `Claude-$PROFILE-Token` + the `PROFILE=` in that tree's `.envrc` must all match (case-sensitive).
3. Mint: `! CLAUDE_CONFIG_DIR=~/.claude-$PROFILE claude setup-token`; store with
   `! security add-generic-password -U -s Claude-$PROFILE-Token -a "$USER" -w 'TOKEN'`.
4. Seed onboarding: `jq '.hasCompletedOnboarding = true' ~/.claude-$PROFILE/.claude.json > /tmp/c && mv …`
   — and tell the user to NEVER click "login" on the onboarding screen (clobbers the keychain).
5. Per work tree: copy `templates/envrc.example`, set `PROFILE`, `direnv allow`. Verify with
   `./verify.sh <work-dir>` (work dir resolves a token + config dir; `$HOME` resolves neither).

## When editing this repo

- Keep `setup-overlay.sh` auditable and idempotent; it must never touch the user's real `~/.claude`
  or personal login keychain beyond the one password item it stores.
- Keep examples generic (`work`, `~/work-home`); never the maintainer's real paths/emails/org.
- If macOS keychain behavior or [#20553](https://github.com/anthropics/claude-code/issues/20553)
  changes, update the README "Status"/"Caveats" and the version tested rather than deleting rationale.
- macOS-first; if you add Linux/Windows, gate it clearly (credentials are file-based there, so neither
  approach's keychain work is needed).
