-- Minimal COO Dashboard - Everything they need in one place
-- This creates simple views that work great in Snowflake's native dashboards

USE DATABASE CLAUDE_LOGS;
USE SCHEMA ACTIVITIES;

-- Main metrics view (for tiles/KPIs)
CREATE OR REPLACE VIEW V_COO_METRICS AS
SELECT 
    'Today' as period,
    COUNT(DISTINCT customer) as sessions,
    COUNT(DISTINCT anonymous_customer_id) as users,
    COUNT(*) as activities,
    COALESCE(ROUND(SUM(revenue_impact) * 1000, 2), 0) as cost_dollars
FROM ACTIVITY_STREAM
WHERE DATE(ts) = CURRENT_DATE()

UNION ALL

SELECT 
    'This Week' as period,
    COUNT(DISTINCT customer) as sessions,
    COUNT(DISTINCT anonymous_customer_id) as users,
    COUNT(*) as activities,
    COALESCE(ROUND(SUM(revenue_impact) * 1000, 2), 0) as cost_dollars
FROM ACTIVITY_STREAM  
WHERE ts >= DATEADD('week', -1, CURRENT_DATE())

UNION ALL

SELECT
    'This Month' as period,
    COUNT(DISTINCT customer) as sessions,
    COUNT(DISTINCT anonymous_customer_id) as users,
    COUNT(*) as activities,
    COALESCE(ROUND(SUM(revenue_impact) * 1000, 2), 0) as cost_dollars
FROM ACTIVITY_STREAM
WHERE ts >= DATEADD('month', -1, CURRENT_DATE())

ORDER BY 
    CASE period 
        WHEN 'Today' THEN 1 
        WHEN 'This Week' THEN 2 
        WHEN 'This Month' THEN 3 
    END;

-- Daily trend view (for line chart)
CREATE OR REPLACE VIEW V_COO_DAILY_TREND AS
SELECT 
    DATE(ts) as day,
    COUNT(DISTINCT customer) as sessions,
    COUNT(DISTINCT anonymous_customer_id) as users,
    COUNT(*) as activities
FROM ACTIVITY_STREAM
WHERE ts >= DATEADD('day', -30, CURRENT_DATE())
GROUP BY DATE(ts)
ORDER BY day;

-- Top users view (for leaderboard)
CREATE OR REPLACE VIEW V_COO_TOP_USERS AS
SELECT 
    anonymous_customer_id as user_name,
    COUNT(DISTINCT customer) as sessions_this_week,
    COUNT(*) as activities_this_week,
    COALESCE(ROUND(SUM(revenue_impact) * 1000, 2), 0) as cost_this_week
FROM ACTIVITY_STREAM
WHERE ts >= DATEADD('week', -1, CURRENT_DATE())
GROUP BY anonymous_customer_id
ORDER BY sessions_this_week DESC
LIMIT 10;

-- Simple activity log (for recent events)
CREATE OR REPLACE VIEW V_COO_RECENT_ACTIVITY AS
SELECT 
    ts as time,
    activity,
    customer as session_id,
    anonymous_customer_id as user,
    CASE 
        WHEN activity = 'claude_meta_query' THEN feature_json:prompt::STRING
        WHEN activity = 'claude_tool_call' THEN feature_json:tool_name::STRING
        WHEN activity = 'claude_file_operation' THEN feature_json:file_path::STRING
        ELSE NULL
    END as details
FROM ACTIVITY_STREAM
WHERE ts >= DATEADD('hour', -24, CURRENT_DATE())
ORDER BY ts DESC
LIMIT 100;

-- Health check view (for alerts)
CREATE OR REPLACE VIEW V_COO_HEALTH_CHECK AS
WITH current_hour AS (
    SELECT 
        COUNT(DISTINCT customer) as current_sessions,
        EXTRACT(hour FROM CURRENT_TIMESTAMP()) as current_hour_of_day
    FROM ACTIVITY_STREAM
    WHERE ts >= DATE_TRUNC('hour', CURRENT_TIMESTAMP())
),
historical_baseline AS (
    SELECT 
        EXTRACT(hour FROM DATE_TRUNC('hour', ts)) as hour_of_day,
        AVG(session_count) as avg_sessions,
        STDDEV(session_count) as stddev_sessions
    FROM (
        SELECT 
            DATE_TRUNC('hour', ts) as hour,
            COUNT(DISTINCT customer) as session_count
        FROM ACTIVITY_STREAM
        WHERE ts >= DATEADD('day', -7, CURRENT_DATE())
            AND ts < DATE_TRUNC('hour', CURRENT_TIMESTAMP())
        GROUP BY DATE_TRUNC('hour', ts)
    )
    GROUP BY hour_of_day
)
SELECT 
    CASE 
        WHEN c.current_sessions < (h.avg_sessions - 2 * COALESCE(h.stddev_sessions, 0)) THEN '⚠️ Low Activity'
        WHEN c.current_sessions > (h.avg_sessions + 2 * COALESCE(h.stddev_sessions, 0)) THEN '🚀 High Activity'
        ELSE '✅ Normal'
    END as status,
    c.current_sessions,
    ROUND(h.avg_sessions, 1) as typical_sessions,
    ROUND(((c.current_sessions - h.avg_sessions) / NULLIF(h.avg_sessions, 0)) * 100, 1) as percent_difference
FROM current_hour c
LEFT JOIN historical_baseline h ON c.current_hour_of_day = h.hour_of_day;

-- Grant permissions
GRANT SELECT ON ALL VIEWS IN SCHEMA ACTIVITIES TO ROLE claude_analyst;