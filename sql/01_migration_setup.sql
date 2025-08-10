-- ============================================================================
-- PHASE 1: Zero-Downtime Migration Setup
-- ActivitySchema v2.0 Production Migration
-- ============================================================================

USE DATABASE CLAUDE_LOGS;
USE SCHEMA ACTIVITIES;

-- ============================================================================
-- VERSION TRACKING
-- ============================================================================

-- Create version tracking table for migration history
CREATE TABLE IF NOT EXISTS ACTIVITY_SCHEMA_VERSION (
    version_id INT AUTOINCREMENT,
    git_sha STRING,
    migration_name STRING NOT NULL,
    applied_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    applied_by STRING DEFAULT CURRENT_USER(),
    rollback_sql STRING,
    checksum_before VARIANT,
    checksum_after VARIANT,
    status STRING DEFAULT 'pending', -- pending, running, completed, rolled_back
    CONSTRAINT pk_version_id PRIMARY KEY (version_id)
);

-- Log this migration
INSERT INTO ACTIVITY_SCHEMA_VERSION (
    git_sha,
    migration_name,
    status,
    rollback_sql
) VALUES (
    'v2.0.0',
    '01_migration_setup',
    'running',
    'DROP TABLE IF EXISTS CLAUDE_STREAM_V2; DROP PROCEDURE IF EXISTS DUAL_WRITE_ACTIVITY;'
);

-- ============================================================================
-- NEW PRODUCTION SCHEMA WITH feature_json
-- ============================================================================

CREATE TABLE IF NOT EXISTS CLAUDE_STREAM_V2 (
    activity_id STRING NOT NULL,
    ts TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    activity STRING NOT NULL,
    customer STRING NOT NULL,
    anonymous_customer_id STRING DEFAULT TO_VARCHAR(CURRENT_SESSION()),
    
    -- Legacy columns for backward compatibility during migration
    feature_1 STRING,
    feature_2 STRING,
    feature_3 STRING,
    
    -- NEW: Structured data in VARIANT column
    feature_json VARIANT,
    
    -- Financial and linking
    revenue_impact FLOAT DEFAULT 0,
    link STRING, -- artifact_id or external reference
    
    -- Occurrence tracking
    activity_occurrence INT DEFAULT 1,
    activity_repeated_at TIMESTAMP_NTZ,
    
    -- Metadata
    created_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    schema_version INT DEFAULT 2,
    
    CONSTRAINT pk_activity_id PRIMARY KEY (activity_id),
    CONSTRAINT uk_activity_dedup UNIQUE (activity_id, customer, ts)
) CLUSTER BY (customer, ts);

-- Create index for efficient deduplication
CREATE INDEX IF NOT EXISTS idx_activity_id ON CLAUDE_STREAM_V2 (activity_id);
CREATE INDEX IF NOT EXISTS idx_customer_ts ON CLAUDE_STREAM_V2 (customer, ts);

-- ============================================================================
-- DUAL-WRITE PROCEDURE FOR MIGRATION
-- ============================================================================

CREATE OR REPLACE PROCEDURE DUAL_WRITE_ACTIVITY(
    p_activity_id STRING,
    p_activity STRING,
    p_customer STRING,
    p_feature_json VARIANT,
    p_revenue_impact FLOAT,
    p_link STRING
)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_result STRING;
    v_feature_1 STRING;
    v_feature_2 STRING;
    v_feature_3 STRING;
    v_anonymous_customer_id STRING;
BEGIN
    -- Extract legacy feature columns from JSON for backward compatibility
    v_feature_1 := COALESCE(p_feature_json:feature_1::STRING, p_feature_json:tool_name::STRING, '');
    v_feature_2 := COALESCE(p_feature_json:feature_2::STRING, p_feature_json:parameters::STRING, '');
    v_feature_3 := COALESCE(p_feature_json:feature_3::STRING, p_feature_json:result_type::STRING, '');
    v_anonymous_customer_id := COALESCE(p_feature_json:host::STRING, TO_VARCHAR(CURRENT_SESSION()));
    
    -- Write to OLD table (existing schema)
    INSERT INTO ACTIVITY_STREAM (
        activity_id,
        ts,
        activity,
        customer,
        anonymous_customer_id,
        feature_1,
        feature_2,
        feature_3,
        feature_json,
        revenue_impact,
        link
    ) VALUES (
        p_activity_id,
        CURRENT_TIMESTAMP(),
        p_activity,
        p_customer,
        v_anonymous_customer_id,
        v_feature_1,
        v_feature_2,
        v_feature_3,
        p_feature_json,
        p_revenue_impact,
        p_link
    );
    
    -- Write to NEW table with deduplication via MERGE
    MERGE INTO CLAUDE_STREAM_V2 target
    USING (
        SELECT 
            p_activity_id as activity_id,
            CURRENT_TIMESTAMP() as ts,
            p_activity as activity,
            p_customer as customer,
            v_anonymous_customer_id as anonymous_customer_id,
            v_feature_1 as feature_1,
            v_feature_2 as feature_2,
            v_feature_3 as feature_3,
            p_feature_json as feature_json,
            p_revenue_impact as revenue_impact,
            p_link as link
    ) source
    ON target.activity_id = source.activity_id
    WHEN NOT MATCHED THEN
        INSERT (
            activity_id, ts, activity, customer, anonymous_customer_id,
            feature_1, feature_2, feature_3, feature_json,
            revenue_impact, link
        ) VALUES (
            source.activity_id, source.ts, source.activity, 
            source.customer, source.anonymous_customer_id,
            source.feature_1, source.feature_2, source.feature_3, 
            source.feature_json, source.revenue_impact, source.link
        );
    
    RETURN 'Dual-write completed for activity_id: ' || p_activity_id;
END;
$$;

-- ============================================================================
-- MIGRATION VALIDATION PROCEDURES
-- ============================================================================

CREATE OR REPLACE PROCEDURE VALIDATE_MIGRATION()
RETURNS TABLE (
    check_name STRING,
    old_table_value VARIANT,
    new_table_value VARIANT,
    match_status STRING
)
LANGUAGE SQL
AS
$$
DECLARE
    res RESULTSET;
BEGIN
    res := (
        WITH validation_checks AS (
            -- Row count check
            SELECT 
                'row_count' as check_name,
                (SELECT COUNT(*) FROM ACTIVITY_STREAM) as old_value,
                (SELECT COUNT(*) FROM CLAUDE_STREAM_V2) as new_value
            UNION ALL
            -- Min timestamp check
            SELECT 
                'min_timestamp' as check_name,
                (SELECT MIN(ts) FROM ACTIVITY_STREAM) as old_value,
                (SELECT MIN(ts) FROM CLAUDE_STREAM_V2) as new_value
            UNION ALL
            -- Max timestamp check
            SELECT 
                'max_timestamp' as check_name,
                (SELECT MAX(ts) FROM ACTIVITY_STREAM) as old_value,
                (SELECT MAX(ts) FROM CLAUDE_STREAM_V2) as new_value
            UNION ALL
            -- 1% sample hash check
            SELECT 
                'sample_hash' as check_name,
                (SELECT MD5(LISTAGG(activity_id, ',') WITHIN GROUP (ORDER BY activity_id)) 
                 FROM (SELECT activity_id FROM ACTIVITY_STREAM SAMPLE (1) ORDER BY activity_id LIMIT 100)) as old_value,
                (SELECT MD5(LISTAGG(activity_id, ',') WITHIN GROUP (ORDER BY activity_id)) 
                 FROM (SELECT activity_id FROM CLAUDE_STREAM_V2 SAMPLE (1) ORDER BY activity_id LIMIT 100)) as new_value
        )
        SELECT 
            check_name,
            old_value as old_table_value,
            new_value as new_table_value,
            CASE 
                WHEN old_value = new_value THEN 'MATCH'
                WHEN old_value IS NULL OR new_value IS NULL THEN 'NULL_VALUE'
                ELSE 'MISMATCH'
            END as match_status
        FROM validation_checks
    );
    
    RETURN TABLE(res);
END;
$$;

-- ============================================================================
-- BACKFILL PROCEDURE
-- ============================================================================

CREATE OR REPLACE PROCEDURE BACKFILL_TO_V2(
    p_start_date DATE DEFAULT NULL,
    p_end_date DATE DEFAULT NULL
)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    v_rows_processed INT;
    v_start_time TIMESTAMP_NTZ;
    v_end_time TIMESTAMP_NTZ;
BEGIN
    v_start_time := CURRENT_TIMESTAMP();
    
    -- Backfill from old table to new with deduplication
    MERGE INTO CLAUDE_STREAM_V2 target
    USING (
        SELECT 
            COALESCE(activity_id, UUID_STRING()) as activity_id,
            ts,
            activity,
            customer,
            anonymous_customer_id,
            feature_1,
            feature_2,
            feature_3,
            feature_json,
            revenue_impact,
            link,
            activity_occurrence,
            activity_repeated_at
        FROM ACTIVITY_STREAM
        WHERE (p_start_date IS NULL OR DATE(ts) >= p_start_date)
          AND (p_end_date IS NULL OR DATE(ts) <= p_end_date)
    ) source
    ON target.activity_id = source.activity_id
    WHEN NOT MATCHED THEN
        INSERT (
            activity_id, ts, activity, customer, anonymous_customer_id,
            feature_1, feature_2, feature_3, feature_json,
            revenue_impact, link, activity_occurrence, activity_repeated_at
        ) VALUES (
            source.activity_id, source.ts, source.activity, 
            source.customer, source.anonymous_customer_id,
            source.feature_1, source.feature_2, source.feature_3, 
            source.feature_json, source.revenue_impact, source.link,
            source.activity_occurrence, source.activity_repeated_at
        );
    
    v_rows_processed := SQLROWCOUNT;
    v_end_time := CURRENT_TIMESTAMP();
    
    -- Log backfill completion
    INSERT INTO ACTIVITY_SCHEMA_VERSION (
        migration_name,
        status,
        checksum_after
    ) VALUES (
        'backfill_to_v2',
        'completed',
        OBJECT_CONSTRUCT(
            'rows_processed', v_rows_processed,
            'duration_seconds', DATEDIFF('second', v_start_time, v_end_time)
        )
    );
    
    RETURN 'Backfill completed: ' || v_rows_processed || ' rows in ' || 
           DATEDIFF('second', v_start_time, v_end_time) || ' seconds';
END;
$$;

-- ============================================================================
-- CUTOVER CONTROL
-- ============================================================================

-- Feature flag table for controlling migration
CREATE TABLE IF NOT EXISTS MIGRATION_FLAGS (
    flag_name STRING PRIMARY KEY,
    flag_value BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    updated_by STRING DEFAULT CURRENT_USER()
);

-- Initialize migration flags
MERGE INTO MIGRATION_FLAGS target
USING (
    SELECT 'dual_write_enabled' as flag_name, TRUE as flag_value
    UNION ALL
    SELECT 'read_from_v2' as flag_name, FALSE as flag_value
) source
ON target.flag_name = source.flag_name
WHEN NOT MATCHED THEN
    INSERT (flag_name, flag_value) 
    VALUES (source.flag_name, source.flag_value);

-- Procedure to toggle migration phase
CREATE OR REPLACE PROCEDURE SET_MIGRATION_FLAG(
    p_flag_name STRING,
    p_flag_value BOOLEAN
)
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
    UPDATE MIGRATION_FLAGS 
    SET flag_value = p_flag_value,
        updated_at = CURRENT_TIMESTAMP(),
        updated_by = CURRENT_USER()
    WHERE flag_name = p_flag_name;
    
    RETURN 'Flag ' || p_flag_name || ' set to ' || p_flag_value;
END;
$$;

-- ============================================================================
-- GRANTS
-- ============================================================================

GRANT SELECT, INSERT ON CLAUDE_STREAM_V2 TO PUBLIC;
GRANT EXECUTE ON PROCEDURE DUAL_WRITE_ACTIVITY TO PUBLIC;
GRANT EXECUTE ON PROCEDURE VALIDATE_MIGRATION TO PUBLIC;
GRANT EXECUTE ON PROCEDURE BACKFILL_TO_V2 TO PUBLIC;
GRANT EXECUTE ON PROCEDURE SET_MIGRATION_FLAG TO PUBLIC;

-- ============================================================================
-- MIGRATION STATUS
-- ============================================================================

-- Update migration status
UPDATE ACTIVITY_SCHEMA_VERSION
SET status = 'completed',
    checksum_after = OBJECT_CONSTRUCT(
        'tables_created', 3,
        'procedures_created', 4,
        'indexes_created', 2
    )
WHERE migration_name = '01_migration_setup'
  AND status = 'running';

-- Display migration summary
SELECT 
    'Migration Setup Complete' as status,
    (SELECT COUNT(*) FROM information_schema.tables 
     WHERE table_schema = 'ACTIVITIES' 
     AND table_name IN ('CLAUDE_STREAM_V2', 'ACTIVITY_SCHEMA_VERSION', 'MIGRATION_FLAGS')) as tables_created,
    (SELECT COUNT(*) FROM information_schema.procedures 
     WHERE procedure_schema = 'ACTIVITIES' 
     AND procedure_name IN ('DUAL_WRITE_ACTIVITY', 'VALIDATE_MIGRATION', 'BACKFILL_TO_V2', 'SET_MIGRATION_FLAG')) as procedures_created;