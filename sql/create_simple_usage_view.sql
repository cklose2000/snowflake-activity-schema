-- Simplified Daily Usage Metrics
-- Aggregates by hostname (most consistent identifier) and date

USE DATABASE CLAUDE_LOGS;
USE SCHEMA ACTIVITIES;

CREATE OR REPLACE VIEW V_USAGE_BY_DAY AS
SELECT 
    DATE(ts) as date,
    anonymous_customer_id as user_machine,
    -- Extract just the machine name for cleaner display
    SPLIT_PART(anonymous_customer_id, '.', 1) as user,
    
    -- Session metrics
    COUNT(DISTINCT CASE WHEN activity = 'claude_session_start' THEN customer END) as sessions,
    
    -- Token usage (from session_end events)
    SUM(CASE 
        WHEN activity = 'claude_session_end' 
        THEN COALESCE(feature_json:total_tokens::NUMBER, 0) 
        ELSE 0 
    END) as tokens_used,
    
    -- Lines of code written (from file operations)
    SUM(CASE 
        WHEN activity = 'claude_file_operation' 
        AND feature_json:operation::STRING IN ('create', 'edit', 'write')
        THEN COALESCE(feature_json:lines_affected::NUMBER, 0) 
        ELSE 0 
    END) as lines_written,
    
    -- Tool usage count
    SUM(CASE WHEN activity = 'claude_tool_call' THEN 1 ELSE 0 END) as tools_used,
    
    -- Estimated cost ($3 per 1M tokens for Claude-3-sonnet input)
    ROUND(SUM(CASE 
        WHEN activity = 'claude_session_end' 
        THEN COALESCE(feature_json:total_tokens::NUMBER, 0) 
        ELSE 0 
    END) * 0.000003, 4) as estimated_cost_usd
    
FROM CLAUDE_LOGS.ACTIVITIES.ACTIVITY_STREAM
WHERE activity IN ('claude_session_start', 'claude_session_end', 'claude_file_operation', 'claude_tool_call')
GROUP BY date, anonymous_customer_id
ORDER BY date DESC, tokens_used DESC;

-- Also create a summary view
CREATE OR REPLACE VIEW V_USAGE_SUMMARY AS
SELECT 
    user,
    COUNT(DISTINCT date) as active_days,
    SUM(sessions) as total_sessions,
    SUM(tokens_used) as total_tokens,
    SUM(lines_written) as total_lines_written,
    SUM(tools_used) as total_tools_used,
    ROUND(AVG(tokens_used), 0) as avg_tokens_per_day,
    ROUND(AVG(lines_written), 0) as avg_lines_per_day,
    SUM(estimated_cost_usd) as total_cost_usd
FROM V_USAGE_BY_DAY
GROUP BY user
ORDER BY total_tokens DESC;