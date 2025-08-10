# Claude Code Logging Fix - December 2024

## Problem
Claude Code prompts were not being logged to Snowflake despite:
- `.claude-log` file being configured
- Wrapper scripts being in place
- Database tables being ready

## Root Cause
The logging script `activity_schema/log_claude_activity.sh` was using `snow` command without full path. When called from the wrapper script, `snow` was not in PATH, causing silent failures.

## Solution Applied

### 1. Fixed Path Issue
Updated `log_claude_activity.sh` line 54-55:
```bash
# Before (failing):
if snow sql -c poc -q "$sql_query" 2>/dev/null; then

# After (working):
SNOW_CMD="${SNOW_CMD:-/Library/Frameworks/Python.framework/Versions/3.12/bin/snow}"
if $SNOW_CMD sql -c poc -q "$sql_query" 2>/dev/null; then
```

### 2. Fixed Infinite Loop
Updated `bin/clogged-json` line 42:
```bash
# Before (infinite loop):
claude "$@" 2>&1 | tee "$TEMP_OUTPUT"

# After (working):
command claude "$@" 2>&1 | tee "$TEMP_OUTPUT"
```

## Verification

Test logging manually:
```bash
# Test session logging
SESSION_ID="test-$(date +%s)"
export CLAUDE_SESSION_ID=$SESSION_ID
/Users/chandler/snowflake-activity-schema/activity_schema/log_claude_activity.sh session_start "$(pwd)"

# Check in Snowflake
snow sql -c poc -q "SELECT * FROM CLAUDE_LOGS.ACTIVITIES.ACTIVITY_STREAM WHERE ts >= CURRENT_TIMESTAMP() - INTERVAL '5 minutes';"
```

Test with Claude:
```bash
# Should log automatically
claude -p "say hello"

# Check logs
dashboard
```

## Current Status
✅ **FIXED** - Logging is now working. All Claude Code sessions in directories with `.claude-log` file will be logged to Snowflake.

## Files Modified
1. `/Users/chandler/snowflake-activity-schema/activity_schema/log_claude_activity.sh` - Added full path to snow command
2. `/Users/chandler/bin/clogged-json` - Fixed infinite loop with `command` prefix

## Lessons Learned
1. Always use full paths in scripts that may be called from different environments
2. Use `command` prefix to bypass shell aliases when calling commands from wrapper scripts
3. Don't silence errors (>/dev/null 2>&1) during development - they hide important debugging information