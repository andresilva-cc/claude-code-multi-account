# claude-code-multi-account

Run two (or more) Claude Code accounts — e.g. a **personal** account and a
**work / enterprise** account — side by side on one Mac, **auto-selected by project directory**.

No tools to install. No script touches your credentials. Just official Claude Code
primitives (`setup-token`, `CLAUDE_CONFIG_DIR`) + [`direnv`](https://direnv.net/).

> **Status:** macOS + zsh. Verified on Claude Code `v2.1.161` with a personal + Team account (June 2026).
> Relies on current macOS keychain behavior and open issue
> [anthropics/claude-code#20553](https://github.com/anthropics/claude-code/issues/20553) —
> see [Why this works](#why-this-works) and [Caveats](#caveats).

---

## The problem

Claude Code stores one logged-in account at a time. The usual "fix" — run `/login` and
switch whenever you change projects — is manual, easy to forget, and error-prone. Worse,
on macOS it's not even enough on its own (see below).

You want: **company projects use the company account, personal projects use the personal
account, automatically, with zero per-session steps.**

## Why not the existing switchers?

Tools like `ccm` and `jean-claude` work, but they're shell scripts that **read and rewrite
your macOS Keychain**. That's a lot of trust for a credential store. This repo takes the
opposite approach: **nothing third-party ever touches your keychain or tokens.** You can
audit the entire setup in the time it takes to read this page.

## Why this works

Two facts about how Claude Code stores state on macOS:

1. **`CLAUDE_CONFIG_DIR` relocates almost everything** — `settings.json`, session history,
   `~/.claude.json`, plugins, MCP config, caches. Point two accounts at two different dirs
   and their *state* is fully isolated.

2. **…except the OAuth token.** On macOS the credential lives in the login **Keychain under
   a single hardcoded item** (`Claude Code-credentials`, keyed to your username) that is
   **not** namespaced by `CLAUDE_CONFIG_DIR`. So two `/login` accounts fight over one slot —
   logging in as B wipes A's refresh token
   ([#20553](https://github.com/anthropics/claude-code/issues/20553)).

The fix is the auth-precedence rule: **`CLAUDE_CODE_OAUTH_TOKEN` outranks the keychain.**
Mint a long-lived token per account with `claude setup-token`, export the right one per
directory via `direnv`, and the binary uses that token and **never touches the shared
keychain slot.** Deterministic, no clobbering.

```
everywhere  ──▶  CLAUDE_CODE_OAUTH_TOKEN = personal   (global default)
~/work/*    ──▶  CLAUDE_CODE_OAUTH_TOKEN = work       (.envrc override via direnv)
```

## Requirements

- macOS, zsh
- [`direnv`](https://direnv.net/) — `brew install direnv`
- `jq` (for the one-time onboarding-flag seed) — `brew install jq`
- Claude Code, logged in (you'll re-auth each account once to mint its token)

## Setup

### 1. Install and hook direnv

```sh
brew install direnv
echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc
```

### 2. Mint a token per account

Each non-default account is a **profile** — a name you choose (`work`, `acme`, `client-x`…).
The convention ties three things to that name, and they must match:

```
profile "work"  ->  config dir ~/.claude-work  +  keychain item Claude-work-Token
```

> Keychain item names are **case-sensitive**. `Claude-work-Token` ≠ `Claude-Work-Token` — use
> the exact same casing as your `PROFILE`, or the `.envrc` reports the token "missing."

Run `setup-token` **while logged into each account**. It mints a long-lived OAuth token
(valid ~1 year). Store each in its own Keychain item — never in plaintext, never in a
screenshot.

```sh
# Personal — this is the default account, no profile needed
claude setup-token
security add-generic-password -s Claude-Personal-Token -a "$USER" -w 'PASTE_PERSONAL_TOKEN'

# Work profile — pick a PROFILE name and use it consistently (here: "work").
# Mint into an isolated config dir so it can't disturb your default profile.
PROFILE=work
mkdir -p ~/.claude-$PROFILE
CLAUDE_CONFIG_DIR=~/.claude-$PROFILE claude setup-token
security add-generic-password -s Claude-$PROFILE-Token -a "$USER" -w 'PASTE_WORK_TOKEN'
```

> Tokens minted into a screenshot or pasted anywhere visible are **burned** — mint a fresh
> one and store only that.

Then mark the new work config dir as **already onboarded**. A fresh `CLAUDE_CONFIG_DIR` hasn't
completed first-run setup, so interactive `claude` would run onboarding and prompt a login —
even though the token is valid (headless `claude -p` works regardless). Seed the flag so it
uses the token instead:

```sh
cfg=~/.claude-$PROFILE/.claude.json
jq '.hasCompletedOnboarding = true' "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"
```

> **Never click "login" on that onboarding screen.** A browser `/login` writes the shared
> keychain slot and breaks isolation. The token is the auth; onboarding just needs marking done.

### 3. Make your personal account the global default

Add to `~/.zshrc`, **before** the `direnv hook` line. Personal-as-default is a deliberate
safety bias: a forgotten switch means *your own* side-project goes to *your own* account —
never company code into a personal, training-eligible account.

```sh
export CLAUDE_CODE_OAUTH_TOKEN="$(security find-generic-password -s Claude-Personal-Token -w)"
```

> **Do not set `CLAUDE_CONFIG_DIR` for personal.** Personal uses the native config dir
> (`~/.claude`). Pointing `CLAUDE_CONFIG_DIR` at `~/.claude` relocates the config file from
> `~/.claude.json` to `~/.claude/.claude.json` and breaks it ("configuration file not found").
> Only *work* profiles set `CLAUDE_CONFIG_DIR`, and only to a **new** dir like `~/.claude-work`.

See [`templates/zshrc-snippet.sh`](templates/zshrc-snippet.sh).

### 4. Override per work directory

Drop an `.envrc` at the root of your work tree (e.g. `~/work/.envrc`), then allow it:

```sh
cp templates/envrc.example ~/work/.envrc
cd ~/work && direnv allow
```

The template has one knob — `PROFILE` at the top. **Set it to the same profile name you
used in step 2** (`work`, `acme`, …); it derives the config dir and keychain item from that,
so there's only one thing to keep in sync. For a second work account, copy the `.envrc` into
that tree and change only `PROFILE`. The template is **fail-closed** — if the token can't be
read it aborts rather than silently falling back to the shared keychain.
See [`templates/envrc.example`](templates/envrc.example).

Now every repo under `~/work` uses that account; everywhere else uses personal. No
aliases, no manual switching.

## Verify it

Run [`verify.sh`](verify.sh) — it confirms a work directory resolves to a **different account
token** than your personal default. It compares the OAuth token each location resolves to
(the real switching mechanism); it's offline and uses no quota.

```sh
./verify.sh ~/work
# second arg overrides the personal keychain item name if you renamed it:
# ./verify.sh ~/work Claude-Personal-Token
```

> Note: it deliberately does **not** call `claude -p '/status'` — slash commands don't run in
> headless (`-p`) mode, so that check would always report "not available." Comparing resolved
> tokens is the reliable, scriptable signal.

## "Claude API" in the header — don't panic

A token-authed profile shows **`Claude API`** in the startup header and a **blank `/usage`**
inside the CLI. This is **not** API billing. A bare token has no stored account session
(`oauthAccount` is `null`), so the CLI can't render your plan name or usage meters and falls
back to a generic label.

Interactive use still bills your **subscription** — confirmed end to end on a **Team** plan:
the web UI's *Settings → Usage* shows the session/weekly meters ticking up, and the admin
billing view shows **$0 direct/overage spend**. The limits are enforced server-side; they're
just not *displayed* in the CLI. Check usage in the **web UI**, not the CLI.

**Confirm it on your own account** rather than taking this on faith — plans and tenants differ:
do some real work, then check *Settings → Usage* in the web UI (the meters should move) and, if
you're on a Team/org plan, have an admin verify **$0 overage** in the billing view. If you see
dollar spend instead of subscription usage, your seat may be API-billed — stop and recheck.

(`claude -p` / headless usage is the exception — as of 2026-06-15 it draws from a separate
Agent SDK credit pool rather than your interactive limits. Normal interactive use is unaffected.)

## Caveats

- **macOS + zsh only.** On Linux/Windows credentials *do* move with `CLAUDE_CONFIG_DIR`, so
  the keychain workaround is unnecessary there.
- **Never run `/login` in a work dir.** That writes the shared keychain slot and undoes the
  isolation. Re-auth by re-running `setup-token` (step 2) instead.
- **Only point `CLAUDE_CONFIG_DIR` at a NEW dir** (e.g. `~/.claude-work`), set before that
  profile's first run. Never point it at the existing `~/.claude` — that relocates
  `~/.claude.json` to `~/.claude/.claude.json` and breaks config. The personal default leaves
  it unset.
- **direnv loads on `cd`, not retroactively.** Start a fresh `claude` per project; `cd`-ing
  mid-session doesn't re-evaluate `.envrc`.
- **Enterprise auth type matters.** This assumes your work seat mints a normal OAuth token
  via `setup-token` (tenant-level accounts do). If yours is API-key or Bedrock/Vertex backed,
  swap the token line for `ANTHROPIC_API_KEY=…` or `CLAUDE_CODE_USE_BEDROCK=1` — both also
  outrank the keychain.
- **Token lifetime isn't officially documented.** Treat as "rotate when it 401s," not
  permanent.
- Behavior depends on a current, partly-undocumented keychain detail and an open bug. If
  Anthropic namespaces the keychain per config dir, the `setup-token` approach still works —
  only the rationale changes.

## Compliance note

Running both accounts is fine. The risk is **routing**: company code must go through the
work/enterprise seat (commercial terms — no training, ZDR). Keep the personal account off
company code, and don't register your personal account under a company-domain email (it can
get auto-linked into the org tenant).

## License

MIT — see [LICENSE](LICENSE).
