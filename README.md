# claude-code-multi-account

Run two (or more) Claude Code accounts — e.g. a **personal** account and a
**work / enterprise** account — side by side on one Mac, **auto-selected by project directory**.

No tools to install. No script touches your credentials. Just official Claude Code
primitives (`setup-token`, `CLAUDE_CONFIG_DIR`) + [`direnv`](https://direnv.net/).

> **Status:** macOS + zsh. Tested against Claude Code `v2.1.160` (June 2026).
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
- Claude Code, logged in (you'll re-auth each account once to mint its token)

## Setup

### 1. Install and hook direnv

```sh
brew install direnv
echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc
```

### 2. Mint a token per account

Run `setup-token` **while logged into each account**. It mints a long-lived OAuth token
(valid ~1 year). Store each in its own Keychain item — never in plaintext, never in a
screenshot.

```sh
# Personal (while logged into your personal account)
claude setup-token
security add-generic-password -s Claude-Personal-Token -a "$USER" -w 'PASTE_PERSONAL_TOKEN'

# Work (mint it in an isolated config dir so it can't disturb your default profile)
mkdir -p ~/.claude-work
CLAUDE_CONFIG_DIR=~/.claude-work claude setup-token
security add-generic-password -s Claude-Work-Token -a "$USER" -w 'PASTE_WORK_TOKEN'
```

> Tokens minted into a screenshot or pasted anywhere visible are **burned** — mint a fresh
> one and store only that.

### 3. Make your personal account the global default

Add to `~/.zshrc`, **before** the `direnv hook` line. Personal-as-default is a deliberate
safety bias: a forgotten switch means *your own* side-project goes to *your own* account —
never company code into a personal, training-eligible account.

```sh
export CLAUDE_CONFIG_DIR="$HOME/.claude"
export CLAUDE_CODE_OAUTH_TOKEN="$(security find-generic-password -s Claude-Personal-Token -w)"
```

See [`templates/zshrc-snippet.sh`](templates/zshrc-snippet.sh).

### 4. Override per work directory

Drop an `.envrc` at the root of your work tree (e.g. `~/work/.envrc`), then allow it:

```sh
cp templates/envrc.example ~/work/.envrc
cd ~/work && direnv allow
```

The template is **fail-closed** — if the token can't be read it aborts rather than silently
falling back to the shared keychain. See [`templates/envrc.example`](templates/envrc.example).

Now every repo under `~/work` uses the work account; everywhere else uses personal. No
aliases, no manual switching.

## Verify it

Run [`verify.sh`](verify.sh) — it confirms each directory resolves to the right identity
**and** that running the non-default account leaves the keychain byte-for-byte untouched
(proof the env token is bypassing it):

```sh
./verify.sh ~/work
```

## Caveats

- **macOS + zsh only.** On Linux/Windows credentials *do* move with `CLAUDE_CONFIG_DIR`, so
  the keychain workaround is unnecessary there.
- **Never run `/login` in a work dir.** That writes the shared keychain slot and undoes the
  isolation. Re-auth by re-running `setup-token` (step 2) instead.
- **Set `CLAUDE_CONFIG_DIR` before a profile's first run** so `~/.claude.json` is redirected
  too — it isn't moved retroactively.
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
