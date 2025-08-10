-- Learning-Oriented Views for ActivitySchema Education
-- These views are intentionally imperfect to teach important patterns

USE DATABASE CLAUDE_LOGS;
USE SCHEMA ACTIVITIES;

-- ============================================================================
-- LEARNING VIEW 1: Discover the Orphaned Sessions Problem
-- ============================================================================
CREATE OR REPLACE VIEW V_LEARNING_ORPHANED_SESSIONS
COMMENT = 'Teaches why resilient event design matters - most sessions are orphaned!'
AS
WITH session_status AS (
    SELECT 
        customer as session_id,
        MAX(CASE WHEN activity = 'claude_session_start' THEN 1 ELSE 0 END) as has_start,
        MAX(CASE WHEN activity = 'claude_session_end' THEN 1 ELSE 0 END) as has_end,
        MIN(ts) as first_event,
        MAX(ts) as last_event
    FROM ACTIVITY_STREAM 
    WHERE activity LIKE 'claude_%'
    GROUP BY customer
)
SELECT 
    COUNT(*) as total_sessions,
    SUM(CASE WHEN has_end = 0 THEN 1 ELSE 0 END) as orphaned_sessions,
    SUM(CASE WHEN has_end = 1 THEN 1 ELSE 0 END) as completed_sessions,
    ROUND(100.0 * SUM(CASE WHEN has_end = 0 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 1) as orphan_rate_pct,
    '🎓 Lesson: This is why heartbeats and timeouts matter in event systems!' as learning_moment,
    '💡 Challenge: How would you detect abandoned sessions?' as student_challenge,
    '🤔 Question: What happens when users hit Ctrl+C?' as discussion_prompt
FROM session_status;

-- ============================================================================
-- LEARNING VIEW 2: Meta-Learning Tracker
-- ============================================================================
CREATE OR REPLACE VIEW V_META_LEARNING
COMMENT = 'Shows when users are studying the system itself - very meta!'
AS
SELECT 
    customer as session_id,
    MIN(ts) as session_start,
    MAX(ts) as last_activity,
    DATEDIFF('minute', MIN(ts), MAX(ts)) as duration_minutes,
    MAX(feature_json:project_path::STRING) as project_directory,
    CASE 
        WHEN project_directory LIKE '%snowflake-activity-schema%' 
        THEN '🔄 Learning about the learning system itself!'
        WHEN project_directory LIKE '%claude%'
        THEN '🤖 Working on Claude-related project'
        ELSE '💼 Using Claude for other work'
    END as meta_level,
    COUNT(*) as activity_count,
    CASE 
        WHEN session_start > DATEADD(minute, -10, CURRENT_TIMESTAMP())
        THEN '👉 YOU ARE HERE'
        ELSE ''
    END as your_session_marker
FROM ACTIVITY_STREAM
WHERE activity LIKE 'claude_%'
GROUP BY customer
ORDER BY session_start DESC
LIMIT 20;

-- ============================================================================
-- LEARNING VIEW 3: System Evolution Tracker
-- ============================================================================
CREATE OR REPLACE VIEW V_SYSTEM_EVOLUTION
COMMENT = 'Watch the logging system evolve as students add features'
AS
SELECT 
    DATE(ts) as day,
    COUNT(DISTINCT activity) as unique_activity_types,
    COUNT(*) as total_events,
    COUNT(DISTINCT customer) as unique_sessions,
    COUNT(DISTINCT anonymous_customer_id) as unique_users,
    LISTAGG(DISTINCT activity, ', ') WITHIN GROUP (ORDER BY activity) as activities_logged,
    CASE 
        WHEN unique_activity_types <= 2 THEN '🌱 Phase 1: Basic session logging'
        WHEN unique_activity_types <= 4 THEN '🌿 Phase 2: Adding activity types'
        WHEN unique_activity_types <= 6 THEN '🌳 Phase 3: Detailed tracking'
        ELSE '🌲 Phase 4: Mature system'
    END as maturity_level,
    '📈 Watch this grow as we add more logging!' as trajectory
FROM ACTIVITY_STREAM
WHERE activity LIKE 'claude_%' OR activity LIKE 'ccode_%'
GROUP BY DATE(ts)
ORDER BY day DESC;

-- ============================================================================
-- LEARNING VIEW 4: Pattern Discovery View
-- ============================================================================
CREATE OR REPLACE VIEW V_PATTERN_DISCOVERY
COMMENT = 'Helps students discover patterns in their Claude usage'
AS
WITH usage_patterns AS (
    SELECT 
        HOUR(ts) as hour_of_day,
        DAYNAME(ts) as day_of_week,
        COUNT(*) as activity_count,
        COUNT(DISTINCT customer) as session_count
    FROM ACTIVITY_STREAM
    WHERE activity LIKE 'claude_%'
    GROUP BY HOUR(ts), DAYNAME(ts)
)
SELECT 
    hour_of_day,
    day_of_week,
    activity_count,
    session_count,
    CASE 
        WHEN hour_of_day BETWEEN 9 AND 17 THEN '🏢 Business hours'
        WHEN hour_of_day BETWEEN 18 AND 23 THEN '🌙 Evening learning'
        WHEN hour_of_day BETWEEN 0 AND 8 THEN '🌅 Early bird'
        ELSE '🤔 Unusual time'
    END as time_pattern,
    '❓ What does this tell us about learning habits?' as reflection_question
FROM usage_patterns
ORDER BY activity_count DESC
LIMIT 20;

-- ============================================================================
-- LEARNING VIEW 5: The Recursive Query Challenge
-- ============================================================================
CREATE OR REPLACE VIEW V_RECURSIVE_LEARNING
COMMENT = 'Find sessions where users analyzed their own sessions - meta!'
AS
WITH recursive_sessions AS (
    SELECT 
        a1.customer as analyzing_session,
        a1.ts as analysis_time,
        a2.customer as analyzed_session,
        a2.ts as original_time,
        DATEDIFF('minute', a2.ts, a1.ts) as minutes_between
    FROM ACTIVITY_STREAM a1
    JOIN ACTIVITY_STREAM a2 
        ON a1.customer != a2.customer
        AND a1.ts > a2.ts
        AND a1.feature_json:project_path::STRING LIKE '%snowflake-activity-schema%'
    WHERE a1.activity = 'claude_session_start'
        AND a2.activity = 'claude_session_start'
)
SELECT 
    analyzing_session,
    analysis_time,
    COUNT(DISTINCT analyzed_session) as sessions_studied,
    MIN(minutes_between) as minutes_after_first_session,
    '🎯 Achievement: Using Claude to study Claude usage!' as meta_achievement,
    '🏆 Next Level: Can you write a query to find your own learning velocity?' as next_challenge
FROM recursive_sessions
GROUP BY analyzing_session, analysis_time
ORDER BY analysis_time DESC;

-- ============================================================================
-- LEARNING VIEW 6: Cost Education View
-- ============================================================================
CREATE OR REPLACE VIEW V_COST_LEARNING
COMMENT = 'Teaches about token estimation and cost calculation'
AS
SELECT 
    DATE(ts) as day,
    COUNT(*) as activities,
    SUM(revenue_impact) as calculated_cost,
    SUM(feature_json:tokens_used::INT) as reported_tokens,
    SUM(feature_json:session_duration_ms::INT) / 1000 as total_seconds,
    ROUND(calculated_cost * 1000000, 2) as cost_in_microdollars,
    CASE 
        WHEN calculated_cost = 0 THEN '❌ No cost tracking yet'
        WHEN calculated_cost < 0.01 THEN '✅ Very efficient!'
        WHEN calculated_cost < 0.10 THEN '📊 Normal usage'
        ELSE '🚨 Heavy usage day'
    END as cost_assessment,
    '💰 Challenge: How would you calculate accurate token costs?' as economics_challenge,
    '📝 Homework: Research Claude API pricing and improve this calculation' as assignment
FROM ACTIVITY_STREAM
WHERE activity LIKE 'claude_%'
GROUP BY DATE(ts)
ORDER BY day DESC;

-- ============================================================================
-- BONUS: Create a Welcome View for New Users
-- ============================================================================
CREATE OR REPLACE VIEW V_WELCOME_NEW_LEARNERS
COMMENT = 'First view that new users should query'
AS
SELECT 
    '👋 Welcome to ActivitySchema Learning!' as greeting,
    '📚 Your Learning Path:' as next_steps,
    '1️⃣ Run: SELECT * FROM V_META_LEARNING;' as step_1,
    '2️⃣ Run: SELECT * FROM V_LEARNING_ORPHANED_SESSIONS;' as step_2,
    '3️⃣ Run: SELECT * FROM V_SYSTEM_EVOLUTION;' as step_3,
    '4️⃣ Challenge: Find your own orphaned sessions' as step_4,
    '5️⃣ Meta Challenge: Use Claude to improve these views!' as step_5,
    CURRENT_USER() as your_username,
    CURRENT_TIMESTAMP() as learning_started_at;

-- Grant permissions for learning
GRANT SELECT ON ALL VIEWS IN SCHEMA ACTIVITIES TO PUBLIC;

-- Display confirmation
SELECT 
    'Learning views created successfully!' as status,
    COUNT(*) as view_count,
    '🎓 Ready to start learning!' as message
FROM information_schema.views
WHERE table_schema = 'ACTIVITIES' 
    AND table_name LIKE 'V_LEARNING%' OR table_name LIKE 'V_%LEARNING%';