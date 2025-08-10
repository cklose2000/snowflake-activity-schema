-- ============================================================================
-- PHASE 4: Typed Views with Standardized JSON
-- Parse feature_json VARIANT column into strongly-typed views
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
    '04_typed_views',
    'running',
    'DROP VIEW IF EXISTS VW_SQL_EVENTS; DROP VIEW IF EXISTS VW_LLM_EVENTS; DROP VIEW IF EXISTS VW_TOOL_EVENTS; DROP VIEW IF EXISTS VW_FILE_EVENTS; DROP VIEW IF EXISTS VW_SESSION_EVENTS; DROP VIEW IF EXISTS VW_MCP_EVENTS; DROP VIEW IF EXISTS VW_SYSTEM_EVENTS; DROP VIEW IF EXISTS VW_PRODUCT_METRICS;'
);

-- ============================================================================
-- SQL EVENTS VIEW
-- ============================================================================

CREATE OR REPLACE VIEW VW_SQL_EVENTS
COMMENT = 'Strongly-typed view of SQL query events with QUERY_HISTORY join'
AS
SELECT 
    -- Core fields
    cs.activity_id,
    cs.ts,
    cs.customer,
    cs.anonymous_customer_id,
    
    -- Parsed SQL event fields
    TRY_TO_VARCHAR(cs.feature_json:query_id) as query_id,
    TRY_TO_VARCHAR(cs.feature_json:sql) as sql_text,
    TRY_TO_VARCHAR(cs.feature_json:warehouse) as warehouse,
    TRY_TO_VARCHAR(cs.feature_json:role) as role,
    TRY_TO_VARCHAR(cs.feature_json:database) as database,
    TRY_TO_VARCHAR(cs.feature_json:schema) as schema,
    TRY_TO_NUMBER(cs.feature_json:rows) as rows_returned,
    TRY_TO_NUMBER(cs.feature_json:bytes_scanned) as bytes_scanned,
    TRY_TO_NUMBER(cs.feature_json:duration_ms) as duration_ms,
    TRY_TO_NUMBER(cs.feature_json:credits_used) as credits_used,
    TRY_TO_BOOLEAN(cs.feature_json:success) as success,
    TRY_TO_VARCHAR(cs.feature_json:error) as error_message,
    TRY_TO_VARCHAR(cs.feature_json:error_code) as error_code,
    
    -- Artifact link
    cs.link as artifact_id,
    
    -- QUERY_HISTORY enrichment (via QUERY_TAG)
    qh.query_id as snowflake_query_id,
    qh.query_text as actual_query_text,
    qh.database_name as actual_database,
    qh.schema_name as actual_schema,
    qh.warehouse_name as actual_warehouse,
    qh.warehouse_size,
    qh.warehouse_type,
    qh.bytes_scanned as qh_bytes_scanned,
    qh.bytes_written,
    qh.rows_produced as qh_rows_produced,
    qh.rows_inserted,
    qh.rows_updated,
    qh.rows_deleted,
    qh.credits_used_cloud_services as qh_credits,
    qh.execution_time as qh_execution_time_ms,
    qh.compilation_time,
    qh.queued_provisioning_time,
    qh.queued_repair_time,
    qh.queued_overload_time,
    qh.list_external_files_time,
    qh.error_code as qh_error_code,
    qh.error_message as qh_error_message,
    
    -- Calculated fields
    COALESCE(cs.revenue_impact, qh.credits_used_cloud_services * 0.00003) as total_cost_usd,
    CASE 
        WHEN TRY_TO_BOOLEAN(cs.feature_json:success) = TRUE THEN 'success'
        WHEN qh.error_code IS NOT NULL THEN 'failed'
        WHEN cs.link IS NOT NULL THEN 'completed'
        ELSE 'unknown'
    END as status
    
FROM CLAUDE_STREAM_V2 cs
LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY qh
    ON qh.query_tag = CONCAT('cdesk:', TRY_TO_VARCHAR(cs.feature_json:query_id))
    AND qh.start_time >= DATEADD('minute', -5, cs.ts)
    AND qh.start_time <= DATEADD('minute', 5, cs.ts)
WHERE cs.activity IN ('query_complete', 'query_submitted', 'sql_execution', 'claude_sql_execution');

-- ============================================================================
-- LLM EVENTS VIEW
-- ============================================================================

CREATE OR REPLACE VIEW VW_LLM_EVENTS
COMMENT = 'Strongly-typed view of LLM interaction events'
AS
SELECT 
    -- Core fields
    activity_id,
    ts,
    customer,
    anonymous_customer_id,
    
    -- Parsed LLM event fields
    TRY_TO_VARCHAR(feature_json:model) as model,
    TRY_TO_VARCHAR(feature_json:prompt_hash) as prompt_hash,
    TRY_TO_NUMBER(feature_json:prompt_tokens) as prompt_tokens,
    TRY_TO_NUMBER(feature_json:completion_tokens) as completion_tokens,
    TRY_TO_NUMBER(feature_json:total_tokens) as total_tokens,
    TRY_TO_NUMBER(feature_json:latency_ms) as time_to_first_token_ms,
    TRY_TO_NUMBER(feature_json:total_latency_ms) as total_latency_ms,
    TRY_TO_NUMBER(feature_json:cost_usd, 6) as cost_usd,
    TRY_TO_NUMBER(feature_json:temperature) as temperature,
    TRY_TO_NUMBER(feature_json:max_tokens) as max_tokens,
    TRY_TO_BOOLEAN(feature_json:stream) as is_streamed,
    
    -- Artifact link
    link as artifact_id,
    
    -- Calculated fields
    COALESCE(
        TRY_TO_NUMBER(feature_json:cost_usd, 6),
        revenue_impact,
        -- Default pricing calculation
        CASE 
            WHEN TRY_TO_VARCHAR(feature_json:model) LIKE '%opus%' THEN 
                (TRY_TO_NUMBER(feature_json:prompt_tokens) * 0.015 + 
                 TRY_TO_NUMBER(feature_json:completion_tokens) * 0.075) / 1000
            WHEN TRY_TO_VARCHAR(feature_json:model) LIKE '%sonnet%' THEN
                (TRY_TO_NUMBER(feature_json:prompt_tokens) * 0.003 + 
                 TRY_TO_NUMBER(feature_json:completion_tokens) * 0.015) / 1000
            WHEN TRY_TO_VARCHAR(feature_json:model) LIKE '%haiku%' THEN
                (TRY_TO_NUMBER(feature_json:prompt_tokens) * 0.00025 + 
                 TRY_TO_NUMBER(feature_json:completion_tokens) * 0.00125) / 1000
            ELSE 0
        END
    ) as estimated_cost_usd,
    
    -- Performance metrics
    CASE 
        WHEN TRY_TO_NUMBER(feature_json:latency_ms) < 300 THEN 'fast'
        WHEN TRY_TO_NUMBER(feature_json:latency_ms) < 1000 THEN 'normal'
        ELSE 'slow'
    END as latency_category
    
FROM CLAUDE_STREAM_V2
WHERE activity IN ('user_asked', 'claude_responded', 'llm_call', 'llm_response');

-- ============================================================================
-- TOOL EVENTS VIEW
-- ============================================================================

CREATE OR REPLACE VIEW VW_TOOL_EVENTS
COMMENT = 'Strongly-typed view of tool execution events'
AS
SELECT 
    -- Core fields
    activity_id,
    ts,
    customer,
    anonymous_customer_id,
    
    -- Parsed tool event fields
    TRY_TO_VARCHAR(feature_json:tool_name) as tool_name,
    TRY_TO_VARCHAR(feature_json:tool_category) as tool_category,
    feature_json:parameters as parameters,
    TRY_TO_BOOLEAN(feature_json:success) as success,
    TRY_TO_NUMBER(feature_json:latency_ms) as latency_ms,
    TRY_TO_VARCHAR(feature_json:error) as error_message,
    TRY_TO_NUMBER(feature_json:result_size) as result_size_bytes,
    TRY_TO_VARCHAR(feature_json:result_type) as result_type,
    
    -- Legacy field mapping
    COALESCE(
        TRY_TO_VARCHAR(feature_json:tool_name),
        feature_1
    ) as tool_name_normalized,
    
    -- Performance classification
    CASE 
        WHEN TRY_TO_NUMBER(feature_json:latency_ms) < 25 THEN 'excellent'
        WHEN TRY_TO_NUMBER(feature_json:latency_ms) < 100 THEN 'good'
        WHEN TRY_TO_NUMBER(feature_json:latency_ms) < 500 THEN 'acceptable'
        ELSE 'poor'
    END as performance_tier,
    
    -- Success rate calculation helper
    CASE 
        WHEN TRY_TO_BOOLEAN(feature_json:success) = TRUE THEN 1
        ELSE 0
    END as success_flag
    
FROM CLAUDE_STREAM_V2
WHERE activity IN ('claude_tool_call', 'tool_call', 'tool_execution');

-- ============================================================================
-- FILE EVENTS VIEW
-- ============================================================================

CREATE OR REPLACE VIEW VW_FILE_EVENTS
COMMENT = 'Strongly-typed view of file operation events'
AS
SELECT 
    -- Core fields
    activity_id,
    ts,
    customer,
    anonymous_customer_id,
    
    -- Parsed file event fields
    TRY_TO_VARCHAR(feature_json:operation) as operation,
    TRY_TO_VARCHAR(feature_json:file_path) as file_path,
    TRY_TO_VARCHAR(feature_json:file_type) as file_type,
    TRY_TO_NUMBER(feature_json:lines_affected) as lines_affected,
    TRY_TO_NUMBER(feature_json:bytes_before) as bytes_before,
    TRY_TO_NUMBER(feature_json:bytes_after) as bytes_after,
    TRY_TO_BOOLEAN(feature_json:success) as success,
    TRY_TO_BOOLEAN(feature_json:git_tracked) as git_tracked,
    TRY_TO_VARCHAR(feature_json:git_branch) as git_branch,
    
    -- File link
    COALESCE(link, CONCAT('file://', TRY_TO_VARCHAR(feature_json:file_path))) as file_link,
    
    -- Calculated fields
    TRY_TO_NUMBER(feature_json:bytes_after) - TRY_TO_NUMBER(feature_json:bytes_before) as bytes_changed,
    CASE 
        WHEN TRY_TO_VARCHAR(feature_json:operation) IN ('create', 'write') THEN 'write'
        WHEN TRY_TO_VARCHAR(feature_json:operation) IN ('read') THEN 'read'
        WHEN TRY_TO_VARCHAR(feature_json:operation) IN ('edit') THEN 'modify'
        WHEN TRY_TO_VARCHAR(feature_json:operation) IN ('delete', 'rename') THEN 'delete'
        ELSE 'other'
    END as operation_category
    
FROM CLAUDE_STREAM_V2
WHERE activity IN ('claude_file_operation', 'file_op', 'file_operation');

-- ============================================================================
-- SESSION EVENTS VIEW
-- ============================================================================

CREATE OR REPLACE VIEW VW_SESSION_EVENTS
COMMENT = 'Strongly-typed view of session lifecycle events'
AS
SELECT 
    -- Core fields
    activity_id,
    ts,
    customer as session_id,
    anonymous_customer_id,
    
    -- Parsed session event fields
    TRY_TO_VARCHAR(feature_json:event_type) as event_type,
    TRY_TO_VARCHAR(feature_json:project_path) as project_path,
    TRY_TO_VARCHAR(feature_json:user) as user,
    TRY_TO_VARCHAR(feature_json:host) as host,
    TRY_TO_VARCHAR(feature_json:cli_version) as cli_version,
    TRY_TO_NUMBER(feature_json:total_activities) as total_activities,
    TRY_TO_NUMBER(feature_json:total_tokens) as total_tokens,
    TRY_TO_NUMBER(feature_json:session_duration_ms) as session_duration_ms,
    
    -- Session status
    CASE 
        WHEN activity = 'claude_session_start' THEN 'started'
        WHEN activity = 'claude_session_end' THEN 'completed'
        WHEN activity = 'claude_context_hydration' THEN 'hydrating'
        ELSE 'active'
    END as session_status,
    
    -- Cost calculation
    COALESCE(
        revenue_impact,
        TRY_TO_NUMBER(feature_json:total_tokens) * 0.000003
    ) as session_cost_usd
    
FROM CLAUDE_STREAM_V2
WHERE activity IN ('claude_session_start', 'claude_session_end', 'session_heartbeat', 'claude_context_hydration');

-- ============================================================================
-- MCP EVENTS VIEW
-- ============================================================================

CREATE OR REPLACE VIEW VW_MCP_EVENTS
COMMENT = 'Strongly-typed view of MCP (Model Context Protocol) events'
AS
SELECT 
    -- Core fields
    activity_id,
    ts,
    customer,
    anonymous_customer_id,
    
    -- Parsed MCP event fields
    TRY_TO_VARCHAR(feature_json:method) as method,
    TRY_TO_BOOLEAN(feature_json:cache_hit) as cache_hit,
    TRY_TO_NUMBER(feature_json:cache_age_ms) as cache_age_ms,
    TRY_TO_NUMBER(feature_json:latency_ms) as latency_ms,
    TRY_TO_BOOLEAN(feature_json:stale) as is_stale_while_revalidate,
    TRY_TO_NUMBER(feature_json:context_size) as context_size_bytes,
    
    -- Performance SLO tracking
    CASE 
        WHEN TRY_TO_NUMBER(feature_json:latency_ms) <= 25 THEN 'within_slo'
        ELSE 'slo_breach'
    END as latency_slo_status,
    
    -- Cache effectiveness
    CASE 
        WHEN TRY_TO_BOOLEAN(feature_json:cache_hit) = TRUE 
             AND TRY_TO_NUMBER(feature_json:cache_age_ms) < 30000 THEN 'fresh_hit'
        WHEN TRY_TO_BOOLEAN(feature_json:cache_hit) = TRUE 
             AND TRY_TO_BOOLEAN(feature_json:stale) = TRUE THEN 'stale_hit'
        WHEN TRY_TO_BOOLEAN(feature_json:cache_hit) = TRUE THEN 'hit'
        ELSE 'miss'
    END as cache_status
    
FROM CLAUDE_STREAM_V2
WHERE activity IN ('mcp_call', 'get_context', 'refresh_context', 'store_artifact');

-- ============================================================================
-- SYSTEM EVENTS VIEW
-- ============================================================================

CREATE OR REPLACE VIEW VW_SYSTEM_EVENTS
COMMENT = 'Strongly-typed view of system monitoring events'
AS
SELECT 
    -- Core fields
    activity_id,
    ts,
    customer,
    
    -- Parsed system event fields
    TRY_TO_VARCHAR(feature_json:event_type) as event_type,
    TRY_TO_VARCHAR(feature_json:severity) as severity,
    TRY_TO_VARCHAR(feature_json:message) as message,
    feature_json:metrics as metrics,
    TRY_TO_VARCHAR(feature_json:action_taken) as action_taken,
    
    -- System health indicator
    CASE 
        WHEN TRY_TO_VARCHAR(feature_json:severity) = 'critical' THEN 'unhealthy'
        WHEN TRY_TO_VARCHAR(feature_json:severity) = 'error' THEN 'degraded'
        WHEN TRY_TO_VARCHAR(feature_json:severity) = 'warning' THEN 'warning'
        ELSE 'healthy'
    END as system_health,
    
    -- Alert priority
    CASE 
        WHEN TRY_TO_VARCHAR(feature_json:event_type) = 'backpressure' 
             AND TRY_TO_VARCHAR(feature_json:severity) IN ('error', 'critical') THEN 1
        WHEN TRY_TO_VARCHAR(feature_json:event_type) = 'schema_drift' THEN 2
        WHEN TRY_TO_VARCHAR(feature_json:severity) = 'critical' THEN 1
        WHEN TRY_TO_VARCHAR(feature_json:severity) = 'error' THEN 2
        WHEN TRY_TO_VARCHAR(feature_json:severity) = 'warning' THEN 3
        ELSE 4
    END as alert_priority
    
FROM CLAUDE_STREAM_V2
WHERE activity IN ('system_backpressure', 'schema_drift_detected', 'queue_rotation', 
                   'artifact_cleanup', 'error_recovery', 'system_event');

-- ============================================================================
-- PRODUCT METRICS VIEW
-- ============================================================================

CREATE OR REPLACE VIEW VW_PRODUCT_METRICS
COMMENT = 'Aggregated product metrics for monitoring and reporting'
AS
WITH hourly_metrics AS (
    SELECT 
        DATE_TRUNC('hour', ts) as hour,
        customer,
        
        -- Activity counts
        COUNT(*) as total_activities,
        COUNT(DISTINCT activity) as unique_activity_types,
        
        -- Performance metrics
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY TRY_TO_NUMBER(feature_json:latency_ms)) as p50_latency_ms,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY TRY_TO_NUMBER(feature_json:latency_ms)) as p95_latency_ms,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY TRY_TO_NUMBER(feature_json:latency_ms)) as p99_latency_ms,
        
        -- Success metrics
        SUM(CASE WHEN TRY_TO_BOOLEAN(feature_json:success) = TRUE THEN 1 ELSE 0 END) as successful_operations,
        SUM(CASE WHEN TRY_TO_BOOLEAN(feature_json:success) = FALSE THEN 1 ELSE 0 END) as failed_operations,
        
        -- Token usage
        SUM(TRY_TO_NUMBER(feature_json:total_tokens)) as total_tokens,
        SUM(TRY_TO_NUMBER(feature_json:prompt_tokens)) as prompt_tokens,
        SUM(TRY_TO_NUMBER(feature_json:completion_tokens)) as completion_tokens,
        
        -- Cost
        SUM(revenue_impact) as total_cost_credits,
        
        -- Provenance tracking
        COUNT(DISTINCT link) as unique_artifacts,
        SUM(CASE WHEN link IS NOT NULL THEN 1 ELSE 0 END) as activities_with_provenance
        
    FROM CLAUDE_STREAM_V2
    WHERE ts > DATEADD('day', -7, CURRENT_TIMESTAMP())
    GROUP BY DATE_TRUNC('hour', ts), customer
)
SELECT 
    hour,
    customer,
    total_activities,
    unique_activity_types,
    
    -- Performance SLOs
    p50_latency_ms,
    p95_latency_ms,
    p99_latency_ms,
    CASE WHEN p95_latency_ms <= 25 THEN 'met' ELSE 'missed' END as mcp_latency_slo,
    
    -- Success rate
    ROUND(successful_operations * 100.0 / NULLIF(successful_operations + failed_operations, 0), 2) as success_rate_pct,
    
    -- Token metrics
    total_tokens,
    prompt_tokens,
    completion_tokens,
    ROUND(total_tokens / NULLIF(total_activities, 0), 2) as avg_tokens_per_activity,
    
    -- Cost metrics
    total_cost_credits,
    ROUND(total_cost_credits * 3, 4) as total_cost_usd,
    
    -- Provenance metrics
    unique_artifacts,
    ROUND(activities_with_provenance * 100.0 / NULLIF(total_activities, 0), 2) as provenance_coverage_pct,
    
    -- Health score (0-100)
    GREATEST(0, LEAST(100,
        (CASE WHEN p95_latency_ms <= 25 THEN 25 ELSE 0 END) +
        (CASE WHEN success_rate_pct >= 95 THEN 25 ELSE success_rate_pct * 0.25 END) +
        (CASE WHEN provenance_coverage_pct >= 98 THEN 25 ELSE provenance_coverage_pct * 0.25 END) +
        25  -- Base score for being operational
    )) as health_score
    
FROM hourly_metrics
ORDER BY hour DESC, customer;

-- ============================================================================
-- GRANTS
-- ============================================================================

GRANT SELECT ON VIEW VW_SQL_EVENTS TO PUBLIC;
GRANT SELECT ON VIEW VW_LLM_EVENTS TO PUBLIC;
GRANT SELECT ON VIEW VW_TOOL_EVENTS TO PUBLIC;
GRANT SELECT ON VIEW VW_FILE_EVENTS TO PUBLIC;
GRANT SELECT ON VIEW VW_SESSION_EVENTS TO PUBLIC;
GRANT SELECT ON VIEW VW_MCP_EVENTS TO PUBLIC;
GRANT SELECT ON VIEW VW_SYSTEM_EVENTS TO PUBLIC;
GRANT SELECT ON VIEW VW_PRODUCT_METRICS TO PUBLIC;

-- ============================================================================
-- MIGRATION COMPLETION
-- ============================================================================

UPDATE ACTIVITY_SCHEMA_VERSION
SET status = 'completed',
    checksum_after = OBJECT_CONSTRUCT(
        'views_created', 8,
        'event_types_supported', 7
    )
WHERE migration_name = '04_typed_views'
  AND status = 'running';

-- Display summary
SELECT 
    'Typed Views Setup Complete' as status,
    (SELECT COUNT(*) FROM information_schema.views 
     WHERE table_schema = 'ACTIVITIES' 
     AND view_name LIKE 'VW_%') as views_created;