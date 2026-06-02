# CLAUDE.md

Runbook for Claude Code to set up multi-account switching **for the user**, end to end.
The README is the human explanation; this is your operational guide. If a user drops this
repo in and says "set this up for me," follow this.

## What you're building

Two Claude Code accounts on one Mac (a default "personal" + one or more "work"), auto-selected
by directory, using only `setup-token` + `CLAUDE_CONFIG_DIR` + direnv. No third-party tool
touches credentials. Read the README's "Why this works" before acting — the load-bearing fact
is that the macOS OAuth token lives in a single keychain item NOT namespaced by
`CLAUDE_CONFIG_DIR`, and `CLAUDE_CODE_OAUTH_TOKEN` overrides it.

## Hard rules

- **Never ask the user to paste a token into the chat, a file, or anywhere you can see it.**
  Tokens are secrets. Have them run `setup-token` themselves and pipe the result straight into
  the keychain. A token that has appeared in plaintext is burned — tell them to re-mint.
- **You cannot run interactive logins.** `claude setup-token` and `/login` open a browser and
  need the user. Hand them the exact command via the `! <cmd>` in-session prefix; don't try to
  run them yourself.
- **Never run `/login` inside a work directory** and never instruct the user to — it rewrites
  the shared keychain slot and breaks isolation. Re-auth = re-run `setup-token`.
- **Don't commit secrets.** No tokens, emails, real org names, or real paths in anything you
  write to this repo.

## Procedure

Confirm preconditions, then drive the user through each step, pausing where their input is
required.

1. **Preconditions** — macOS + zsh; `claude` on PATH; `direnv` installed (`brew install direnv`)
   and hooked in `~/.zshrc`. Ask which directories map to which account (e.g. a work tree path).
2. **Pick a profile name** per non-default account (`work`, `acme`, …). Convention, all keyed
   to that name: config dir `~/.claude-$PROFILE` + keychain item `Claude-$PROFILE-Token` +
   the `PROFILE=` line in that tree's `.envrc`. Keep all three in sync.
3. **Verify the seat can mint a token** — the one real unknown. Ask the user to run
   `! CLAUDE_CONFIG_DIR=~/.claude-$PROFILE claude setup-token`. If it returns an `sk-ant-oat…`
   token, proceed. If it errors (SSO / API-key / Bedrock-Vertex seat), switch that account's
   `.envrc` to `ANTHROPIC_API_KEY` or `CLAUDE_CODE_USE_BEDROCK=1` instead.
4. **Store each token in its own keychain item** — have the user run, with their real token:
   `! security add-generic-password -s Claude-$PROFILE-Token -a "$USER" -w 'TOKEN'`
   (and `Claude-Personal-Token` for personal). You supply the command; they supply the token.
5. **Global default in `~/.zshrc`** — from `templates/zshrc-snippet.sh`, placed BEFORE the
   direnv hook. Personal is the default (safety bias: a slip sends personal code to the
   personal account, never company code to it).
6. **Per-dir override** — copy `templates/envrc.example` to the work tree root as `.envrc`,
   set its `PROFILE=` to match step 2, then have the user `direnv allow` it.
   It's fail-closed on purpose; keep it that way.
7. **Verify** — run `./verify.sh <work-dir>`. Pass = two different `/status` identities AND an
   unchanged keychain hash. If the keychain hash changed, a `/login` ran or the env token was
   empty; check `env | grep CLAUDE_CODE_OAUTH_TOKEN` in the work dir.

## When editing this repo

- Keep the "no third-party code touches credentials" promise — it's the whole point. Don't add
  an installer that reads/writes the keychain on the user's behalf beyond the transparent
  one-line `security` commands above.
- Keep example paths generic (`~/work`), never the maintainer's real paths.
- If macOS keychain behavior or issue #20553 changes, update README "Status" + "Caveats" and
  the version tested, rather than deleting the rationale.
- Shell is zsh-first; if you add Linux/Windows support, gate it clearly (credentials DO move
  with `CLAUDE_CONFIG_DIR` there, so the keychain step is unnecessary).
