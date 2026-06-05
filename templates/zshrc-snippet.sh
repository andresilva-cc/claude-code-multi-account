# --- claude-code-multi-account: default account + direnv ---
# Add the direnv hook to ~/.zshrc (bash: ~/.bashrc, with `direnv hook bash`).
#
# Your PRIMARY account is the default everywhere: it owns the keychain via normal
# `claude /login`, so set NO Claude env vars here. That keeps it a full subscription
# session (real /usage + /remote-control). Per-dir .envrc files override it for work.
#
# Do NOT set CLAUDE_CONFIG_DIR or a token for the default — pointing CLAUDE_CONFIG_DIR at
# ~/.claude relocates ~/.claude.json to ~/.claude/.claude.json and breaks config. Only work
# profiles set CLAUDE_CONFIG_DIR (to a new dir like ~/.claude-work) in their .envrc.

eval "$(direnv hook zsh)"
