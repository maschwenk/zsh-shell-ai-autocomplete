# zsh-autosuggest-ai.plugin.zsh
# AI-powered autosuggestions strategy for zsh-autosuggestions
#
# Requirements:
# - zsh-autosuggestions plugin installed
# - suggestd daemon running (bin/suggestd start)
#
# Usage:
#   source this file in your .zshrc
#   export ZSH_AUTOSUGGEST_USE_ASYNC=1
#   export ZSH_AUTOSUGGEST_STRATEGY=(history completion ai)

# Configuration
: ${ZSH_AUTOSUGGEST_AI_SCRIPT:="${0:A:h}/../bin/aisuggest"}
: ${ZSH_AUTOSUGGEST_AI_MIN_BUFFER_LEN:=2}
: ${ZSH_AUTOSUGGEST_AI_HISTORY_SIZE:=20}
: ${ZSH_AUTOSUGGEST_AI_MAX_TOKENS:=16}
: ${ZSH_AUTOSUGGEST_AI_TIMEOUT:=0.5}

# Export timeout for aisuggest
export AISUGGEST_TIMEOUT="${ZSH_AUTOSUGGEST_AI_TIMEOUT}"

# AI strategy function
# This gets called by zsh-autosuggestions when AI is in the strategy list
_zsh_autosuggest_strategy_ai() {
    local buffer=$1
    local -a history_lines
    local -A aliases_map
    local json_input

    # Only suggest for buffers that are long enough
    if [[ ${#buffer} -lt $ZSH_AUTOSUGGEST_AI_MIN_BUFFER_LEN ]]; then
        return
    fi

    # Skip if buffer is only whitespace
    if [[ -z "${buffer//[[:space:]]/}" ]]; then
        return
    fi

    # Check if aisuggest script exists and is executable
    if [[ ! -x "$ZSH_AUTOSUGGEST_AI_SCRIPT" ]]; then
        # Silently skip if script not available
        return
    fi

    # Collect recent history
    # Use fc to get last N commands, excluding the current line
    history_lines=("${(@f)$(fc -ln -$ZSH_AUTOSUGGEST_AI_HISTORY_SIZE | sed 's/^[[:space:]]*//')}")

    # Collect command aliases
    # Get all aliases and format them for JSON
    local alias_name alias_value
    for alias_name in ${(k)aliases}; do
        alias_value="${aliases[$alias_name]}"
        aliases_map[$alias_name]="$alias_value"
    done

    # Build JSON payload
    # We need to properly escape strings for JSON
    local buffer_json=$(printf '%s' "$buffer" | python3 -c 'import json, sys; print(json.dumps(sys.stdin.read().rstrip("\n")))')
    local cwd_json=$(printf '%s' "$PWD" | python3 -c 'import json, sys; print(json.dumps(sys.stdin.read().rstrip("\n")))')

    # Build history array
    local history_json="[]"
    if (( ${#history_lines[@]} > 0 )); then
        # Use python to properly escape and format history array
        history_json=$(printf '%s\n' "${history_lines[@]}" | python3 -c '
import json, sys
lines = [line.rstrip() for line in sys.stdin if line.strip()]
print(json.dumps(lines[-20:]))  # Last 20 items
')
    fi

    # Build aliases object
    local aliases_json="{}"
    if (( ${#aliases_map[@]} > 0 )); then
        # Use python to build aliases JSON
        aliases_json=$(python3 -c "
import json, sys
aliases = {}
$(for alias_name in ${(k)aliases_map}; do
    printf 'aliases[%s] = %s\n' \
        "$(printf '%s' "$alias_name" | python3 -c 'import json, sys; print(json.dumps(sys.stdin.read().rstrip("\n")))')" \
        "$(printf '%s' "${aliases_map[$alias_name]}" | python3 -c 'import json, sys; print(json.dumps(sys.stdin.read().rstrip("\n")))')"
done)
print(json.dumps(aliases))
" 2>/dev/null) || aliases_json="{}"
    fi

    # Build complete JSON input
    json_input=$(cat <<EOF
{
  "buffer": $buffer_json,
  "cwd": $cwd_json,
  "history": $history_json,
  "aliases": $aliases_json,
  "max_tokens": $ZSH_AUTOSUGGEST_AI_MAX_TOKENS
}
EOF
)

    # Call aisuggest with JSON input
    # The suggestion will be just the suffix to append
    local suggestion
    suggestion=$(printf '%s' "$json_input" | "$ZSH_AUTOSUGGEST_AI_SCRIPT" 2>/dev/null)

    # If we got a suggestion, output the full completion (buffer + suffix)
    if [[ -n "$suggestion" ]]; then
        # zsh-autosuggestions expects the full line, not just the suffix
        printf '%s' "${buffer}${suggestion}"
    fi
}

# Optional: Add a keybinding to manually trigger AI suggestion
# bindkey '^[a' autosuggest-execute  # Alt+a to accept and execute
# bindkey '^[s' autosuggest-accept   # Alt+s to accept suggestion

# Informational message on plugin load (only if in interactive shell)
if [[ -o interactive ]]; then
    # Check if daemon is running
    if ! curl -s http://127.0.0.1:11435/health >/dev/null 2>&1; then
        echo "[zsh-autosuggest-ai] Warning: suggestd daemon not running"
        echo "[zsh-autosuggest-ai] Start with: $(dirname $ZSH_AUTOSUGGEST_AI_SCRIPT)/suggestd start"
    fi
fi
