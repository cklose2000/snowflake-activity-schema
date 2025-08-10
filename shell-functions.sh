#!/bin/bash
# Shell functions for Claude + Snowflake integration
# Add this to your ~/.zshrc or ~/.bashrc: source ~/snowflake-activity-schema/shell-functions.sh

# cq - Claude Query: Natural language to SQL
cq() {
    ~/snowflake-activity-schema/bin/cq "$@"
}

# why - COO-friendly alias for asking why metrics look strange
why() {
    # Simple interface for executives
    ~/snowflake-activity-schema/bin/cq-simple "explain why $@"
}

# what - COO-friendly alias for asking what's happening
what() {
    ~/snowflake-activity-schema/bin/cq-simple "what $@"
}

# how - COO-friendly alias for asking how many/much
how() {
    ~/snowflake-activity-schema/bin/cq-simple "how $@"
}

# dashboard - Show COO metrics instantly
dashboard() {
    echo "📊 Claude Usage Dashboard"
    echo "========================="
    /Library/Frameworks/Python.framework/Versions/3.12/bin/snow sql -c poc -q "
    SELECT * FROM CLAUDE_LOGS.ACTIVITIES.V_COO_METRICS;
    " --format table 2>/dev/null
    
    echo ""
    echo "📈 Health Check:"
    /Library/Frameworks/Python.framework/Versions/3.12/bin/snow sql -c poc -q "
    SELECT * FROM CLAUDE_LOGS.ACTIVITIES.V_COO_HEALTH_CHECK;
    " --format table 2>/dev/null
    
    echo ""
    echo "To ask questions, use: why 'sessions are low'"
}

# cql - Claude Query Learn: With learning context
cql() {
    local prompt="$*"
    # Add learning context to the prompt
    enhanced_prompt="Using the ActivitySchema learning views (V_LEARNING_ORPHANED_SESSIONS, V_META_LEARNING, V_SYSTEM_EVOLUTION), $prompt"
    ~/snowflake-activity-schema/bin/cq "$enhanced_prompt"
}

# cmq - Claude Meta Query: Query your queries!
cmq() {
    # Specifically query the meta-queries themselves
    ~/snowflake-activity-schema/bin/cq "Show me queries where activity='claude_meta_query' from ACTIVITY_STREAM"
}

# clearn - Start interactive learning
clearn() {
    echo "🎓 Starting ActivitySchema Learning Journey..."
    echo ""
    echo "1. Check your progress:"
    echo "   $ cq 'show me my learning progress'"
    echo ""
    echo "2. Find orphaned sessions:"
    echo "   $ cq 'how many of my sessions are orphaned?'"
    echo ""
    echo "3. Discover patterns:"
    echo "   $ cq 'when do I use Claude most?'"
    echo ""
    echo "4. Go meta:"
    echo "   $ cq 'show me sessions where I analyzed Claude usage'"
    echo ""
    read -p "Press Enter to run your first query..." 
    ~/snowflake-activity-schema/bin/my-claude-journey
}

# csession - Quick session check
csession() {
    echo "📊 Your Current Session Status:"
    /Library/Frameworks/Python.framework/Versions/3.12/bin/snow sql -c poc -q "
    SELECT 
        'Active Sessions' as metric,
        COUNT(*) as value
    FROM CLAUDE_LOGS.ACTIVITIES.ACTIVITY_STREAM
    WHERE activity = 'claude_session_start'
        AND customer NOT IN (
            SELECT customer 
            FROM CLAUDE_LOGS.ACTIVITIES.ACTIVITY_STREAM 
            WHERE activity = 'claude_session_end'
        )
        AND ts > DATEADD('hour', -1, CURRENT_TIMESTAMP())
    UNION ALL
    SELECT 
        'Orphaned Today' as metric,
        COUNT(*) as value
    FROM (
        SELECT customer
        FROM CLAUDE_LOGS.ACTIVITIES.ACTIVITY_STREAM
        WHERE activity = 'claude_session_start'
            AND DATE(ts) = CURRENT_DATE()
        MINUS
        SELECT customer
        FROM CLAUDE_LOGS.ACTIVITIES.ACTIVITY_STREAM
        WHERE activity = 'claude_session_end'
            AND DATE(ts) = CURRENT_DATE()
    );" --format table 2>/dev/null
}

# cstats - Quick stats dashboard
cstats() {
    echo "📈 Claude Usage Stats:"
    /Library/Frameworks/Python.framework/Versions/3.12/bin/snow sql -c poc -q "
    SELECT * FROM CLAUDE_LOGS.ACTIVITIES.V_EXECUTIVE_SUMMARY;" --format table 2>/dev/null | head -20
}

# corphans - Check orphaned sessions
corphans() {
    echo "👻 Orphaned Sessions Analysis:"
    /Library/Frameworks/Python.framework/Versions/3.12/bin/snow sql -c poc -q "
    SELECT * FROM CLAUDE_LOGS.ACTIVITIES.V_LEARNING_ORPHANED_SESSIONS;" --format table 2>/dev/null
}

# cmeta - See meta-learning sessions
cmeta() {
    echo "🔄 Meta-Learning Sessions (studying the system itself):"
    /Library/Frameworks/Python.framework/Versions/3.12/bin/snow sql -c poc -q "
    SELECT * FROM CLAUDE_LOGS.ACTIVITIES.V_META_LEARNING LIMIT 10;" --format table 2>/dev/null
}

# cevolve - See system evolution
cevolve() {
    echo "📊 System Evolution Over Time:"
    /Library/Frameworks/Python.framework/Versions/3.12/bin/snow sql -c poc -q "
    SELECT * FROM CLAUDE_LOGS.ACTIVITIES.V_SYSTEM_EVOLUTION;" --format table 2>/dev/null
}

# cteach - Start the teaching system
cteach() {
    ~/snowflake-activity-schema/bin/teach-me-activityschema
}

# cjourney - Your personal journey
cjourney() {
    ~/snowflake-activity-schema/bin/my-claude-journey
}

# Print available commands
claude_help() {
    cat << EOF
🎓 Claude + Snowflake Learning Commands:

Query Commands:
  cq "question"     - Ask Claude to write and run SQL
  cql "question"    - Query with learning context
  cmq              - Query your queries (meta!)

Quick Views:
  csession         - Check active/orphaned sessions
  cstats           - Executive dashboard
  corphans         - Orphaned sessions analysis
  cmeta            - Meta-learning sessions
  cevolve          - System evolution

Learning:
  clearn           - Start interactive learning
  cteach           - Run the tutorial
  cjourney         - Your personal dashboard

Examples:
  cq "show me my Claude usage today"
  cq "which sessions are orphaned?"
  cql "analyze the orphan problem"
  cmq  # See all your meta-queries

The Meta Loop:
  You ask → Claude writes SQL → Executes → Logs → Query the logs!

EOF
}

# Alias for help
alias chelp='claude_help'

# Auto-complete for cq (zsh)
if [[ -n "$ZSH_VERSION" ]]; then
    _cq_complete() {
        local queries=(
            "show me my orphaned sessions"
            "what are today's activities?"
            "how many sessions this week?"
            "which projects use Claude most?"
            "analyze usage patterns by hour"
            "show me the meta-learning sessions"
            "calculate total tokens used"
            "find longest Claude session"
        )
        _describe 'query' queries
    }
    compdef _cq_complete cq
fi

echo "✅ Claude + Snowflake functions loaded! Type 'chelp' for commands."