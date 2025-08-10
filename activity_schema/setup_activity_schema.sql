-- ActivitySchema v2.0 Setup Script for Claude Code
-- This script creates the complete ActivitySchema infrastructure in Snowflake
-- Following the v2.0 specification exactly

-- Create the Claude Logs database
CREATE DATABASE IF NOT EXISTS CLAUDE_LOGS;
USE DATABASE CLAUDE_LOGS;

-- Create the activities schema
CREATE SCHEMA IF NOT EXISTS ACTIVITIES;
USE SCHEMA ACTIVITIES;

-- Create the main activity stream table following ActivitySchema v2.0
CREATE TABLE IF NOT EXISTS ACTIVITY_STREAM (
    -- Core ActivitySchema columns
    activity_id STRING NOT NULL,
    ts TIMESTAMP_NTZ NOT NULL,
    activity STRING NOT NULL,
    customer STRING,
    anonymous_customer_id STRING,
    feature_json VARIANT,
    revenue_impact FLOAT,
    link STRING,
    
    -- Helper columns for temporal queries (optional but recommended)
    activity_occurrence INT,
    activity_repeated_at TIMESTAMP_NTZ,
    
    -- Constraints
    PRIMARY KEY (activity_id),
    -- Ensure uniqueness of activity-timestamp-customer
    UNIQUE (activity, ts, customer)
);

-- Create indexes for performance (adjust based on your query patterns)
ALTER TABLE ACTIVITY_STREAM CLUSTER BY (activity, ts);

-- Create a view specifically for Claude Code activities
CREATE OR REPLACE VIEW V_CLAUDE_ACTIVITIES AS
SELECT 
    activity_id,
    ts,
    activity,
    customer as session_id,  -- For Claude, 'customer' is the session ID
    anonymous_customer_id as host_id,  -- Host machine identifier
    
    -- Extract common features from feature_json
    feature_json:tool_name::STRING as tool_name,
    feature_json:command::STRING as command,
    feature_json:parameters as parameters,
    feature_json:result_type::STRING as result_type,
    feature_json:error_message::STRING as error_message,
    feature_json:duration_ms::INT as duration_ms,
    feature_json:tokens_used::INT as tokens_used,
    feature_json:confidence_score::FLOAT as confidence_score,
    feature_json:project_path::STRING as project_path,
    feature_json:git_branch::STRING as git_branch,
    feature_json:file_path::STRING as file_path,
    
    -- Full feature JSON for detailed analysis
    feature_json,
    
    -- Revenue impact (e.g., cost of API calls)
    revenue_impact,
    
    -- Link to relevant resource
    link
FROM ACTIVITY_STREAM
WHERE activity LIKE 'claude_%' OR activity LIKE 'ccode_%';

-- Create helper functions for activity occurrence tracking
CREATE OR REPLACE PROCEDURE UPDATE_ACTIVITY_OCCURRENCES(
    ACTIVITY_NAME STRING
)
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
    -- Update activity_occurrence for the specified activity
    UPDATE ACTIVITY_STREAM t1
    SET activity_occurrence = (
        SELECT COUNT(*)
        FROM ACTIVITY_STREAM t2
        WHERE t2.customer = t1.customer
        AND t2.activity = t1.activity
        AND t2.ts <= t1.ts
    )
    WHERE t1.activity = :ACTIVITY_NAME
    AND t1.activity_occurrence IS NULL;
    
    -- Update activity_repeated_at
    UPDATE ACTIVITY_STREAM t1
    SET activity_repeated_at = (
        SELECT MIN(t2.ts)
        FROM ACTIVITY_STREAM t2
        WHERE t2.customer = t1.customer
        AND t2.activity = t1.activity
        AND t2.ts > t1.ts
    )
    WHERE t1.activity = :ACTIVITY_NAME
    AND t1.activity_repeated_at IS NULL;
    
    RETURN 'Updated occurrences for ' || :ACTIVITY_NAME;
END;
$$;

-- Create sample activity definitions for Claude Code
CREATE TABLE IF NOT EXISTS ACTIVITY_DEFINITIONS (
    activity_name STRING PRIMARY KEY,
    description STRING,
    expected_features VARIANT,
    created_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Insert Claude Code activity definitions
INSERT INTO ACTIVITY_DEFINITIONS (activity_name, description, expected_features) 
SELECT * FROM (
    SELECT 
        'claude_session_start' as activity_name,
        'Claude Code session initiated' as description,
        PARSE_JSON('{"session_id": "string", "project_path": "string", "git_branch": "string", "user": "string", "host": "string"}') as expected_features
    UNION ALL
    SELECT 
        'claude_tool_call',
        'Claude Code executed a tool',
        PARSE_JSON('{"tool_name": "string", "parameters": "object", "result_type": "string", "duration_ms": "number", "tokens_used": "number"}')
    UNION ALL
    SELECT 
        'claude_file_operation',
        'Claude Code performed file operation',
        PARSE_JSON('{"operation": "string", "file_path": "string", "lines_affected": "number", "success": "boolean"}')
    UNION ALL
    SELECT 
        'claude_decision',
        'Claude Code made a decision',
        PARSE_JSON('{"decision_type": "string", "confidence_score": "number", "alternatives_considered": "array", "reasoning": "string"}')
    UNION ALL
    SELECT 
        'claude_sql_execution',
        'Claude Code executed SQL',
        PARSE_JSON('{"database": "string", "query_type": "string", "tables_affected": "array", "rows_affected": "number"}')
    UNION ALL
    SELECT 
        'claude_error',
        'Claude Code encountered an error',
        PARSE_JSON('{"error_type": "string", "error_message": "string", "stack_trace": "string", "recovery_action": "string"}')
    UNION ALL
    SELECT 
        'claude_session_end',
        'Claude Code session completed',
        PARSE_JSON('{"session_id": "string", "total_activities": "number", "total_tokens": "number", "session_duration_ms": "number"}')
) AS new_definitions
WHERE NOT EXISTS (
    SELECT 1 FROM ACTIVITY_DEFINITIONS 
    WHERE activity_name = new_definitions.activity_name
);

-- Create a materialized view for session summaries
CREATE MATERIALIZED VIEW IF NOT EXISTS MV_CLAUDE_SESSIONS AS
SELECT 
    customer as session_id,
    MIN(CASE WHEN activity = 'claude_session_start' THEN ts END) as session_start,
    MAX(CASE WHEN activity = 'claude_session_end' THEN ts END) as session_end,
    COUNT(*) as total_activities,
    COUNT(DISTINCT activity) as unique_activity_types,
    SUM(CASE WHEN activity = 'claude_tool_call' THEN 1 ELSE 0 END) as tool_calls,
    SUM(CASE WHEN activity = 'claude_error' THEN 1 ELSE 0 END) as errors,
    SUM(feature_json:tokens_used::INT) as total_tokens,
    SUM(revenue_impact) as total_cost,
    ARRAY_AGG(DISTINCT feature_json:tool_name::STRING) as tools_used,
    MAX(feature_json:project_path::STRING) as project_path
FROM ACTIVITY_STREAM
WHERE activity LIKE 'claude_%'
GROUP BY customer;

-- Create utility views
CREATE OR REPLACE VIEW V_RECENT_ACTIVITIES AS
SELECT 
    activity_id,
    ts,
    activity,
    customer,
    anonymous_customer_id,
    feature_json,
    revenue_impact,
    link,
    TIMEDIFF(second, ts, CURRENT_TIMESTAMP()) as seconds_ago,
    TIMEDIFF(minute, ts, CURRENT_TIMESTAMP()) as minutes_ago
FROM ACTIVITY_STREAM
WHERE ts >= DATEADD(hour, -24, CURRENT_TIMESTAMP())
ORDER BY ts DESC;

CREATE OR REPLACE VIEW V_ACTIVITY_STATS AS
SELECT 
    activity,
    DATE_TRUNC('hour', ts) as hour,
    COUNT(*) as activity_count,
    COUNT(DISTINCT customer) as unique_sessions,
    AVG(feature_json:duration_ms::INT) as avg_duration_ms,
    SUM(revenue_impact) as total_revenue_impact,
    MAX(ts) as last_occurrence
FROM ACTIVITY_STREAM
GROUP BY activity, DATE_TRUNC('hour', ts);

-- Grant permissions
GRANT USAGE ON DATABASE CLAUDE_LOGS TO ROLE PUBLIC;
GRANT USAGE ON SCHEMA ACTIVITIES TO ROLE PUBLIC;
GRANT SELECT, INSERT ON TABLE ACTIVITY_STREAM TO ROLE PUBLIC;
GRANT SELECT ON ALL VIEWS IN SCHEMA ACTIVITIES TO ROLE PUBLIC;

-- Display confirmation
SELECT 'ActivitySchema v2.0 setup complete!' as status,
       'Database: CLAUDE_LOGS, Schema: ACTIVITIES' as location,
       'Main table: ACTIVITY_STREAM' as main_table,
       COUNT(*) as existing_activities
FROM ACTIVITY_STREAM;