-- CQ Learning System: Make Claude Query smarter over time
-- This tracks successful queries and builds a knowledge base

USE DATABASE CLAUDE_LOGS;
USE SCHEMA ACTIVITIES;

-- Table to store successful CQ queries for learning
CREATE TABLE IF NOT EXISTS CQ_KNOWLEDGE_BASE (
    kb_id VARCHAR(100),
    created_ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    user_prompt VARCHAR(2000),           -- What the user asked
    generated_query VARCHAR(5000),        -- SQL that Claude generated
    query_success BOOLEAN,                -- Did it execute successfully?
    result_count NUMBER,                  -- How many rows returned
    execution_time_ms NUMBER,             -- How fast it ran
    user_rating VARCHAR(10),              -- Optional: thumbs up/down
    common_pattern VARCHAR(500),          -- Pattern category (e.g., "session_analysis")
    PRIMARY KEY (kb_id)
);

-- View: Most successful query patterns
CREATE OR REPLACE VIEW V_CQ_SUCCESSFUL_PATTERNS AS
SELECT 
    common_pattern,
    COUNT(*) as usage_count,
    AVG(execution_time_ms) as avg_execution_ms,
    SUM(CASE WHEN query_success THEN 1 ELSE 0 END) / COUNT(*) as success_rate,
    ARRAY_AGG(DISTINCT user_prompt) as example_prompts,
    ARRAY_AGG(DISTINCT generated_query) as example_queries
FROM CQ_KNOWLEDGE_BASE
WHERE query_success = TRUE
GROUP BY common_pattern
ORDER BY usage_count DESC;

-- View: Common executive queries and their optimized SQL
CREATE OR REPLACE VIEW V_CQ_EXECUTIVE_TEMPLATES AS
SELECT 
    user_prompt,
    generated_query,
    result_count,
    execution_time_ms,
    created_ts
FROM CQ_KNOWLEDGE_BASE
WHERE query_success = TRUE
    AND (
        LOWER(user_prompt) LIKE '%executive%'
        OR LOWER(user_prompt) LIKE '%cost%'
        OR LOWER(user_prompt) LIKE '%metric%'
        OR LOWER(user_prompt) LIKE '%dashboard%'
        OR LOWER(user_prompt) LIKE '%summary%'
    )
ORDER BY 
    CASE 
        WHEN user_rating = 'excellent' THEN 1
        WHEN user_rating = 'good' THEN 2
        ELSE 3
    END,
    execution_time_ms ASC;

-- View: Failed queries for improvement
CREATE OR REPLACE VIEW V_CQ_LEARNING_OPPORTUNITIES AS
SELECT 
    user_prompt,
    generated_query,
    created_ts,
    'Query Failed' as issue_type
FROM CQ_KNOWLEDGE_BASE
WHERE query_success = FALSE
UNION ALL
SELECT 
    user_prompt,
    generated_query,
    created_ts,
    'No Results' as issue_type
FROM CQ_KNOWLEDGE_BASE
WHERE query_success = TRUE AND result_count = 0
ORDER BY created_ts DESC;

-- Function to log CQ usage (called from the shell script)
CREATE OR REPLACE PROCEDURE LOG_CQ_QUERY(
    prompt VARCHAR,
    query VARCHAR,
    success BOOLEAN,
    row_count NUMBER,
    exec_time NUMBER
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
    INSERT INTO CQ_KNOWLEDGE_BASE (
        kb_id,
        user_prompt,
        generated_query,
        query_success,
        result_count,
        execution_time_ms,
        common_pattern
    ) VALUES (
        UUID_STRING(),
        prompt,
        query,
        success,
        row_count,
        exec_time,
        CASE 
            WHEN LOWER(prompt) LIKE '%orphan%' THEN 'orphan_analysis'
            WHEN LOWER(prompt) LIKE '%cost%' THEN 'cost_analysis'
            WHEN LOWER(prompt) LIKE '%session%' THEN 'session_analysis'
            WHEN LOWER(prompt) LIKE '%tool%' THEN 'tool_usage'
            WHEN LOWER(prompt) LIKE '%metric%' OR LOWER(prompt) LIKE '%executive%' THEN 'executive_metrics'
            WHEN LOWER(prompt) LIKE '%trend%' OR LOWER(prompt) LIKE '%time%' THEN 'trend_analysis'
            ELSE 'general_query'
        END
    );
    RETURN 'Query logged for learning';
END;
$$;

-- View: CQ Intelligence Report (how smart is CQ getting?)
CREATE OR REPLACE VIEW V_CQ_INTELLIGENCE_METRICS AS
WITH daily_stats AS (
    SELECT 
        DATE(created_ts) as query_date,
        COUNT(*) as total_queries,
        SUM(CASE WHEN query_success THEN 1 ELSE 0 END) as successful_queries,
        AVG(execution_time_ms) as avg_exec_time,
        COUNT(DISTINCT common_pattern) as pattern_diversity
    FROM CQ_KNOWLEDGE_BASE
    GROUP BY DATE(created_ts)
)
SELECT 
    query_date,
    total_queries,
    successful_queries / NULLIF(total_queries, 0) as success_rate,
    avg_exec_time,
    pattern_diversity,
    SUM(total_queries) OVER (ORDER BY query_date) as cumulative_queries,
    AVG(successful_queries / NULLIF(total_queries, 0)) 
        OVER (ORDER BY query_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) as rolling_7day_success_rate
FROM daily_stats
ORDER BY query_date DESC;

-- Sample queries to seed the knowledge base
INSERT INTO CQ_KNOWLEDGE_BASE (kb_id, user_prompt, generated_query, query_success, result_count, execution_time_ms, common_pattern)
SELECT * FROM VALUES
    (UUID_STRING(), 'show executive metrics', 'SELECT * FROM V_EXECUTIVE_SUMMARY;', TRUE, 1, 120, 'executive_metrics'),
    (UUID_STRING(), 'find orphaned sessions', 'SELECT * FROM V_LEARNING_ORPHANED_SESSIONS;', TRUE, 45, 230, 'orphan_analysis'),
    (UUID_STRING(), 'calculate costs', 'SELECT SUM(estimated_cost) FROM V_COST_FANTASY;', TRUE, 1, 89, 'cost_analysis'),
    (UUID_STRING(), 'show usage trends', 'SELECT DATE(ts), COUNT(*) FROM ACTIVITY_STREAM GROUP BY DATE(ts) ORDER BY 1 DESC;', TRUE, 30, 156, 'trend_analysis')
WHERE NOT EXISTS (SELECT 1 FROM CQ_KNOWLEDGE_BASE LIMIT 1);

-- Grant permissions
GRANT SELECT ON ALL VIEWS IN SCHEMA ACTIVITIES TO ROLE claude_analyst;
GRANT SELECT, INSERT ON TABLE CQ_KNOWLEDGE_BASE TO ROLE claude_analyst;
GRANT USAGE ON PROCEDURE LOG_CQ_QUERY(VARCHAR, VARCHAR, BOOLEAN, NUMBER, NUMBER) TO ROLE claude_analyst;