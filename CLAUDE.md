# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Snowflake ActivitySchema v2.0 integration for Claude Code that automatically logs Claude activities to Snowflake for analytics and monitoring. The system follows the ActivitySchema specification to track user sessions, tool usage, file operations, and errors.

## Automatic Context Hydration

**IMPORTANT**: This repository uses automatic Snowflake context hydration for optimal performance. On first Claude Code execution in this directory, the system automatically:

1. **Auto-Discovery**: Queries INFORMATION_SCHEMA to discover all available database objects
2. **Role-Based Context**: Loads different contexts based on your role (BA or DE)
3. **Dynamic Documentation**: Generates CLAUDE_DYNAMIC.md with current schema state
4. **Session Registration**: Logs the hydration event to Snowflake for tracking

### How to Use Context Hydration

```bash
# For Business Analyst role (default)
./bin/snowflake-context-init BA

# For Data Engineer role
./bin/snowflake-context-init DE

# The script creates .claude_context/ with:
# - schema.json: All database objects
# - active_context.json: Role-specific context
# - CLAUDE_DYNAMIC.md: Auto-generated documentation
```

## Executive Dashboard Queries (For COO/Leadership)

When asked about Claude Code usage, use these pre-built views for instant responses:

### Executive Summary
```sql
-- High-level KPIs (30-day rolling window)
SELECT * FROM CLAUDE_LOGS.ACTIVITIES.V_EXECUTIVE_SUMMARY;
```

### User Adoption Trends
```sql
-- Daily active users and growth metrics
SELECT * FROM CLAUDE_LOGS.ACTIVITIES.V_USER_ADOPTION 
WHERE activity_date >= CURRENT_DATE - 7
ORDER BY activity_date DESC;
```

### Tool Usage Analytics
```sql
-- Detailed tool performance and usage patterns
SELECT * FROM CLAUDE_LOGS.ACTIVITIES.V_TOOL_USAGE_ANALYTICS 
ORDER BY usage_count DESC 
LIMIT 10;
```

### Error Analysis
```sql
-- Error tracking and patterns
SELECT * FROM CLAUDE_LOGS.ACTIVITIES.V_ERROR_ANALYSIS
WHERE error_date >= CURRENT_DATE - 7
ORDER BY error_count DESC;
```

### Project Activity
```sql
-- Activity breakdown by project/repository
SELECT * FROM CLAUDE_LOGS.ACTIVITIES.V_PROJECT_ACTIVITY
ORDER BY sessions DESC;
```

## Architecture

### Core Components

1. **`bin/snowflake-context-init`** - Context hydration script
   - Discovers all database objects
   - Creates role-specific contexts
   - Generates dynamic documentation
   - Registers session with Snowflake

2. **`activity_schema/log_claude_activity.sh`** - Main logging script
   - Generates unique activity IDs  
   - Formats JSON feature data
   - Executes SQL inserts via Snowflake CLI
   - Supports session_start, session_end, tool_call, and file_op activities

3. **`activity_schema/parse_claude_stream.py`** - Python parser for JSON stream
   - Reads Claude's JSON output stream
   - Extracts tool usage events
   - Calls logging script in real-time
   - Tracks session metrics

4. **`sql/create_executive_objects.sql`** - Database schema setup
   - Creates executive views (V_EXECUTIVE_SUMMARY, V_USER_ADOPTION, etc.)
   - Defines INITIALIZE_SESSION stored procedure
   - Sets up role-based contexts

### Database Schema

- **Database**: CLAUDE_LOGS
- **Schema**: ACTIVITIES  
- **Main Table**: ACTIVITY_STREAM
- **Connection**: Uses Snowflake CLI with connection name "poc"

### Executive Views (Pre-built for Performance)

| View Name | Purpose | Key Metrics |
|-----------|---------|-------------|
| V_EXECUTIVE_SUMMARY | 30-day executive dashboard | Users, sessions, costs, tool usage |
| V_USER_ADOPTION | User growth and engagement | DAU, growth %, activities per session |
| V_TOOL_USAGE_ANALYTICS | Tool performance metrics | Usage counts, duration, success rates |
| V_ERROR_ANALYSIS | Error tracking | Error types, affected users, recovery |
| V_PROJECT_ACTIVITY | Project-level insights | Files touched, lines modified, costs |

### Key Activity Types

- `claude_session_start` - Tracks session initialization
- `claude_tool_call` - Records tool/command execution
- `claude_file_operation` - Logs file read/write/edit operations  
- `claude_session_end` - Captures session completion metrics
- `claude_error` - Records errors and recovery actions
- `claude_context_hydration` - Tracks context initialization

## CQ (Claude Query) - Natural Language SQL System

### How CQ Works
**CQ** stands for "Claude Query" - it's a command that lets executives and users ask questions in plain English, and Claude automatically writes and executes the SQL.

```bash
# Examples
cq "show me my orphaned sessions"
cq "what are today's activities?" 
cq "calculate our Claude costs this week"

# Executive-optimized version
cq-executive metrics      # Pre-loaded executive dashboard
cq-executive costs       # Cost breakdown
cq-executive trends      # Usage trends
```

### Why CQ is Smart From Day One

1. **Comprehensive Context File** (`contexts/cq_context.md`):
   - Complete schema documentation for all tables and views
   - Column descriptions and data types
   - Common query patterns and mappings
   - Executive question → SQL translations

2. **Learning Knowledge Base** (`CQ_KNOWLEDGE_BASE` table):
   - Tracks every successful query for reuse
   - Learns from failures to improve
   - Builds pattern library over time
   - Gets smarter with each use

3. **Executive Optimization**:
   - Pre-loaded business context
   - Smart shortcuts (metrics, costs, trends)
   - Formatted for C-suite consumption
   - No SQL knowledge required

### Available Views for CQ

| View | Purpose | Sample Query |
|------|---------|--------------|
| `V_EXECUTIVE_SUMMARY` | High-level KPIs | `cq "show executive metrics"` |
| `V_LEARNING_ORPHANED_SESSIONS` | Incomplete sessions (80% rate) | `cq "find orphaned sessions"` |
| `V_META_LEARNING` | Recursive usage analysis | `cq "show meta-learning"` |
| `V_SYSTEM_EVOLUTION` | System improvement tracking | `cq "how is the system evolving?"` |
| `V_CQ_SUCCESSFUL_PATTERNS` | What queries work best | `cq "show successful query patterns"` |
| `V_CQ_INTELLIGENCE_METRICS` | How smart CQ is getting | `cq "how intelligent is cq becoming?"` |

## SQL Query Rules
- Always redirect stderr to /dev/null for snow commands: `2>/dev/null`
- Save all query results to sql_results/ folder
- When opening SQL results, always use: `code -r [filename]`
  - This ensures files open as tabs in my current VS Code window, not new windows
- Show only row count confirmation in terminal

## Development Commands

### Initial Setup

```bash
# Install Snowflake CLI (if not installed)
brew install snowflake-cli
# or
pip3 install snowflake-cli

# Test Snowflake connection
snow sql -c poc -q "SELECT 1;"

# Initialize database schema and views
snow sql -c poc -f sql/create_executive_objects.sql
snow sql -c poc -f sql/create_learning_views.sql
snow sql -c poc -f sql/create_cq_learning.sql

# Run context hydration
./bin/snowflake-context-init BA

# Load shell functions for easy access
source shell-functions.sh
```

### Manual Activity Logging

```bash
# Log a session start
./activity_schema/log_claude_activity.sh session_start

# Log a tool call
./activity_schema/log_claude_activity.sh tool_call "bash" '{"command":"ls"}' "success" 100 500

# Log file operation
./activity_schema/log_claude_activity.sh file_op "edit" "/path/to/file.py" 25 true

# Log session end
./activity_schema/log_claude_activity.sh session_end 10 1500 30000
```

### Query Activities

```bash
# Using snow CLI directly
snow sql -c poc -q "SELECT * FROM CLAUDE_LOGS.ACTIVITIES.V_RECENT_ACTIVITIES ORDER BY ts DESC LIMIT 10;"

# Check tool usage stats
snow sql -c poc -q "SELECT * FROM CLAUDE_LOGS.ACTIVITIES.V_TOOL_USAGE_ANALYTICS;"

# Get executive summary
snow sql -c poc -q "SELECT * FROM CLAUDE_LOGS.ACTIVITIES.V_EXECUTIVE_SUMMARY;"
```

### Testing

```bash
# Test logging script
export CLAUDE_SESSION_ID="test-$(date +%s)"
./activity_schema/log_claude_activity.sh session_start
./activity_schema/log_claude_activity.sh session_end 1 100 5000

# Test context hydration
./bin/snowflake-context-init BA
cat .claude_context/active_context.json

# Test with different role
./bin/snowflake-context-init DE
cat .claude_context/active_context.json
```

## Environment Variables

- `CLAUDE_SESSION_ID` - Session identifier (auto-generated if not set)
- `SNOW_CONNECTION` - Snowflake connection name (defaults to "poc")
- `CLAUDE_ROLE` - User role for context (BA or DE, defaults to BA)
- `CLAUDE_SNOWFLAKE_INITIALIZED` - Set to true after context hydration
- `CLAUDE_CONTEXT_PATH` - Path to context files (defaults to .claude_context)

## Responding to Executive Queries

When a COO or executive asks about Claude Code usage:

1. **Check if context is hydrated**: Look for `.claude_context/active_context.json`
2. **Use pre-built views**: Query V_EXECUTIVE_SUMMARY first for overview
3. **Provide business insights**: Focus on trends, adoption, and ROI
4. **Format for executives**: Use clear metrics, percentages, and comparisons

Example response pattern:
```
"Based on the executive dashboard, here are your Claude Code metrics:
- Active Users: X (up Y% from last week)  
- Total Sessions: X
- Most Used Tools: [list]
- Total Cost: $X.XX
- Average Response Time: Xms"
```

## Troubleshooting

### If context hydration fails:
1. Verify Snowflake CLI is installed: `snow --version` or check `/Library/Frameworks/Python.framework/Versions/3.12/bin/snow`
2. Check connection config: `cat ~/.snowflake/config.toml`
3. Test database access: `snow sql -c poc -q "SHOW DATABASES;"`
4. Ensure CLAUDE_LOGS.ACTIVITIES schema exists
5. Check for SQL syntax errors in feature_json formatting

### If queries are slow:
1. Use pre-built views instead of custom queries
2. Run context hydration to cache schema: `./bin/snowflake-context-init`
3. Check if views need refreshing (materialized views may help)

### Manual context refresh:
```bash
rm -rf .claude_context
unset CLAUDE_SNOWFLAKE_INITIALIZED
./bin/snowflake-context-init BA
```

## Best Practices

1. **Always use context hydration** at session start for optimal performance
2. **Query views, not tables** for executive dashboards
3. **Use role-appropriate context** (BA for analytics, DE for engineering)
4. **Check .claude_context/** for available objects before writing custom queries
5. **Log hydration events** to track context initialization patterns