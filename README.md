# claude-code-multi-account

Run two (or more) Claude Code accounts — e.g. a **personal** account and a
**work / enterprise** account — side by side on one Mac, **auto-selected by project directory**.

No tools to install. No script touches your credentials. Just official Claude Code
primitives (`setup-token`, `CLAUDE_CONFIG_DIR`) + [`direnv`](https://direnv.net/).

> **Status:** macOS (zsh/bash). Verified on Claude Code `v2.1.161` with a personal + Team account (June 2026).
> Linux/Windows: see [Other platforms](#other-platforms).
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

The fix uses the auth-precedence rule — **`CLAUDE_CODE_OAUTH_TOKEN` outranks the keychain** —
but only where needed:

- **Your primary account claims the keychain** via normal `claude /login`. Nothing special;
  it gets a **full subscription session** (real `/usage`, plan display, and login-gated
  features like `/remote-control`).
- **Each additional account** mints a long-lived `setup-token` and exports it per-directory
  via `direnv`. `CLAUDE_CODE_OAUTH_TOKEN` outranks the keychain, so those dirs override
  **without ever writing the shared slot** — no collision, because only the primary account
  touches the keychain.

```
everywhere  ──▶  keychain /login  = personal   (full session; primary account)
~/work/*    ──▶  CLAUDE_CODE_OAUTH_TOKEN = work (.envrc token override via direnv)
```

> **Token-authed accounts can't use login-gated features.** A `setup-token` has no `/login`
> session, so for those (non-primary) accounts **`/remote-control` doesn't work**, and the CLI
> shows "Claude API" with no `/usage` meter (see [that section](#claude-api-in-the-header--dont-panic)).
> They still bill the subscription and work for normal coding. **Put the account you need
> `/remote-control` (or usage visibility) on as the primary/keychain account.**

## Requirements

- macOS, zsh (bash works too — see [Other platforms](#other-platforms))
- [`direnv`](https://direnv.net/) — `brew install direnv`
- `jq` (for the one-time onboarding-flag seed) — `brew install jq`
- Claude Code, logged in (you'll re-auth each account once to mint its token)

## Setup

### 1. Install and hook direnv

```sh
brew install direnv
echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc
```

> bash: use `echo 'eval "$(direnv hook bash)"' >> ~/.bashrc` instead. Everything else is identical.

### 2. Log in your primary account, then mint a token per additional account

**Primary account** — just log in normally. It owns the keychain and gets the full session
(remote control, `/usage`):

```sh
claude /login    # pick your primary (e.g. personal) account
```

**Each additional account** is a **profile** — a name you choose (`work`, `acme`, `client-x`…).
The convention ties three things to that name, and they must match:

```
profile "work"  ->  config dir ~/.claude-work  +  keychain item Claude-work-Token
```

> Keychain item names are **case-sensitive**. `Claude-work-Token` ≠ `Claude-Work-Token` — use
> the exact same casing as your `PROFILE`, or the `.envrc` reports the token "missing."

Mint a token **while logged into that account**. `setup-token` mints a long-lived OAuth token
(valid ~1 year). Store it in its own Keychain item — never in plaintext, never in a screenshot.

```sh
# Work profile — pick a PROFILE name and use it consistently (here: "work").
# Mint into an isolated config dir so it can't disturb your primary login.
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

### 3. Hook direnv (that's it for the default)

Your primary account is already the global default — anywhere without a work `.envrc` falls
through to its keychain `/login` session. So step 3 is just making sure `direnv` is hooked
(from step 1). **Set no Claude env vars for the default** — that's what keeps the primary
account a full `/login` session. This is also a safety bias: a forgotten switch means *your
own* side-project goes to *your own* account, never company code into a personal one.

> **Do not set `CLAUDE_CONFIG_DIR` (or a token) for the default.** It uses the native config
> dir (`~/.claude`). Pointing `CLAUDE_CONFIG_DIR` at `~/.claude` relocates the config file to
> `~/.claude/.claude.json` and breaks it ("configuration file not found"). Only *work* profiles
> set `CLAUDE_CONFIG_DIR`, and only to a **new** dir like `~/.claude-work`.

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

Run [`verify.sh`](verify.sh) — it confirms the work dir resolves a token + its own config dir,
while the default (`$HOME`) resolves **neither** (so it falls through to the keychain `/login`).
That's the whole isolation in one check; it's offline and uses no quota.

```sh
./verify.sh ~/work
```

> Note: it deliberately does **not** call `claude -p '/status'` — slash commands don't run in
> headless (`-p`) mode, so that check would always report "not available." Inspecting the
> resolved env per directory is the reliable, scriptable signal.

## "Claude API" in the header — don't panic

A token-authed profile shows **`Claude API`** in the startup header and a **blank `/usage`**
inside the CLI. This is **not** API billing. A bare token has no stored account session
(`oauthAccount` is `null`), so the CLI can't render your plan name or usage meters and falls
back to a generic label.

For the same reason, **login-gated features don't work on a token-authed account** — notably
**`/remote-control`**. If you need remote control (or the in-CLI usage meter) on a given
account, make it your **primary/keychain account** (`claude /login`, no `.envrc`); only the
*other* accounts ride on tokens. You can only have one keychain login, so pick the account you
most need those features on.

Interactive use still bills your **subscription** — confirmed end to end on a **Team** plan:
the web UI's *Settings → Usage* shows the session/weekly meters ticking up, and the admin
billing view shows **$0 direct/overage spend**. The limits are enforced server-side; they're
just not *displayed* in the built-in panel. Check usage in the **web UI**, not the `/usage` panel.

> **Tip — get a usage readout back in the CLI.** The blank `/usage` is just the built-in panel
> not rendering for token auth. A custom **statusline** (`/statusline`) *does* surface usage for
> these accounts — it pulls from local session data / the usage endpoint, independent of the
> keychain session — so you get an at-a-glance meter in the terminal regardless of auth method.

**Confirm it on your own account** rather than taking this on faith — plans and tenants differ:
do some real work, then check *Settings → Usage* in the web UI (the meters should move) and, if
you're on a Team/org plan, have an admin verify **$0 overage** in the billing view. If you see
dollar spend instead of subscription usage, your seat may be API-billed — stop and recheck.

(`claude -p` / headless usage is the exception — as of 2026-06-15 it draws from a separate
Agent SDK credit pool rather than your interactive limits. Normal interactive use is unaffected.)

## Token expiry & re-minting

`setup-token` tokens last ~1 year. When one expires, the failure is **not** silent — but note
the `.envrc` fail-closed guard won't catch it: it only checks the token is non-empty, and an
expired token is still a non-empty string. So `claude` launches, the server returns **401**,
and you get an auth error — typically the **"Select login method"** screen.

> **Do NOT click login on that screen.** A browser `/login` writes the shared keychain slot and
> clobbers your other account. Re-mint instead:

```sh
PROFILE=work
CLAUDE_CONFIG_DIR=~/.claude-$PROFILE claude setup-token
security add-generic-password -U -s Claude-$PROFILE-Token -a "$USER" -w 'NEW_TOKEN'   # -U updates
```

Open a fresh terminal and you're back. (Same drill for the personal token.)

## Other platforms

- **bash (macOS):** fully supported — use `direnv hook bash` in `~/.bashrc` (see step 1).
  `verify.sh` already runs under bash. Nothing else changes.
- **Linux:** *easier, and you don't need this repo's keychain workaround.* On Linux credentials
  live in a file (`~/.claude/.credentials.json`) and **do** move with `CLAUDE_CONFIG_DIR` — so a
  plain per-dir `CLAUDE_CONFIG_DIR` + normal `claude /login` per account isolates cleanly, no
  `setup-token` dance. *(Untested here — no Linux box to verify on; PRs/reports welcome.)*
- **Windows:** not covered. Credential storage differs again; contributions welcome.

## Caveats

- **macOS-focused** (zsh or bash). Linux/Windows differ — see [Other platforms](#other-platforms);
  the keychain workaround is a macOS-specific need.
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
