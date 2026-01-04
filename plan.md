# PLAN.md — AI-powered zsh-autosuggestions (local, <1GB RAM, low latency)

## Goals
- Provide zsh autosuggestions that *feel* instantaneous:
  - Tier A: normal zsh-autosuggestions sources (history/completion) always available.
  - Tier B: AI suggestions appear shortly after typing pause; never block input.
- Run entirely locally on macOS (Apple Silicon M4), with a daemon using < 1GB RAM.
- Suggestions are “ghost text” only (no auto-execution).
- Safe-by-default: avoid suggesting destructive commands unless user already typed them.

## Non-goals
- Full “shell agent” that runs commands or edits files automatically.
- Huge context / deep reasoning. Keep prompts small and completions short.

---

## Architecture Overview

### Components
1) `llama-server` (daemon)
- Runs llama.cpp HTTP server on localhost (Metal acceleration enabled).
- Loads a small model (Llama 3.2 1B instruct) quantized to ~0.8GB.
- Hard constraints for low RAM: small ctx, single sequence, mmap.

2) `aisuggest` (client)
- CLI tool invoked by zsh-autosuggestions async worker.
- Inputs: current buffer + minimal context (cwd, last N commands, optional repo hint).
- Outputs: ONLY the suggested suffix (no newline).

3) `zsh-autosuggest-ai` strategy
- A zsh-autosuggestions strategy that queries `aisuggest`.
- Works with `ZSH_AUTOSUGGEST_USE_ASYNC=1` so expensive calls run in background.

### Data flow
- User types -> zsh-autosuggestions computes suggestion.
- Strategy order: history/completion first; AI is last fallback or “enhancer”.
- When AI returns, autosuggestion updates; if stale (buffer changed), ignore.

---

## Performance & Resource Budgets

### Latency budget (end-to-end)
- Target median: 120–250ms for AI suggestion availability after a short typing pause.
- Debounce: 80–150ms after last keystroke before launching AI request.

### Memory budget (daemon RSS)
- < 1GB target:
  - 1B model quantized ~0.8GB
  - ctx-size: 256–512
  - parallel: 1
  - mmap: enabled
  - optional: quantize KV cache if needed

### Suggestion length
- Cap output: 8–24 tokens (short continuations).
- Stop sequences: newline always; optionally stop at `;`.

---

## Repo Layout

.
├── PLAN.md
├── README.md
├── bin/
│   ├── suggestd         # starts llama-server with safe flags
│   └── aisuggest        # calls llama-server and prints suffix
├── config/
│   ├── prompt.txt       # stable system + instruction prompt (no chatty text)
│   └── safety_rules.md  # documented post-filters
└── zsh/
    ├── zsh-autosuggest-ai.plugin.zsh  # strategy + config
    └── _zsh_autosuggest_strategy_ai   # strategy function (optional split file)

---

## Step 1 — Choose model & install llama.cpp

### Model choice (under 1GB)
- Primary: Llama 3.2 1B Instruct GGUF (Q4_K_M or Q4_K_S)
- Keep a local path:
  - models/Llama-3.2-1B-Instruct-Q4_K_M.gguf

### Install llama.cpp
Option A: Homebrew (simplest)
- brew install llama.cpp

Option B: build from source (if you want newest Metal perf)
- git clone https://github.com/ggml-org/llama.cpp
- cmake -B build -DGGML_METAL=ON
- cmake --build build -j

---

## Step 2 — Run the daemon (`bin/suggestd`)

### Requirements
- Bind only to localhost (127.0.0.1) on a fixed port, e.g. 11435.
- Use Metal, mmap, and hard resource limits.

### `bin/suggestd` responsibilities
- Validate model file exists.
- Start server with:
  - ctx-size: 256 (start) -> 512 (if you need more)
  - parallel: 1
  - temp: low (0–0.3)
  - top_p/top_k: conservative
  - max tokens: 24
  - stop: "\n"

### Example command (tune flags after measuring)
llama-server \
  --host 127.0.0.1 --port 11435 \
  -m models/Llama-3.2-1B-Instruct-Q4_K_M.gguf \
  --ctx-size 256 \
  --parallel 1 \
  --threads 6 \
  --n-gpu-layers 99 \
  --mmap \
  --no-webui

### Optional: KV-cache quantization if RSS too high
- Use cache-type-k/cache-type-v (e.g. q8_0, q4_0) and re-measure.

---

## Step 3 — Implement `bin/aisuggest` (client)

### Input contract
aisuggest reads a JSON payload from stdin (single line), e.g.
{
  "buffer": "git ch",
  "cwd": "/Users/max/dev/repo",
  "history": ["git status", "git checkout main", ...],
  "aliases": {"g":"git"},
  "max_tokens": 16
}

### Output contract
- Prints ONLY a suffix (string) with no newline characters inside.
- If no good suggestion: print nothing and exit 0.

### HTTP API approach (simple)
- Use llama.cpp OpenAI-compatible `POST /v1/completions` or `POST /completion`.
- Prompt format: deterministic + short. Must instruct: “return only suffix”.

### Prompt template (key constraints)
- Never output the full command; output only the continuation suffix.
- No explanations.
- Must be valid shell text.
- Must not include newline.

Example prompt (conceptual):
SYSTEM:
You are a shell autosuggestion engine. Output ONLY the continuation suffix. No prose.

USER:
CWD: ...
BUFFER: ...
RECENT_HISTORY:
- ...
ALIASES:
- ...
Return the best suffix to append to BUFFER.

### Post-processing rules (required)
After receiving text:
- Strip leading whitespace unless user’s buffer ends with whitespace.
- Remove surrounding quotes if they don’t match buffer context.
- Reject if contains:
  - newline or carriage return
  - ASCII control chars
- Reject or down-rank dangerous ops unless user already typed the dangerous verb:
  - rm, dd, mkfs, shutdown, reboot
  - git push --force, kubectl delete, terraform destroy
- If rejected: output nothing.

### Latency optimizations
- Add a short timeout (e.g. 250ms–500ms) so AI never stalls UX.
- Prefer keep-alive if you use a library (curl spawns process overhead).
- Keep prompt under ~300–600 tokens max.

---

## Step 4 — Add zsh-autosuggestions AI strategy

### Prefer integrating with zsh-autosuggestions (instead of reinventing)
- Use built-in async mode:
  - export ZSH_AUTOSUGGEST_USE_ASYNC=1
- Add AI as a strategy:
  - export ZSH_AUTOSUGGEST_STRATEGY=(history completion ai)

### `zsh/zsh-autosuggest-ai.plugin.zsh` tasks
1) Define `_zsh_autosuggest_strategy_ai` function.
2) In that function:
   - Read $BUFFER and $PWD
   - Collect recent history (last 20–50):
     - fc -ln -20 (or -50)
   - Call `aisuggest` (stdin JSON) and capture result.
   - Set `suggestion` variable (the suffix or full suggestion per strategy API).
3) Ensure AI only runs when:
   - buffer length >= 2–3 chars
   - buffer not empty and not purely whitespace
   - optionally: only if Tier A has no suggestion or low confidence

### Staleness / cancellation
- Rely on zsh-autosuggestions async cancellation (it re-runs and replaces results).
- Also embed a request-id in payload:
  - request_id = $EPOCHREALTIME + random
- When result returns, compare to current $BUFFER; if changed, ignore.

---

## Step 5 — Safety & UX polish

### Safety filters (must-have)
- “Do no harm” default:
  - Never suggest destructive commands unless user already typed the key verb.
  - Never suggest pipes to sudo unless user already typed sudo.
- Add a denylist + allowlist:
  - Denylist: rm, dd, mkfs, :(){:|:&};:, curl | sh, etc.
  - Allowlist: ls, cd, cat, rg, git status, git diff, etc.

### UX rules
- Suggestion should feel like a continuation, not a rewrite:
  - If model outputs a full command, convert to suffix by removing the buffer prefix if it matches.
  - If it doesn’t match, discard.

### Debounce
- Configure zsh-autosuggestions’ async delay if needed (or implement lightweight debounce in AI strategy):
  - Example: don’t call AI if last keystroke < 100ms ago.

---

## Step 6 — Observability & Benchmarking

### Measure daemon RSS
- Record RSS right after load and after running a few suggestions.
- Script: ps -o rss= -p $(pgrep -x llama-server)

### Measure tokens/sec (sanity)
- Use llama-bench or a simple prompt with fixed output tokens.

### Measure end-to-end latency
- In `aisuggest`, log timestamps:
  - t0 before HTTP
  - t1 after response
  - print (t1 - t0) to stderr when DEBUG=1

### Acceptance criteria
- Typing never lags.
- AI suggestion appears within ~250ms after a short pause most of the time.
- Daemon stays < 1GB RSS in steady state.
- No newline suggestions; no unsafe suggestions by default.

---

## Step 7 — Packaging for daily use

### Launching the daemon
- Option A: manual
  - bin/suggestd
- Option B: launchd agent (macOS)
  - Provide a plist that starts at login and restarts on crash.

### Zsh install
- Source the plugin in .zshrc:
  - source /path/to/zsh/zsh-autosuggest-ai.plugin.zsh
- Ensure `ZSH_AUTOSUGGEST_USE_ASYNC=1` and strategy order.

---

## Step 8 — Future enhancements (optional)

1) Prompt caching / prefix caching
- Keep a stable “system” prefix constant so prompt processing is minimized.

2) Smarter context
- If in a git repo: include branch name + short status summary (cached).
- Directory listing: only include top N entries, avoid huge dirs.

3) Grammar / constrained decoding
- Constrain to shell-ish characters and stop at newline/semicolon.

4) Multi-model fallback
- If AI times out: show Tier A suggestion only.

---

## Implementation Checklist (copy/paste into issues)

- [ ] Install llama.cpp (brew or build) with Metal
- [ ] Download 1B GGUF quant (Q4_K_M or Q4_K_S) into models/
- [ ] Write bin/suggestd (start/stop, validate flags)
- [ ] Write bin/aisuggest (stdin JSON -> HTTP -> suffix)
- [ ] Add safety post-filter + dangerous-command gating
- [ ] Add zsh strategy `_zsh_autosuggest_strategy_ai`
- [ ] Wire strategy order: (history completion ai) and enable async
- [ ] Add debug logging + latency measurement
- [ ] Verify RSS < 1GB and tune ctx/cache types if needed
- [ ] Document setup in README.md

