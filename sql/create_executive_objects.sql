-- Create Executive Views and Initialization Procedure for Claude Code Context Hydration
-- Run this script to set up all executive-level database objects

USE DATABASE CLAUDE_LOGS;
USE SCHEMA ACTIVITIES;

-- ============================================================================
-- EXECUTIVE VIEWS
-- ============================================================================

-- 1. Executive Summary View - High-level KPIs for leadership
CREATE OR REPLACE VIEW V_EXECUTIVE_SUMMARY
COMMENT = 'Executive dashboard with key performance indicators for Claude Code usage'
AS
SELECT 
    CURRENT_DATE() as report_date,
    CURRENT_TIMESTAMP() as last_updated,
    
    -- User Metrics
    COUNT(DISTINCT customer) as total_sessions,
    COUNT(DISTINCT anonymous_customer_id) as unique_users,
    
    -- Activity Metrics
    COUNT(*) as total_activities,
    SUM(CASE WHEN activity = 'claude_tool_call' THEN 1 ELSE 0 END) as tool_executions,
    SUM(CASE WHEN activity = 'claude_file_operation' THEN 1 ELSE 0 END) as file_operations,
    SUM(CASE WHEN activity = 'claude_error' THEN 1 ELSE 0 END) as errors_encountered,
    
    -- Financial Metrics
    ROUND(SUM(revenue_impact), 6) as total_cost_usd,
    ROUND(AVG(revenue_impact), 8) as avg_cost_per_activity,
    
    -- Usage Patterns
    COUNT(DISTINCT DATE(ts)) as days_active,
    COUNT(DISTINCT feature_json:project_path::STRING) as projects_touched,
    COUNT(DISTINCT feature_json:git_branch::STRING) as git_branches_worked,
    
    -- Performance Metrics
    ROUND(AVG(feature_json:duration_ms::INT), 2) as avg_response_time_ms,
    ROUND(MAX(feature_json:duration_ms::INT), 2) as max_response_time_ms,
    ROUND(SUM(feature_json:tokens_used::INT), 0) as total_tokens_consumed
    
FROM ACTIVITY_STREAM
WHERE activity LIKE 'claude_%'
    AND ts >= DATEADD('day', -30, CURRENT_DATE());

-- 2. User Adoption View - Track user growth and engagement
CREATE OR REPLACE VIEW V_USER_ADOPTION
COMMENT = 'Daily user adoption and engagement metrics'
AS
SELECT 
    DATE_TRUNC('day', ts) as activity_date,
    COUNT(DISTINCT anonymous_customer_id) as daily_active_users,
    COUNT(DISTINCT customer) as daily_sessions,
    COUNT(*) as daily_activities,
    
    -- Engagement Metrics
    ROUND(COUNT(*) / NULLIF(COUNT(DISTINCT customer), 0), 2) as avg_activities_per_session,
    COUNT(DISTINCT feature_json:tool_name::STRING) as unique_tools_used,
    
    -- User Breakdown
    LISTAGG(DISTINCT anonymous_customer_id, ', ') WITHIN GROUP (ORDER BY anonymous_customer_id) as user_list,
    
    -- Growth Metrics (requires window functions)
    LAG(COUNT(DISTINCT anonymous_customer_id), 1) OVER (ORDER BY DATE_TRUNC('day', ts)) as previous_day_users,
    ROUND(
        (COUNT(DISTINCT anonymous_customer_id) - LAG(COUNT(DISTINCT anonymous_customer_id), 1) OVER (ORDER BY DATE_TRUNC('day', ts))) 
        / NULLIF(LAG(COUNT(DISTINCT anonymous_customer_id), 1) OVER (ORDER BY DATE_TRUNC('day', ts)), 0) * 100, 
        2
    ) as daily_growth_percentage
    
FROM ACTIVITY_STREAM
WHERE activity LIKE 'claude_%'
GROUP BY DATE_TRUNC('day', ts)
ORDER BY activity_date DESC;

-- 3. Tool Usage Analytics - Detailed tool performance metrics
CREATE OR REPLACE VIEW V_TOOL_USAGE_ANALYTICS
COMMENT = 'Detailed analytics on Claude Code tool usage patterns'
AS
SELECT 
    feature_json:tool_name::STRING as tool_name,
    COUNT(*) as usage_count,
    COUNT(DISTINCT customer) as unique_sessions,
    COUNT(DISTINCT anonymous_customer_id) as unique_users,
    
    -- Performance Metrics
    ROUND(AVG(feature_json:duration_ms::INT), 2) as avg_duration_ms,
    ROUND(MIN(feature_json:duration_ms::INT), 2) as min_duration_ms,
    ROUND(MAX(feature_json:duration_ms::INT), 2) as max_duration_ms,
    ROUND(STDDEV(feature_json:duration_ms::INT), 2) as stddev_duration_ms,
    
    -- Token Usage
    SUM(feature_json:tokens_used::INT) as total_tokens,
    ROUND(AVG(feature_json:tokens_used::INT), 2) as avg_tokens_per_call,
    
    -- Success Rate
    SUM(CASE WHEN feature_json:result_type::STRING = 'success' THEN 1 ELSE 0 END) as successful_calls,
    ROUND(
        SUM(CASE WHEN feature_json:result_type::STRING = 'success' THEN 1 ELSE 0 END) * 100.0 / 
        NULLIF(COUNT(*), 0), 
        2
    ) as success_rate_percentage,
    
    -- Cost Analysis
    SUM(revenue_impact) as total_cost,
    AVG(revenue_impact) as avg_cost_per_call,
    
    -- Temporal Patterns
    MIN(ts) as first_used,
    MAX(ts) as last_used,
    DATEDIFF('hour', MIN(ts), MAX(ts)) as hours_in_use
    
FROM ACTIVITY_STREAM
WHERE activity = 'claude_tool_call'
    AND feature_json:tool_name IS NOT NULL
GROUP BY feature_json:tool_name::STRING
ORDER BY usage_count DESC;

-- 4. Error Analysis View - Track and analyze errors
CREATE OR REPLACE VIEW V_ERROR_ANALYSIS
COMMENT = 'Error tracking and analysis for Claude Code sessions'
AS
SELECT 
    DATE_TRUNC('day', ts) as error_date,
    feature_json:error_type::STRING as error_type,
    feature_json:error_message::STRING as error_message,
    COUNT(*) as error_count,
    COUNT(DISTINCT customer) as affected_sessions,
    COUNT(DISTINCT anonymous_customer_id) as affected_users,
    
    -- Error Patterns
    LISTAGG(DISTINCT feature_json:tool_name::STRING, ', ') 
        WITHIN GROUP (ORDER BY feature_json:tool_name::STRING) as related_tools,
    
    -- Recovery Metrics
    SUM(CASE WHEN feature_json:recovery_action IS NOT NULL THEN 1 ELSE 0 END) as errors_with_recovery,
    
    -- Impact Assessment
    MAX(ts) as last_occurrence,
    MIN(ts) as first_occurrence
    
FROM ACTIVITY_STREAM
WHERE activity = 'claude_error' 
    OR feature_json:result_type::STRING = 'error'
GROUP BY 
    DATE_TRUNC('day', ts),
    feature_json:error_type::STRING,
    feature_json:error_message::STRING
ORDER BY error_date DESC, error_count DESC;

-- 5. Project Activity View - Track activity by project/repository
CREATE OR REPLACE VIEW V_PROJECT_ACTIVITY
COMMENT = 'Activity breakdown by project and repository'
AS
SELECT 
    feature_json:project_path::STRING as project_path,
    feature_json:git_branch::STRING as git_branch,
    COUNT(DISTINCT customer) as sessions,
    COUNT(DISTINCT anonymous_customer_id) as users,
    COUNT(*) as total_activities,
    
    -- Activity Breakdown
    SUM(CASE WHEN activity = 'claude_tool_call' THEN 1 ELSE 0 END) as tool_calls,
    SUM(CASE WHEN activity = 'claude_file_operation' THEN 1 ELSE 0 END) as file_operations,
    
    -- File Operations Detail
    COUNT(DISTINCT feature_json:file_path::STRING) as files_touched,
    SUM(feature_json:lines_affected::INT) as total_lines_modified,
    
    -- Time Metrics
    MIN(ts) as first_activity,
    MAX(ts) as last_activity,
    DATEDIFF('day', MIN(ts), MAX(ts)) as project_age_days,
    
    -- Cost Allocation
    SUM(revenue_impact) as project_cost
    
FROM ACTIVITY_STREAM
WHERE activity LIKE 'claude_%'
    AND feature_json:project_path IS NOT NULL
GROUP BY 
    feature_json:project_path::STRING,
    feature_json:git_branch::STRING
ORDER BY sessions DESC;

-- ============================================================================
-- STORED PROCEDURES
-- ============================================================================

-- Initialize Session Procedure - Returns role-specific context
CREATE OR REPLACE PROCEDURE INITIALIZE_SESSION(role VARCHAR DEFAULT 'BA')
RETURNS TABLE(context_type VARCHAR, context_value VARIANT)
LANGUAGE SQL
AS
$$
DECLARE
    res RESULTSET;
BEGIN
    -- Create temporary table for results
    CREATE OR REPLACE TEMPORARY TABLE session_context (
        context_type VARCHAR,
        context_value VARIANT
    );
    
    IF (role IN ('BA', 'ANALYST', 'BUSINESS')) THEN
        -- Business Analyst Context
        INSERT INTO session_context
        SELECT 
            'executive_views' as context_type,
            ARRAY_AGG(OBJECT_CONSTRUCT(
                'view_name', table_name,
                'description', COALESCE(comment, 'Executive view'),
                'sample_query', 'SELECT * FROM ' || table_catalog || '.' || table_schema || '.' || table_name || ' LIMIT 10;'
            )) as context_value
        FROM information_schema.views
        WHERE table_schema = 'ACTIVITIES'
            AND (table_name LIKE '%EXECUTIVE%' 
                OR table_name LIKE '%SUMMARY%'
                OR table_name LIKE '%KPI%'
                OR table_name LIKE '%ADOPTION%'
                OR table_name LIKE '%ANALYTICS%');
        
        -- Add recent successful queries for BA role
        INSERT INTO session_context
        SELECT 
            'recent_queries' as context_type,
            ARRAY_AGG(DISTINCT feature_json) as context_value
        FROM (
            SELECT feature_json
            FROM ACTIVITY_STREAM
            WHERE activity = 'claude_sql_execution'
                AND ts > DATEADD('day', -7, CURRENT_TIMESTAMP())
                AND feature_json:success::BOOLEAN = TRUE
            ORDER BY ts DESC
            LIMIT 10
        );
        
        -- Add quick stats
        INSERT INTO session_context
        SELECT 
            'quick_stats' as context_type,
            OBJECT_CONSTRUCT(
                'total_users', (SELECT COUNT(DISTINCT anonymous_customer_id) FROM ACTIVITY_STREAM WHERE activity LIKE 'claude_%'),
                'sessions_today', (SELECT COUNT(DISTINCT customer) FROM ACTIVITY_STREAM WHERE DATE(ts) = CURRENT_DATE()),
                'activities_last_hour', (SELECT COUNT(*) FROM ACTIVITY_STREAM WHERE ts >= DATEADD('hour', -1, CURRENT_TIMESTAMP()))
            ) as context_value;
            
    ELSE
        -- Data Engineer Context
        INSERT INTO session_context
        SELECT 
            'pipeline_objects' as context_type,
            ARRAY_AGG(OBJECT_CONSTRUCT(
                'object_name', procedure_name,
                'object_type', 'PROCEDURE',
                'arguments', argument_signature
            )) as context_value
        FROM information_schema.procedures
        WHERE procedure_schema = 'ACTIVITIES';
        
        -- Add table statistics
        INSERT INTO session_context
        SELECT 
            'table_stats' as context_type,
            OBJECT_CONSTRUCT(
                'activity_stream_rows', (SELECT COUNT(*) FROM ACTIVITY_STREAM),
                'last_insert', (SELECT MAX(ts) FROM ACTIVITY_STREAM),
                'storage_bytes', (SELECT bytes FROM information_schema.tables WHERE table_name = 'ACTIVITY_STREAM')
            ) as context_value;
            
        -- Add maintenance recommendations
        INSERT INTO session_context
        SELECT 
            'maintenance_tasks' as context_type,
            ARRAY_CONSTRUCT(
                CASE 
                    WHEN (SELECT COUNT(*) FROM ACTIVITY_STREAM) > 1000000 
                    THEN 'Consider partitioning ACTIVITY_STREAM table'
                    ELSE NULL
                END,
                CASE 
                    WHEN (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'ACTIVITIES' AND table_name LIKE '%_BACKUP%') = 0
                    THEN 'No backup tables found - consider creating backups'
                    ELSE NULL
                END
            ) as context_value;
    END IF;
    
    -- Add common context for all roles
    INSERT INTO session_context
    SELECT 
        'session_info' as context_type,
        OBJECT_CONSTRUCT(
            'role', role,
            'initialized_at', CURRENT_TIMESTAMP(),
            'database', CURRENT_DATABASE(),
            'schema', CURRENT_SCHEMA(),
            'warehouse', CURRENT_WAREHOUSE(),
            'user', CURRENT_USER()
        ) as context_value;
    
    -- Return results
    res := (SELECT * FROM session_context WHERE context_value IS NOT NULL);
    RETURN TABLE(res);
END;
$$;

-- Grant permissions
GRANT EXECUTE ON PROCEDURE INITIALIZE_SESSION(VARCHAR) TO PUBLIC;
GRANT SELECT ON ALL VIEWS IN SCHEMA ACTIVITIES TO PUBLIC;

-- Display confirmation
SELECT 'Executive objects created successfully!' as status,
       (SELECT COUNT(*) FROM information_schema.views 
        WHERE table_schema = 'ACTIVITIES' 
        AND table_name LIKE 'V_%') as view_count,
       (SELECT COUNT(*) FROM information_schema.procedures 
        WHERE procedure_schema = 'ACTIVITIES') as procedure_count;