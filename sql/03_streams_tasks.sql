-- ============================================================================
-- PHASE 3: Event-Driven Streams and Tasks
-- Automatic context refresh using Snowflake Streams and Tasks
-- ============================================================================

USE DATABASE CLAUDE_LOGS;
USE SCHEMA ACTIVITIES;

-- Log migration start
INSERT INTO ACTIVITY_SCHEMA_VERSION (
    git_sha,
    migration_name,
    status,
    rollback_sql
) VALUES (
    'v2.0.0',
    '03_streams_tasks',
    'running',
    'DROP STREAM IF EXISTS CLAUDE_STREAM_CHANGES; DROP STREAM IF EXISTS INSIGHT_ATOMS_CHANGES; DROP TASK IF EXISTS REFRESH_CONTEXT_TASK;'
);

-- ============================================================================
-- STREAMS FOR CHANGE DETECTION
-- ============================================================================

-- Stream to detect changes in activity data
CREATE OR REPLACE STREAM CLAUDE_STREAM_CHANGES 
ON TABLE CLAUDE_STREAM_V2
APPEND_ONLY = TRUE
SHOW_INITIAL_ROWS = FALSE
COMMENT = 'Captures new activities for context refresh';

-- Stream to detect changes in insights
CREATE OR REPLACE STREAM INSIGHT_ATOMS_CHANGES 
ON TABLE INSIGHT_ATOMS
APPEND_ONLY = FALSE
SHOW_INITIAL_ROWS = FALSE
COMMENT = 'Captures new and updated insights for context refresh';

-- ============================================================================
-- EVENT-DRIVEN CONTEXT REFRESH TASK
-- ============================================================================

CREATE OR REPLACE TASK REFRESH_CONTEXT_TASK
    WAREHOUSE = COMPUTE_XS
    SCHEDULE = '1 MINUTE'
    COMMENT = 'Event-driven context refresh with stale-while-revalidate'
    WHEN SYSTEM$STREAM_HAS_DATA('CLAUDE_STREAM_CHANGES') 
      OR SYSTEM$STREAM_HAS_DATA('INSIGHT_ATOMS_CHANGES')
AS
BEGIN
    -- Start transaction for atomic update
    BEGIN TRANSACTION;
    
    -- Update context cache for all affected customers
    MERGE INTO CONTEXT_CACHE target
    USING (
        WITH recent_activities AS (
            -- Get recent activities from stream
            SELECT DISTINCT
                customer,
                OBJECT_AGG(
                    activity || ':' || DATE_TRUNC('hour', ts),
                    COUNT(*)
                ) WITHIN GROUP (ORDER BY ts DESC) as activity_counts
            FROM CLAUDE_STREAM_CHANGES
            WHERE ts > DATEADD('hour', -24, CURRENT_TIMESTAMP())
            GROUP BY customer
        ),
        recent_insights AS (
            -- Get valid insights
            SELECT 
                customer,
                OBJECT_AGG(
                    subject || ':' || metric,
                    OBJECT_CONSTRUCT(
                        'value', value,
                        'confidence', confidence,
                        'artifact_id', artifact_id,
                        'valid_until', valid_until
                    )
                ) WITHIN GROUP (ORDER BY confidence DESC, ts DESC) as insights
            FROM INSIGHT_ATOMS
            WHERE valid_until > CURRENT_TIMESTAMP()
              AND is_stale = FALSE
              AND is_quarantined = FALSE
            GROUP BY customer
        ),
        recent_queries AS (
            -- Get recent successful queries
            SELECT 
                customer,
                ARRAY_AGG(
                    OBJECT_CONSTRUCT(
                        'activity_id', activity_id,
                        'ts', ts,
                        'sql', feature_json:sql::STRING,
                        'rows', feature_json:row_count::INT,
                        'artifact_id', link,
                        'warehouse', feature_json:warehouse::STRING
                    )
                ) WITHIN GROUP (ORDER BY ts DESC) as queries
            FROM (
                SELECT *
                FROM CLAUDE_STREAM_V2
                WHERE activity = 'query_complete'
                  AND feature_json:success::BOOLEAN = TRUE
                  AND ts > DATEADD('hour', -2, CURRENT_TIMESTAMP())
                QUALIFY ROW_NUMBER() OVER (PARTITION BY customer ORDER BY ts DESC) <= 10
            )
            GROUP BY customer
        ),
        tool_usage AS (
            -- Get tool usage patterns
            SELECT 
                customer,
                OBJECT_AGG(
                    feature_json:tool_name::STRING,
                    OBJECT_CONSTRUCT(
                        'count', COUNT(*),
                        'avg_latency_ms', AVG(feature_json:latency_ms::INT),
                        'p95_latency_ms', PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY feature_json:latency_ms::INT)
                    )
                ) as tool_stats
            FROM CLAUDE_STREAM_V2
            WHERE activity = 'tool_call'
              AND ts > DATEADD('hour', -6, CURRENT_TIMESTAMP())
            GROUP BY customer
        ),
        context_summary AS (
            -- Combine all context elements
            SELECT 
                COALESCE(a.customer, i.customer, q.customer, t.customer) as customer,
                'default' as context_type,
                OBJECT_CONSTRUCT(
                    'activities', a.activity_counts,
                    'insights', i.insights,
                    'recent_queries', q.queries,
                    'tool_usage', t.tool_stats,
                    'refreshed_at', CURRENT_TIMESTAMP(),
                    'refresh_lag_ms', DATEDIFF('millisecond', 
                        (SELECT MAX(ts) FROM CLAUDE_STREAM_CHANGES), 
                        CURRENT_TIMESTAMP()
                    ),
                    'is_stale', FALSE
                ) as context_blob
            FROM recent_activities a
            FULL OUTER JOIN recent_insights i ON a.customer = i.customer
            FULL OUTER JOIN recent_queries q ON COALESCE(a.customer, i.customer) = q.customer
            FULL OUTER JOIN tool_usage t ON COALESCE(a.customer, i.customer, q.customer) = t.customer
        )
        SELECT * FROM context_summary
    ) source
    ON target.customer = source.customer AND target.context_type = source.context_type
    WHEN MATCHED THEN 
        UPDATE SET 
            context_blob = source.context_blob,
            updated_at = CURRENT_TIMESTAMP(),
            is_stale = FALSE,
            access_count = target.access_count + 1
    WHEN NOT MATCHED THEN 
        INSERT (customer, context_type, context_blob, updated_at, is_stale)
        VALUES (source.customer, source.context_type, source.context_blob, CURRENT_TIMESTAMP(), FALSE);
    
    -- Mark old contexts as stale (for stale-while-revalidate)
    UPDATE CONTEXT_CACHE
    SET is_stale = TRUE
    WHERE updated_at < DATEADD('second', -30, CURRENT_TIMESTAMP())
      AND is_stale = FALSE;
    
    -- Consume the streams to mark records as processed
    INSERT INTO ACTIVITY_SCHEMA_VERSION (
        migration_name,
        checksum_after
    )
    SELECT 
        'context_refresh_' || TO_VARCHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS'),
        OBJECT_CONSTRUCT(
            'stream_records', COUNT(*),
            'customers_updated', COUNT(DISTINCT customer)
        )
    FROM CLAUDE_STREAM_CHANGES;
    
    COMMIT;
END;

-- ============================================================================
-- ADDITIONAL SPECIALIZED TASKS
-- ============================================================================

-- Task to detect and handle schema drift
CREATE OR REPLACE TASK DETECT_SCHEMA_DRIFT_TASK
    WAREHOUSE = COMPUTE_XS
    SCHEDULE = 'USING CRON 0 */6 * * * America/Los_Angeles' -- Every 6 hours
    COMMENT = 'Detects schema changes and quarantines affected insights'
AS
BEGIN
    -- Check for new columns in feature_json
    WITH schema_analysis AS (
        SELECT 
            f.key as column_name,
            COUNT(DISTINCT f.value:type) as type_variations,
            MODE(f.value:type) as dominant_type,
            COUNT(*) as occurrences
        FROM CLAUDE_STREAM_V2,
             LATERAL FLATTEN(input => feature_json) f
        WHERE ts > DATEADD('hour', -24, CURRENT_TIMESTAMP())
        GROUP BY f.key
    ),
    expected_schema AS (
        -- Define expected schema (would be in a config table in production)
        SELECT column_name, expected_type
        FROM VALUES
            ('tool_name', 'STRING'),
            ('parameters', 'OBJECT'),
            ('latency_ms', 'NUMBER'),
            ('success', 'BOOLEAN'),
            ('error', 'STRING'),
            ('warehouse', 'STRING'),
            ('role', 'STRING'),
            ('bytes_scanned', 'NUMBER'),
            ('rows', 'NUMBER'),
            ('model', 'STRING'),
            ('prompt_tokens', 'NUMBER'),
            ('completion_tokens', 'NUMBER')
        AS t(column_name, expected_type)
    ),
    drift_detection AS (
        SELECT 
            s.column_name,
            s.dominant_type as actual_type,
            e.expected_type,
            CASE 
                WHEN e.expected_type IS NULL THEN 'NEW_COLUMN'
                WHEN s.dominant_type != e.expected_type THEN 'TYPE_CHANGE'
                WHEN s.type_variations > 1 THEN 'TYPE_INCONSISTENCY'
                ELSE 'OK'
            END as drift_status
        FROM schema_analysis s
        LEFT JOIN expected_schema e ON s.column_name = e.column_name
        WHERE drift_status != 'OK'
    )
    -- Log schema drift events
    INSERT INTO CLAUDE_STREAM_V2 (
        activity_id,
        activity,
        customer,
        feature_json
    )
    SELECT 
        UUID_STRING(),
        'schema_drift_detected',
        'SYSTEM',
        OBJECT_CONSTRUCT(
            'drift_type', drift_status,
            'column', column_name,
            'expected_type', expected_type,
            'actual_type', actual_type,
            'action', 'quarantine_insights'
        )
    FROM drift_detection;
    
    -- Quarantine affected insights
    UPDATE INSIGHT_ATOMS
    SET is_quarantined = TRUE,
        quarantine_reason = 'Schema drift detected'
    WHERE artifact_id IN (
        SELECT DISTINCT link
        FROM CLAUDE_STREAM_V2
        WHERE ts > DATEADD('hour', -24, CURRENT_TIMESTAMP())
          AND feature_json IS NOT NULL
    )
    AND is_quarantined = FALSE;
END;

-- Task to calculate and store aggregate metrics
CREATE OR REPLACE TASK CALCULATE_METRICS_TASK
    WAREHOUSE = COMPUTE_XS
    SCHEDULE = 'USING CRON 0 * * * * America/Los_Angeles' -- Every hour
    COMMENT = 'Calculates aggregate metrics for monitoring'
AS
BEGIN
    -- Calculate hourly metrics
    INSERT INTO INSIGHT_ATOMS (
        customer,
        subject,
        metric,
        value,
        grain,
        confidence,
        derivation_method
    )
    SELECT 
        customer,
        'system_performance',
        'hourly_latency_p95',
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY feature_json:latency_ms::INT),
        'hourly',
        1.0,
        'aggregate_calculation'
    FROM CLAUDE_STREAM_V2
    WHERE activity = 'mcp_call'
      AND ts > DATEADD('hour', -1, CURRENT_TIMESTAMP())
      AND feature_json:latency_ms IS NOT NULL
    GROUP BY customer;
    
    -- Calculate query success rates
    INSERT INTO INSIGHT_ATOMS (
        customer,
        subject,
        metric,
        value,
        grain,
        confidence,
        derivation_method
    )
    SELECT 
        customer,
        'query_performance',
        'success_rate',
        SUM(CASE WHEN feature_json:success::BOOLEAN = TRUE THEN 1 ELSE 0 END) * 100.0 / COUNT(*),
        'daily',
        0.95,
        'aggregate_calculation'
    FROM CLAUDE_STREAM_V2
    WHERE activity IN ('query_complete', 'query_error')
      AND ts > DATEADD('day', -1, CURRENT_TIMESTAMP())
    GROUP BY customer
    HAVING COUNT(*) > 10; -- Only if sufficient sample size
END;

-- ============================================================================
-- TASK MANAGEMENT
-- ============================================================================

-- Enable tasks (must be done after creation)
ALTER TASK CALCULATE_METRICS_TASK RESUME;
ALTER TASK DETECT_SCHEMA_DRIFT_TASK RESUME;
ALTER TASK REFRESH_CONTEXT_TASK RESUME;

-- ============================================================================
-- MONITORING VIEWS
-- ============================================================================

-- View to monitor stream lag
CREATE OR REPLACE VIEW V_STREAM_LAG
COMMENT = 'Monitors lag between events and context refresh'
AS
SELECT 
    'CLAUDE_STREAM_CHANGES' as stream_name,
    COUNT(*) as pending_records,
    MIN(ts) as oldest_record,
    MAX(ts) as newest_record,
    DATEDIFF('second', MIN(ts), CURRENT_TIMESTAMP()) as max_lag_seconds,
    DATEDIFF('millisecond', MAX(ts), CURRENT_TIMESTAMP()) as min_lag_ms
FROM CLAUDE_STREAM_CHANGES
UNION ALL
SELECT 
    'INSIGHT_ATOMS_CHANGES' as stream_name,
    COUNT(*) as pending_records,
    MIN(ts) as oldest_record,
    MAX(ts) as newest_record,
    DATEDIFF('second', MIN(ts), CURRENT_TIMESTAMP()) as max_lag_seconds,
    DATEDIFF('millisecond', MAX(ts), CURRENT_TIMESTAMP()) as min_lag_ms
FROM INSIGHT_ATOMS_CHANGES;

-- View to monitor task execution
CREATE OR REPLACE VIEW V_TASK_MONITORING
COMMENT = 'Monitors task execution and performance'
AS
SELECT 
    name as task_name,
    state,
    scheduled_time,
    completed_time,
    DATEDIFF('second', scheduled_time, completed_time) as duration_seconds,
    error_message,
    CASE 
        WHEN state = 'SUCCEEDED' THEN 'healthy'
        WHEN state = 'FAILED' THEN 'critical'
        WHEN state = 'SKIPPED' THEN 'warning'
        ELSE 'unknown'
    END as health_status
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
    SCHEDULED_TIME_RANGE_START => DATEADD('hour', -24, CURRENT_TIMESTAMP()),
    TASK_NAME => 'REFRESH_CONTEXT_TASK'
))
ORDER BY scheduled_time DESC;

-- ============================================================================
-- GRANTS
-- ============================================================================

GRANT SELECT ON STREAM CLAUDE_STREAM_CHANGES TO PUBLIC;
GRANT SELECT ON STREAM INSIGHT_ATOMS_CHANGES TO PUBLIC;
GRANT MONITOR ON TASK REFRESH_CONTEXT_TASK TO PUBLIC;
GRANT SELECT ON VIEW V_STREAM_LAG TO PUBLIC;
GRANT SELECT ON VIEW V_TASK_MONITORING TO PUBLIC;

-- ============================================================================
-- MIGRATION COMPLETION
-- ============================================================================

UPDATE ACTIVITY_SCHEMA_VERSION
SET status = 'completed',
    checksum_after = OBJECT_CONSTRUCT(
        'streams_created', 2,
        'tasks_created', 3,
        'views_created', 2
    )
WHERE migration_name = '03_streams_tasks'
  AND status = 'running';

-- Display summary
SELECT 
    'Streams and Tasks Setup Complete' as status,
    (SELECT COUNT(*) FROM information_schema.tables 
     WHERE table_schema = 'ACTIVITIES' 
     AND table_type = 'STREAM') as streams_created,
    (SELECT COUNT(*) FROM information_schema.task_history()
     WHERE name IN ('REFRESH_CONTEXT_TASK', 'DETECT_SCHEMA_DRIFT_TASK', 'CALCULATE_METRICS_TASK')
     AND scheduled_time > DATEADD('minute', -5, CURRENT_TIMESTAMP())) as tasks_active;