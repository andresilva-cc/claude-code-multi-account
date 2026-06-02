# --- claude-code-multi-account: global default account ---
# Add to ~/.zshrc BEFORE the `eval "$(direnv hook zsh)"` line.
# Makes your personal account the default everywhere; per-dir .envrc files override it.
export CLAUDE_CONFIG_DIR="$HOME/.claude"
export CLAUDE_CODE_OAUTH_TOKEN="$(security find-generic-password -s Claude-Personal-Token -w)"

# direnv must be hooked AFTER the exports above so .envrc overrides win.
eval "$(direnv hook zsh)"
