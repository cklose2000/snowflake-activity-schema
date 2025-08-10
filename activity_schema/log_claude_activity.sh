#!/bin/bash
# log_claude_activity.sh - ActivitySchema v2.0 compliant logger for Claude Code

# Configuration
SNOW_CONNECTION="${SNOW_CONNECTION:-default}"
CLAUDE_SESSION_ID="${CLAUDE_SESSION_ID:-$(uuidgen 2>/dev/null || echo "session-$(date +%s)")}"
export CLAUDE_SESSION_ID

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper function to generate UUID (fallback for systems without uuidgen)
generate_uuid() {
    if command -v uuidgen &> /dev/null; then
        uuidgen
    else
        echo "$(date +%s)-$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 8)"
    fi
}

# Core logging function following ActivitySchema v2.0
log_activity() {
    local activity_id=$(generate_uuid)
    local activity="$1"
    local feature_json="$2"
    local revenue_impact="${3:-0}"
    local link="${4:-NULL}"
    
    local customer="${CLAUDE_SESSION_ID}"
    local anonymous_customer_id="${HOSTNAME:-$(hostname 2>/dev/null || echo 'unknown')}"
    
    # Escape single quotes in JSON
    feature_json="${feature_json//\'/\'\'}"
    
    # Prepare the SQL statement
    local sql_query="
    INSERT INTO CLAUDE_LOGS.ACTIVITIES.ACTIVITY_STREAM 
    SELECT 
        '$activity_id' as activity_id,
        CURRENT_TIMESTAMP() as ts,
        '$activity' as activity,
        '$customer' as customer,
        '$anonymous_customer_id' as anonymous_customer_id,
        PARSE_JSON('$feature_json') as feature_json,
        $revenue_impact as revenue_impact,
        $([ "$link" = "NULL" ] && echo "NULL" || echo "'$link'") as link,
        NULL as activity_occurrence,
        NULL as activity_repeated_at;"
    
    # Execute the query (use full path to snow command)
    SNOW_CMD="${SNOW_CMD:-/Library/Frameworks/Python.framework/Versions/3.12/bin/snow}"
    if $SNOW_CMD sql -c poc -q "$sql_query" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Logged activity: $activity"
        return 0
    else
        echo -e "${RED}✗${NC} Failed to log activity: $activity" >&2
        return 1
    fi
}

# Activity logging functions
log_session_start() {
    local project_path="${1:-$(pwd)}"
    local git_branch="$(git branch --show-current 2>/dev/null || echo 'none')"
    local user="${USER:-unknown}"
    local host="${HOSTNAME:-$(hostname 2>/dev/null || echo 'unknown')}"
    
    local feature_json=$(cat <<JSON
{
    "session_id": "$CLAUDE_SESSION_ID",
    "project_path": "$project_path",
    "git_branch": "$git_branch",
    "user": "$user",
    "host": "$host",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)",
    "cli_version": "$($SNOW_CMD --version 2>/dev/null | grep -o '[0-9.]*' || echo 'unknown')"
}
JSON
)
    log_activity "claude_session_start" "$feature_json"
    echo "Session ID: $CLAUDE_SESSION_ID"
}

log_tool_call() {
    local tool_name="$1"
    local parameters="$2"
    local result_type="${3:-success}"
    local duration_ms="${4:-0}"
    local tokens_used="${5:-0}"
    
    local feature_json=$(cat <<JSON
{
    "tool_name": "$tool_name",
    "parameters": $parameters,
    "result_type": "$result_type",
    "duration_ms": $duration_ms,
    "tokens_used": $tokens_used,
    "project_path": "$(pwd)",
    "git_branch": "$(git branch --show-current 2>/dev/null || echo 'none')",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)"
}
JSON
)
    
    local cost=$(echo "scale=6; $tokens_used * 0.00004 / 1000" | bc 2>/dev/null || echo "0")
    log_activity "claude_tool_call" "$feature_json" "$cost"
}

log_file_operation() {
    local operation="$1"
    local file_path="$2"
    local lines_affected="${3:-0}"
    local success="${4:-true}"
    
    local feature_json=$(cat <<JSON
{
    "operation": "$operation",
    "file_path": "$file_path",
    "lines_affected": $lines_affected,
    "success": $success,
    "file_size": $([ -f "$file_path" ] && stat -f%z "$file_path" 2>/dev/null || echo "0"),
    "project_path": "$(pwd)",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)"
}
JSON
)
    
    log_activity "claude_file_operation" "$feature_json" "0" "file://$file_path"
}

log_session_end() {
    local total_activities="${1:-0}"
    local total_tokens="${2:-0}"
    local session_duration_ms="${3:-0}"
    
    local feature_json=$(cat <<JSON
{
    "session_id": "$CLAUDE_SESSION_ID",
    "total_activities": $total_activities,
    "total_tokens": $total_tokens,
    "session_duration_ms": $session_duration_ms,
    "session_outcome": "success",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)"
}
JSON
)
    
    local cost=$(echo "scale=6; $total_tokens * 0.00004 / 1000" | bc 2>/dev/null || echo "0")
    log_activity "claude_session_end" "$feature_json" "$cost"
}

# Main execution
case "${1:-}" in
    session_start) log_session_start "${2:-}" ;;
    session_end) log_session_end "${2:-0}" "${3:-0}" "${4:-0}" ;;
    tool_call) log_tool_call "$2" "$3" "${4:-success}" "${5:-0}" "${6:-0}" ;;
    file_op) log_file_operation "$2" "$3" "${4:-0}" "${5:-true}" ;;
    *) echo "Usage: $0 {session_start|session_end|tool_call|file_op} [args...]" ;;
esac