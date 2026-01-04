# AI-Powered Zsh Autosuggestions

Local, low-latency AI autosuggestions for your shell. Runs entirely on your Mac (Apple Silicon) with <1GB RAM usage.

## Features

- **Instant suggestions**: AI suggestions appear within ~250ms after you stop typing
- **Low resource usage**: <1GB RAM using a quantized 1B parameter model
- **Safe by default**: Never suggests destructive commands unless you've already typed them
- **Local and private**: Everything runs on your machine, no data sent to external services
- **Non-blocking**: Uses zsh-autosuggestions async mode; typing is never laggy

## Requirements

- macOS with Apple Silicon (M1/M2/M3/M4)
- zsh shell
- [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions) plugin
- Python 3.6+
- llama.cpp with Metal support

## Installation

### 1. Install llama.cpp

```bash
# Option A: Using Homebrew (recommended)
brew install llama.cpp

# Option B: Build from source for latest Metal optimizations
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp
cmake -B build -DGGML_METAL=ON
cmake --build build -j
# Add to PATH or symlink the llama-server binary
```

### 2. Download the model

Download a quantized Llama 3.2 1B Instruct model (~800MB):

```bash
mkdir -p models
cd models

# Download from Hugging Face (example)
# You can use any Llama 3.2 1B Instruct GGUF Q4_K_M or Q4_K_S quantization
wget https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf
```

Alternative models that work well:
- `Llama-3.2-1B-Instruct-Q4_K_M.gguf` (~800MB, recommended)
- `Llama-3.2-1B-Instruct-Q4_K_S.gguf` (~700MB, slightly faster)

### 3. Install zsh-autosuggestions

If you don't have it already:

```bash
# Using Oh My Zsh
# Add 'zsh-autosuggestions' to plugins in ~/.zshrc

# Or install manually
git clone https://github.com/zsh-users/zsh-autosuggestions ~/.zsh/zsh-autosuggestions
```

### 4. Configure your .zshrc

Add to your `~/.zshrc`:

```bash
# Enable zsh-autosuggestions (if installed manually)
source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh

# Enable async mode (required for AI suggestions)
export ZSH_AUTOSUGGEST_USE_ASYNC=1

# Configure strategy order: try history first, then completion, then AI
export ZSH_AUTOSUGGEST_STRATEGY=(history completion ai)

# Source the AI plugin
source /path/to/ai-autocomplete/zsh/zsh-autosuggest-ai.plugin.zsh

# Optional: Adjust AI suggestion parameters
# export ZSH_AUTOSUGGEST_AI_MIN_BUFFER_LEN=3    # Min chars before AI activates
# export ZSH_AUTOSUGGEST_AI_HISTORY_SIZE=20     # How many history items to include
# export ZSH_AUTOSUGGEST_AI_MAX_TOKENS=16       # Max tokens in suggestion
# export ZSH_AUTOSUGGEST_AI_TIMEOUT=0.5         # Timeout in seconds
```

### 5. Start the daemon

```bash
# Start the llama-server daemon
/path/to/ai-autocomplete/bin/suggestd start

# Check status
/path/to/ai-autocomplete/bin/suggestd status

# View logs
/path/to/ai-autocomplete/bin/suggestd logs
```

### 6. Reload your shell

```bash
source ~/.zshrc
```

## Usage

Just start typing in your shell! The AI suggestions will appear as ghost text after you pause typing.

- **→** (Right arrow) or **End** to accept the suggestion
- **Alt+F** to accept the next word
- Keep typing to ignore the suggestion

Example:
```bash
$ git ch█
# AI suggests: "eckout main"
$ git checkout main
```

## Configuration

### Environment Variables

#### For suggestd (daemon):
- `MODEL_PATH`: Path to the GGUF model file
- `SUGGESTD_HOST`: Bind address (default: 127.0.0.1)
- `SUGGESTD_PORT`: Port number (default: 11435)
- `SUGGESTD_CTX_SIZE`: Context window size (default: 256)
- `SUGGESTD_THREADS`: CPU threads to use (default: 6)
- `SUGGESTD_MAX_TOKENS`: Max tokens per completion (default: 24)

#### For aisuggest (client):
- `AISUGGEST_TIMEOUT`: Request timeout in seconds (default: 0.5)
- `DEBUG`: Set to "1" to enable debug logging

### Custom Prompts

Edit `config/prompt.txt` to customize the system prompt sent to the model.

## Performance Tuning

### Reduce Latency

```bash
# Decrease timeout (faster rejection of slow responses)
export ZSH_AUTOSUGGEST_AI_TIMEOUT=0.3

# Reduce max tokens (shorter completions = faster)
export ZSH_AUTOSUGGEST_AI_MAX_TOKENS=12
```

### Reduce Memory Usage

```bash
# Reduce context size
SUGGESTD_CTX_SIZE=128 bin/suggestd restart

# Use a smaller quantization (Q4_K_S instead of Q4_K_M)
# Or try Q3_K_M for even lower memory (~600MB)
```

### Check Memory Usage

```bash
# View daemon memory usage
bin/suggestd status

# Or manually:
ps -o rss= -p $(pgrep llama-server) | awk '{print $1/1024 "MB"}'
```

## Safety

The AI will NOT suggest:
- Destructive commands (`rm -rf`, `dd`, `mkfs`, etc.) unless you've already typed them
- `sudo` commands unless you've already typed `sudo`
- Piping to shell (`curl | sh`) unless already in your buffer
- Commands with suspicious patterns (see `config/safety_rules.md`)

These safety filters are applied in `bin/aisuggest` before any suggestion is shown.

## Troubleshooting

### Daemon won't start

```bash
# Check if llama-server is installed
which llama-server

# Check if model file exists
ls -lh models/*.gguf

# Check logs
cat .suggestd.log
```

### No suggestions appearing

```bash
# Verify daemon is running
bin/suggestd status

# Test the daemon directly
curl http://127.0.0.1:11435/health

# Enable debug mode
DEBUG=1 zsh
# Type something and check stderr for debug messages
```

### Suggestions are slow

```bash
# Check latency in debug mode
DEBUG=1 zsh
# Type something - you'll see timing info in stderr

# Reduce timeout or max tokens
export ZSH_AUTOSUGGEST_AI_TIMEOUT=0.3
export ZSH_AUTOSUGGEST_AI_MAX_TOKENS=12
```

### High memory usage

```bash
# Check current usage
bin/suggestd status

# Reduce context size
SUGGESTD_CTX_SIZE=128 bin/suggestd restart

# Try a smaller model quantization
```

## Running at Startup (Optional)

### Using launchd (macOS)

Create `~/Library/LaunchAgents/com.user.suggestd.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.suggestd</string>
    <key>ProgramArguments</key>
    <array>
        <string>/path/to/ai-autocomplete/bin/suggestd</string>
        <string>start</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/suggestd.out</string>
    <key>StandardErrorPath</key>
    <string>/tmp/suggestd.err</string>
</dict>
</plist>
```

Then:
```bash
launchctl load ~/Library/LaunchAgents/com.user.suggestd.plist
```

## Architecture

```
┌─────────────────────────────────────────────┐
│  zsh shell (user typing)                    │
└────────────────┬────────────────────────────┘
                 │
                 │ zsh-autosuggestions (async)
                 │
┌────────────────▼────────────────────────────┐
│  _zsh_autosuggest_strategy_ai               │
│  (zsh/zsh-autosuggest-ai.plugin.zsh)        │
└────────────────┬────────────────────────────┘
                 │
                 │ JSON (buffer, cwd, history)
                 │
┌────────────────▼────────────────────────────┐
│  aisuggest (bin/aisuggest)                  │
│  - Builds prompt                            │
│  - Calls llama-server                       │
│  - Applies safety filters                   │
└────────────────┬────────────────────────────┘
                 │
                 │ HTTP (POST /completion)
                 │
┌────────────────▼────────────────────────────┐
│  llama-server (daemon)                      │
│  - Llama 3.2 1B Instruct (Q4_K_M)           │
│  - Metal acceleration                       │
│  - <1GB RAM                                 │
└─────────────────────────────────────────────┘
```

## Contributing

Contributions welcome! Areas for improvement:
- Better prompt engineering
- Additional safety filters
- Performance optimizations
- Support for other shells (bash, fish)
- Alternative model recommendations

## License

MIT License - see LICENSE file for details

## Credits

- Built on [llama.cpp](https://github.com/ggerganov/llama.cpp)
- Integrates with [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions)
- Uses Meta's Llama 3.2 model
