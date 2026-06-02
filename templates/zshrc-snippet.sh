# --- claude-code-multi-account: global default account ---
# Add to ~/.zshrc BEFORE the `eval "$(direnv hook zsh)"` line.
# Makes your personal account the default everywhere; per-dir .envrc files override it.
#
# Do NOT set CLAUDE_CONFIG_DIR for the personal default. Personal lives on the NATIVE
# config dir (~/.claude), and pointing CLAUDE_CONFIG_DIR at ~/.claude relocates the config
# file from ~/.claude.json to ~/.claude/.claude.json — which breaks it ("configuration file
# not found"). Only pin the token; work profiles set their own CLAUDE_CONFIG_DIR in .envrc.
export CLAUDE_CODE_OAUTH_TOKEN="$(security find-generic-password -s Claude-Personal-Token -w)"

# direnv must be hooked AFTER the export above so .envrc overrides win.
eval "$(direnv hook zsh)"
