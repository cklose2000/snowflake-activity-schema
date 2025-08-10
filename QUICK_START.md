# Claude Code + Snowflake Learning System - Quick Reference

## 🚀 Enable Automatic Logging (One Time Setup)

```bash
# 1. Source your shell config (if you haven't already)
source ~/.zshrc

# 2. Navigate to your project
cd /your/project

# 3. Enable logging
claude-logging-setup enable

# 4. That's it! All claude commands are now logged
```

## 📊 View Your Activity

```bash
# Recent activities
snow-claude-recent

# Tool usage statistics  
snow-claude-stats

# Session summaries
snow-claude-sessions
```

## 🎛️ Control Commands

| Command | Description |
|---------|-------------|
| `claude` | Smart command - logs if `.claude-log` exists |
| `ccode` | Always log (force logging) |
| `claude-plain` | Never log (bypass logging) |
| `claude-logging-setup status` | Check current status |
| `claude-logging-setup disable` | Turn off logging |

## 🤖 Natural Language SQL with Claude

```bash
# Load the functions
source ~/snowflake-activity-schema/shell-functions.sh

# Ask Claude to write and execute SQL
cq "show me my orphaned sessions"
cq "what are the top 10 most active sessions?"
cq "analyze Claude usage patterns by hour"

# Quick commands
cstats    # Executive dashboard
corphans  # Orphaned sessions
cmeta     # Meta-learning sessions
cjourney  # Your personal journey
```

## 🔧 Advanced Options

```bash
# Use simple logging (less detailed)
claude-logging-setup enable simple

# Enable globally (all directories)
export CLAUDE_ALWAYS_LOG=json

# Add to .gitignore for personal settings
echo ".claude-log" >> .gitignore
```

---
**Snowflake Dashboard**: `SELECT * FROM CLAUDE_LOGS.ACTIVITIES.V_RECENT_ACTIVITIES;`