# Safety Rules for AI Autosuggestions

## Principle: Do No Harm by Default

The AI should never proactively suggest potentially destructive commands unless the user has already explicitly typed the dangerous verb or pattern.

## Post-Processing Filters

### 1. Character Validation
**Always reject suggestions containing:**
- Newline characters (`\n`)
- Carriage returns (`\r`)
- ASCII control characters (0x00-0x1F except space)
- Null bytes

### 2. Dangerous Command Protection

**High-risk commands** (reject unless user buffer already contains the verb):
- `rm -rf`, `rm -fr`, `rm -r`, `rm -f` (especially with `/`, `~`, `*`)
- `dd` (raw disk operations)
- `mkfs` (filesystem creation/formatting)
- `:(){ :|:& };:` (fork bomb)
- `sudo rm`, `sudo dd`
- `shutdown`, `reboot`, `halt`, `poweroff`
- `curl ... | sh`, `wget ... | bash` (pipe to shell)
- `chmod 777`, `chmod -R 777`
- `chown -R`, `chmod -R` on system directories
- `> /dev/sd*` (writing to raw devices)

**Moderate-risk commands** (reject unless buffer contains partial match):
- `git push --force`, `git push -f`
- `git reset --hard`
- `git clean -fdx`
- `kubectl delete` (especially namespaces, deployments)
- `terraform destroy`
- `docker rm -f $(docker ps -aq)`
- `npm publish`, `cargo publish`
- `killall`, `pkill` (without specific process name)

### 3. Implementation Logic

```
if suggestion contains dangerous_verb:
    if buffer does NOT contain dangerous_verb:
        REJECT suggestion
    else:
        ALLOW (user already knows what they're typing)
```

### 4. Safe Commands (Allowlist - always OK to suggest)
- `ls`, `ll`, `la`
- `cd`, `pwd`
- `cat`, `less`, `more`, `head`, `tail`
- `grep`, `rg`, `ag`, `ack`
- `git status`, `git log`, `git diff`, `git show`
- `echo`
- `which`, `type`
- `man`, `help`
- `history`
- `find` (read-only operations)

### 5. Context-Based Safety

**Prefix matching:**
- If buffer = `git ch`, suggesting `eckout main` is safe
- If buffer = `ls`, suggesting `-la *.py` is safe
- If buffer is empty, never suggest `rm`, `dd`, etc.

**Whitespace handling:**
- Strip leading whitespace from suggestion unless buffer ends with whitespace
- Preserve intent: if user typed `ls `, suggestion should start with filename/option

### 6. Validation After Model Output

```python
def is_safe_suggestion(buffer: str, suggestion: str) -> bool:
    full_command = buffer + suggestion

    # Check for control characters
    if any(ord(c) < 32 and c not in [' ', '\t'] for c in suggestion):
        return False

    # Check for newlines
    if '\n' in suggestion or '\r' in suggestion:
        return False

    # Check dangerous patterns
    for pattern in DANGEROUS_PATTERNS:
        if pattern_in_suggestion(full_command, pattern):
            if not pattern_in_buffer(buffer, pattern):
                return False

    return True
```

## Edge Cases

1. **User explicitly types dangerous command**: ALLOW suggestion to complete it
2. **Suggestion would create dangerous command**: REJECT even if each part seems safe
3. **Ambiguous completion**: Prefer safer alternative or output nothing
4. **Shell operators**: Be cautious with `|`, `>`, `>>`, `;`, `&&`, `||` in suggestions

## Monitoring and Logging

- Log rejected suggestions (when DEBUG=1) with reason
- Track false positives (safe commands rejected)
- Allow opt-in to "expert mode" via environment variable if needed

## Future Enhancements

- Machine learning based risk scoring
- Per-directory safety profiles
- User feedback loop for false positives/negatives
- Integration with sudo/doas detection
