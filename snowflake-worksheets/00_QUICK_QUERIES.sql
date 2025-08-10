-- CLAUDE ACTIVITY QUICK QUERIES
-- Copy any of these queries to run in Snowflake

-- 1. TODAY'S ACTIVITIES
SELECT * FROM CLAUDE_LOGS.ACTIVITIES.ACTIVITY_STREAM 
WHERE DATE(ts) = CURRENT_DATE()
ORDER BY ts DESC;

-- 2. EXECUTIVE SUMMARY
SELECT * FROM CLAUDE_LOGS.ACTIVITIES.V_EXECUTIVE_SUMMARY;

-- 3. ORPHANED SESSIONS (80% rate - this is intentional for learning!)
SELECT * FROM CLAUDE_LOGS.ACTIVITIES.V_LEARNING_ORPHANED_SESSIONS;

-- 4. META QUERIES (Queries about queries!)
SELECT 
    ts,
    customer as session_id,
    feature_json:prompt::STRING as question_asked,
    LEFT(feature_json:query_generated::STRING, 100) as sql_preview
FROM CLAUDE_LOGS.ACTIVITIES.ACTIVITY_STREAM
WHERE activity = 'claude_meta_query'
ORDER BY ts DESC;

-- 5. SESSION SUMMARY
SELECT 
    DATE(ts) as date,
    COUNT(DISTINCT customer) as unique_sessions,
    COUNT(*) as total_activities,
    SUM(CASE WHEN activity = 'claude_session_start' THEN 1 ELSE 0 END) as sessions_started,
    SUM(CASE WHEN activity = 'claude_session_end' THEN 1 ELSE 0 END) as sessions_ended
FROM CLAUDE_LOGS.ACTIVITIES.ACTIVITY_STREAM
GROUP BY DATE(ts)
ORDER BY date DESC;

-- 6. TOOL USAGE BREAKDOWN  
SELECT 
    feature_json:tool_name::STRING as tool,
    COUNT(*) as usage_count,
    AVG(feature_json:duration_ms::NUMBER) as avg_duration_ms
FROM CLAUDE_LOGS.ACTIVITIES.ACTIVITY_STREAM
WHERE activity = 'claude_tool_call'
GROUP BY tool
ORDER BY usage_count DESC;

-- 7. RECENT CQ QUERIES (Your natural language queries)
SELECT 
    ts,
    feature_json:prompt::STRING as your_question,
    feature_json:query_generated::STRING as generated_sql
FROM CLAUDE_LOGS.ACTIVITIES.ACTIVITY_STREAM
WHERE activity = 'claude_meta_query'
    AND ts > DATEADD('hour', -24, CURRENT_TIMESTAMP())
ORDER BY ts DESC;

-- 8. FILES TOUCHED
SELECT DISTINCT
    feature_json:file_path::STRING as file_path,
    COUNT(*) as operations_count,
    MAX(ts) as last_modified
FROM CLAUDE_LOGS.ACTIVITIES.ACTIVITY_STREAM
WHERE activity = 'claude_file_operation'
GROUP BY file_path
ORDER BY last_modified DESC;