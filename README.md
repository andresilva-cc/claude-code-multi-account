# claude-code-multi-account

Run two (or more) Claude Code accounts — e.g. **personal** + **work/enterprise** — side by side
on one Mac, **auto-selected by project directory**, with the native toolchain in both.

Two approaches; pick by what you need from the *secondary* account:

| | **A — HOME-overlay** (recommended) | **B — Token** (lightweight) |
|---|---|---|
| Secondary account session | **full `/login`** | bare token |
| `/remote-control`, in-CLI `/usage` | **yes** | no (shows "Claude API") |
| Native toolchain (no reinstall) | yes | yes |
| How it isolates | its own `$HOME` → its own keychain | per-dir `CLAUDE_CONFIG_DIR` + token |
| One-time setup | run one script (overlay + keychain) | mint a `setup-token` |
| Best when | you want the secondary account to be first-class | you just need it to code, minimal setup |

> **Status:** macOS (zsh/bash). Verified on Claude Code `v2.1.177` with personal + Team accounts
> (June 2026). Linux/Windows: see [Other platforms](#other-platforms). Builds on official
> primitives and the keychain behavior around [anthropics/claude-code#20553](https://github.com/anthropics/claude-code/issues/20553).

---

## The problem

Claude Code keeps **one logged-in account at a time**, and on macOS a `/login` session lives in a
**single hardcoded Keychain item** (`Claude Code-credentials`) that isn't namespaced — so two
`/login` accounts fight over one slot and clobber each other ([#20553](https://github.com/anthropics/claude-code/issues/20553)).
Switching by hand (`/login` each time you change projects) is manual and error-prone. You want
company projects on the company account, personal on personal, **automatically, both live at once**.

## The key fact

A *full* `/login` session is stored in the macOS keychain at **`$HOME/Library/Keychains/login.keychain-db`**
— resolved via **`$HOME`**. So you can give two accounts independent keychains by isolating along
exactly one of three boundaries: **`$HOME`** (overlay), a **second macOS user**, or an **OS boundary**
(container/VM). Anything else can't give two *simultaneous full sessions*.

- **Approach A** isolates by `$HOME` — each account gets its own keychain and a real `/login`.
- **Approach B** sidesteps the keychain entirely: `CLAUDE_CODE_OAUTH_TOKEN` outranks it, so a
  per-directory token routes the secondary account without writing the shared slot. Simpler — but a
  token has no `/login` session, so that account loses `/remote-control` and the in-CLI `/usage` meter.

---

## Approach A — HOME-overlay (recommended)

### How it works

Give the secondary account its **own `$HOME`** — `~/work-home`, a **symlink overlay** of your real home:

- **Shared** (symlinks → real `$HOME`): your toolchain (`.nvm`, pnpm, `.npmrc`), `.config`, `.cache`,
  `.gitconfig`, `.ssh`, shell rc — so git/ssh/node behave identically.
- **Separate** (real dirs): `.claude`, `.claude.json`, `Library/Keychains` — its own config + keychain.

Run claude with `HOME=~/work-home` and it's **vanilla claude on a separate keychain**: a real
`/login` session (remote control, `/usage`, no "Claude API" label). The toolchain stays native
because **binaries resolve via `PATH` (absolute paths), independent of `$HOME`** — zero reinstall.

### Setup

```sh
brew install direnv jq
./setup-overlay.sh work        # builds ~/work-home + a separate keychain + a claude-work wrapper + a direnv shim
claude-work                    # then run /login and pick the work account
```

Auto-route by directory — in each work tree:

```sh
echo 'PATH_add "$HOME/.claude-shims/work"' > .envrc && direnv allow   # see templates/envrc.overlay.example
```

Now `claude`/`clauded` in that tree → **work**; everywhere else → your **primary** account. Confirm
in-session: `/status` (real account, not "Claude API"), `/usage` (meters render), `/remote-control`.

[`setup-overlay.sh`](setup-overlay.sh) is short and auditable — read it before running.

### Why it's automatic *and* safe

The shim only changes which binary `claude` *resolves to* inside a work tree; the wrapper flips
`HOME` for the **claude process only**, so your shell (history, git, prompt) is untouched. The
failure mode is the safe one: a stray `claude` *outside* a work tree hits your primary account —
never company code on the personal account.

### Keychain unlock

The overlay keychain isn't your login keychain, so it doesn't auto-unlock at GUI login.
`setup-overlay.sh` stores its password **in your personal login keychain** (which *does* auto-unlock),
and the wrapper retrieves it on demand — no plaintext file.

### Terminal multiplexers (cmux)

If you run Claude Code inside [cmux](https://github.com/cmuxterm/cmux), the wrapper auto-routes
through cmux's own wrapper when in a cmux session, so the secondary account's sessions still show
in the sidebar. It's gated on `CMUX_SURFACE_ID` + the cmux app being present — **a no-op if you
don't use cmux** (the wrapper just execs claude directly).

### Migrating an existing token profile's config + transcripts

Moving off Approach B (a token profile at `~/.claude-work`) into the overlay — note `.claude.json`
sits at a different path under `$HOME` than under `CLAUDE_CONFIG_DIR`:

```sh
NEW=~/work-home
cp -a "$NEW/.claude" "$NEW/.claude.bak" && cp -a "$NEW/.claude.json" "$NEW/.claude.json.bak"   # back up first
# transcripts + config (everything except .claude.json)
rsync -a --exclude='.claude.json' ~/.claude-work/ "$NEW/.claude/"
# merge .claude.json: old as base (project-trust / MCP / history), new overlaid so the /login wins
jq -s '.[0] * .[1]' ~/.claude-work/.claude.json "$NEW/.claude.json" > "$NEW/.claude.json.tmp" \
  && mv "$NEW/.claude.json.tmp" "$NEW/.claude.json"
```

Memories (`projects/<slug>/memory/`) ride along with the rsync. Verify `/status` + your history,
then delete `~/.claude-work`.

### Blast radius — what to know

`HOME` redirects **everything** HOME-relative, which is why the overlay symlinks your toolchain and
dotfiles. Consequences:

- **Keyring tools.** `gh` keeps its token in the macOS keychain, so it won't see it under the overlay.
  The wrapper **bridges `gh` automatically** (reads `gh auth token` while `HOME` is real, exports
  `GH_TOKEN`, which outranks the keyring). If another keychain-based tool breaks in the overlay,
  bridge it the same way. Most dev tools use file config (symlinked) and are fine.
- **`/doctor` PATH warning** is cosmetic — `$HOME/.local/bin` under the overlay is a symlink to the
  real `.local/bin` already in `PATH`; the wrapper re-adds it so the check passes.
- A tool that writes a **non-symlinked** `~/path` forks its config into the overlay. If you rely on a
  dotfile not in the script's shared list, add a symlink.

---

## Approach B — Token (lightweight)

Your **primary** account uses normal `claude /login` (owns the keychain, full session). Each
**additional** account mints a long-lived `setup-token` and is selected per-directory via `direnv`;
`CLAUDE_CODE_OAUTH_TOKEN` outranks the keychain, so it never writes the shared slot.

```sh
brew install direnv jq
echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc        # bash: direnv hook bash >> ~/.bashrc

# additional account — pick a PROFILE name; config dir + keychain item derive from it
PROFILE=work
mkdir -p ~/.claude-$PROFILE
CLAUDE_CONFIG_DIR=~/.claude-$PROFILE claude setup-token            # mint while logged into that account
security add-generic-password -s Claude-$PROFILE-Token -a "$USER" -w 'PASTE_TOKEN'   # case-sensitive name
jq '.hasCompletedOnboarding = true' ~/.claude-$PROFILE/.claude.json > /tmp/c \
  && mv /tmp/c ~/.claude-$PROFILE/.claude.json                     # skip first-run onboarding/login prompt
```

Per work tree: `cp templates/envrc.example ~/work/.envrc`, set `PROFILE` at its top, `direnv allow`.
The template is fail-closed (aborts if the token is missing rather than falling back to the keychain).
Verify with [`verify.sh`](verify.sh) `~/work`. See [`templates/envrc.example`](templates/envrc.example)
and [`templates/zshrc-snippet.sh`](templates/zshrc-snippet.sh).

**Known limits of Approach B** (all solved by Approach A):
- The secondary account shows **"Claude API"** in the header and a **blank `/usage`** — a bare token
  has no stored account session, so the CLI can't render the plan/meters. It still **bills the
  subscription** (verified on a Team plan: web-UI meters move, admin billing shows $0 overage —
  check the **web UI**, not the CLI panel). A custom `/statusline` can surface usage anyway.
- **`/remote-control` doesn't work** on a token-authed account (no `/login` session).
- **Never run `/login` in a token work dir** — it writes the shared keychain slot and breaks isolation.
- **Token expiry (~1yr)** surfaces as a 401 / "Select login method" — **don't click login**; re-mint:
  `CLAUDE_CONFIG_DIR=~/.claude-$PROFILE claude setup-token` then `security add-generic-password -U …`.
- **Enterprise auth type matters** — if the seat is API-key or Bedrock/Vertex backed, swap the token
  line for `ANTHROPIC_API_KEY=…` or `CLAUDE_CODE_USE_BEDROCK=1`.

---

## Caveats (both approaches)

- **macOS-focused** (zsh or bash). Linux/Windows differ — see [Other platforms](#other-platforms).
- **direnv loads on `cd`, not retroactively.** Start a fresh `claude` per project.
- Behavior leans on current, partly-undocumented macOS keychain details and [#20553](https://github.com/anthropics/claude-code/issues/20553).
  If Anthropic namespaces the keychain per config dir, both approaches still work — only the rationale shifts.
- `claude -p` / headless and Agent-SDK/subagent usage bill per the **active account's** plan and (as of
  2026-06-15) draw from a pool separate from interactive limits — so heavy agent use on a smaller plan
  can incur overage. Route programmatic tools at the account you intend to bill.

## Compliance note

Running both accounts is fine; the risk is **routing**. Company code must go through the work/enterprise
seat (commercial terms — no training, ZDR). Keep the personal account off company code, and don't
register your personal account under a company-domain email (it can get auto-linked into the org tenant).

## Other platforms

- **bash (macOS):** supported — `direnv hook bash` in `~/.bashrc`; the scripts run under bash.
- **Linux:** *easier — you need neither approach's keychain work.* Credentials live in a file
  (`~/.claude/.credentials.json`) and **do** move with `CLAUDE_CONFIG_DIR`, so per-dir `CLAUDE_CONFIG_DIR`
  + normal `/login` per account isolates cleanly. *(Untested here; PRs welcome.)*
- **Windows:** not covered. Credential storage differs again; contributions welcome.

## License

MIT — see [LICENSE](LICENSE).
