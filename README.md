# Snowflake ActivitySchema Integration for Claude Code

This integration automatically logs Claude Code activities to Snowflake following the ActivitySchema v2.0 specification.

## 🚀 NEW: Automatic Logging is Now Available!

After setting up, just run `claude-logging-setup enable` in any directory to automatically log all Claude Code sessions.

## Installation Status ✅

- Snowflake CLI installed (v3.10.0)
- Database schema created (CLAUDE_LOGS.ACTIVITIES)
- Logging scripts configured
- Wrapper commands available

## Quick Start

### Automatic Logging Setup (Recommended)

1. **Source your shell configuration** (one time only):
   ```bash
   source ~/.zshrc
   ```

2. **Enable logging in any directory**:
   ```bash
   cd /your/project/directory
   claude-logging-setup enable    # Uses JSON logging by default
   # or
   claude-logging-setup enable simple  # For basic logging only
   ```

3. **Use Claude normally** - all sessions are automatically logged:
   ```bash
   claude -p "Help me refactor this code"
   # This is automatically logged to Snowflake!
   ```

4. **Check your activity**:
   ```bash
   snow-claude-recent    # View recent activities
   snow-claude-stats     # See tool usage statistics
   ```

### Manual Logging
```bash
cd ~/snowflake-activity-schema/activity_schema

# Log a session
./log_claude_activity.sh session_start
./log_claude_activity.sh tool_call "bash" '{"command":"ls"}' "success" 100 500
./log_claude_activity.sh session_end 1 500 5000
```

### Manual Control Options

- **Bypass logging temporarily**: Use `claude-plain` command
- **Always log (override directory setting)**: Use `ccode` command  
- **Check current status**: Run `claude-logging-setup status`
- **Disable logging**: Run `claude-logging-setup disable`

### Global Logging Control

Set environment variable to enable logging everywhere:
```bash
export CLAUDE_ALWAYS_LOG=json    # or 'simple'
```

## Configuration

### Snowflake Connection
- Config file: `~/.snowflake/config.toml`
- Connection name: `poc`
- Account: `yshmxno-fbc56289`
- Database: `CLAUDE_LOGS`
- Schema: `ACTIVITIES`

### Environment Variables
```bash
export PATH="$PATH:$HOME/bin"  # Add to ~/.bashrc or ~/.zshrc
export CLAUDE_SESSION_ID="custom-session-id"  # Optional
```

## Querying Your Data

### Recent Activities
```sql
-- View last 24 hours of activities
SELECT * FROM CLAUDE_LOGS.ACTIVITIES.V_RECENT_ACTIVITIES 
ORDER BY ts DESC LIMIT 20;

-- Tool usage summary
SELECT 
    tool_name,
    COUNT(*) as usage_count,
    AVG(duration_ms) as avg_duration,
    SUM(tokens_used) as total_tokens
FROM CLAUDE_LOGS.ACTIVITIES.V_CLAUDE_ACTIVITIES
WHERE tool_name IS NOT NULL
GROUP BY tool_name
ORDER BY usage_count DESC;

-- Session summaries
SELECT * FROM CLAUDE_LOGS.ACTIVITIES.V_CLAUDE_SESSIONS
ORDER BY session_start DESC;
```

### Activity Patterns
```sql
-- Hourly activity patterns
SELECT 
    DATE_TRUNC('hour', ts) as hour,
    COUNT(*) as activities,
    COUNT(DISTINCT customer) as unique_sessions
FROM CLAUDE_LOGS.ACTIVITIES.ACTIVITY_STREAM
GROUP BY hour
ORDER BY hour DESC;

-- Error analysis
SELECT 
    feature_json:error_message::STRING as error,
    COUNT(*) as occurrences
FROM CLAUDE_LOGS.ACTIVITIES.ACTIVITY_STREAM
WHERE activity = 'claude_error'
GROUP BY error;
```

## How Automatic Logging Works

1. **Directory Detection**: The `claude()` shell function checks for `.claude-log` file
2. **Smart Routing**: 
   - If `.claude-log` exists → Routes to logging wrapper
   - If `CLAUDE_ALWAYS_LOG` is set → Uses that preference
   - Otherwise → Normal Claude execution
3. **Seamless Experience**: You use `claude` normally, logging happens transparently

### Managing Logging Preferences

```bash
# Per-project configuration
echo "json" > .claude-log     # Always use JSON logging
echo "simple" > .claude-log    # Use simple logging

# Add to .gitignore for personal preferences
echo ".claude-log" >> .gitignore
```

## Architecture

### Components
1. **log_claude_activity.sh** - Core logging script
2. **clogged** - Simple wrapper for basic session logging
3. **clogged-json** - Advanced wrapper with JSON stream parsing
4. **parse_claude_stream.py** - Python parser for real-time activity extraction

### Data Flow
```
Claude Code → JSON Stream → Parser → Snowflake
     ↓                         ↓
  Terminal               Activity Logs
```

## Troubleshooting

### Connection Issues
```bash
# Test connection
snow sql -c poc -q "SELECT 1;"

# Check config
cat ~/.snowflake/config.toml
```

### Logging Issues
```bash
# Test logging directly
cd ~/snowflake-activity-schema/activity_schema
./log_claude_activity.sh session_start

# Check for errors
tail -f ~/.claude/sessions/*.log
```

### No Activities Showing
1. Ensure PATH includes snow CLI location
2. Check CLAUDE_SESSION_ID is set
3. Verify Snowflake connection works
4. Look for error messages in stderr

## Advanced Usage

### Custom Activity Logging
```bash
# Log custom activities
./log_claude_activity.sh tool_call "custom_tool" \
  '{"action":"analyze","target":"codebase"}' \
  "success" 250 1000
```

### Batch Processing
```bash
# Process existing Claude logs
find ~/.claude/shell-snapshots -name "*.json" -mtime -7 | \
  while read f; do
    python3 ~/snowflake-activity-schema/batch_process.py "$f"
  done
```

### Integration with Scripts
```bash
#!/bin/bash
# my_claude_script.sh

# Start logging
source ~/snowflake-activity-schema/activity_schema/log_claude_activity.sh
log_session_start

# Your Claude commands
claude -p "Your prompt"

# End logging
log_session_end
```

## Next Steps

1. **Add to PATH**: Add `~/bin` to your PATH for easy access to wrappers
2. **Create Dashboards**: Use Snowflake's visualization tools
3. **Set Up Alerts**: Monitor for errors or unusual patterns
4. **Optimize Performance**: Batch load for high-volume usage
5. **Extend Schema**: Add custom activities for your workflow

## Support

- Snowflake Docs: https://docs.snowflake.com
- Claude Code Docs: https://docs.anthropic.com/en/docs/claude-code
- ActivitySchema Spec: (Your internal documentation)

---
Generated: 2025-08-09