#!/bin/bash
# Fix .zshrc by removing duplicate entries and fixing claude setup

echo "Fixing .zshrc configuration..."

# Backup current .zshrc
cp ~/.zshrc ~/.zshrc.backup.$(date +%s)

# Create a clean version
cat > ~/.zshrc.fixed << 'EOF'
. "/Users/chandler/.deno/env"
# Created by `pipx` on 2025-07-13 00:36:21
export PATH="$PATH:/Users/chandler/.local/bin"

# Add Snowflake CLI and user bin to PATH
export PATH="$HOME/bin:/Library/Frameworks/Python.framework/Versions/3.12/bin:$PATH"

# Snowflake Claude query shortcuts
alias snow-claude-recent='snow sql -c poc -q "SELECT ts, activity, tool_name, parameters FROM CLAUDE_LOGS.ACTIVITIES.V_RECENT_ACTIVITIES LIMIT 20;"'
alias snow-claude-stats='snow sql -c poc -q "SELECT tool_name, COUNT(*) as uses, AVG(duration_ms) as avg_ms FROM CLAUDE_LOGS.ACTIVITIES.V_CLAUDE_ACTIVITIES WHERE tool_name IS NOT NULL GROUP BY 1 ORDER BY 2 DESC;"'
alias snow-claude-sessions='snow sql -c poc -q "SELECT session_id, session_start, total_activities, total_tokens FROM CLAUDE_LOGS.ACTIVITIES.V_CLAUDE_SESSIONS ORDER BY session_start DESC LIMIT 10;"'

# ActivitySchema v2 - Claude wrapper
# Use claude-v2 for automatic activity logging
alias claude='claude-v2'
alias claude-plain='command claude'    # Use this for no logging
alias ccode='~/bin/clogged-json'      # Legacy JSON logging

EOF

# Replace the original
mv ~/.zshrc.fixed ~/.zshrc

echo "✅ Fixed .zshrc"
echo ""
echo "Now run:"
echo "  source ~/.zshrc"
echo ""
echo "Then test with:"
echo "  claude 'What is 2+2'"