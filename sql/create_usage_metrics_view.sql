-- Daily Usage Metrics View
-- Shows tokens consumed and lines of code written per user per day

USE DATABASE CLAUDE_LOGS;
USE SCHEMA ACTIVITIES;

CREATE OR REPLACE VIEW V_DAILY_USER_METRICS AS
WITH daily_tokens AS (
    -- Get tokens from session_end events
    SELECT 
        DATE(ts) as date,
        COALESCE(feature_json:user::STRING, anonymous_customer_id) as username,
        SUM(COALESCE(feature_json:total_tokens::NUMBER, 0)) as tokens_used
    FROM ACTIVITY_STREAM
    WHERE activity = 'claude_session_end'
    GROUP BY DATE(ts), username
),
daily_lines AS (
    -- Get lines written from file operations
    SELECT 
        DATE(ts) as date,
        COALESCE(feature_json:user::STRING, anonymous_customer_id) as username,
        SUM(COALESCE(feature_json:lines_affected::NUMBER, 0)) as lines_written
    FROM ACTIVITY_STREAM
    WHERE activity = 'claude_file_operation'
        AND feature_json:operation::STRING IN ('create', 'edit', 'write')
    GROUP BY DATE(ts), username
),
daily_sessions AS (
    -- Count sessions for context
    SELECT 
        DATE(ts) as date,
        COALESCE(feature_json:user::STRING, anonymous_customer_id) as username,
        COUNT(DISTINCT customer) as session_count
    FROM ACTIVITY_STREAM
    WHERE activity = 'claude_session_start'
    GROUP BY DATE(ts), username
)
SELECT 
    COALESCE(t.date, l.date, s.date) as date,
    COALESCE(t.username, l.username, s.username) as username,
    COALESCE(s.session_count, 0) as sessions,
    COALESCE(t.tokens_used, 0) as tokens_used,
    COALESCE(l.lines_written, 0) as lines_of_code_written,
    -- Calculate estimated cost (rough: $0.003 per 1K tokens for Claude-3-sonnet)
    ROUND(COALESCE(t.tokens_used, 0) * 0.000003, 4) as estimated_cost_usd
FROM daily_tokens t
FULL OUTER JOIN daily_lines l 
    ON t.date = l.date AND t.username = l.username
FULL OUTER JOIN daily_sessions s 
    ON COALESCE(t.date, l.date) = s.date 
    AND COALESCE(t.username, l.username) = s.username
ORDER BY date DESC, tokens_used DESC;

-- Grant permissions
GRANT SELECT ON VIEW V_DAILY_USER_METRICS TO ROLE claude_analyst;