-- ============================================================================
-- PHASE 2: Artifacts Table with Content Schema
-- Internal storage for query results with pre-computed samples
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
    '02_artifacts',
    'running',
    'DROP TABLE IF EXISTS ARTIFACTS; DROP TABLE IF EXISTS INSIGHT_ATOMS;'
);

-- ============================================================================
-- ARTIFACTS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS ARTIFACTS (
    -- Primary identification
    artifact_id STRING NOT NULL,
    created_ts TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    
    -- Ownership and access
    customer STRING NOT NULL,
    org_id STRING,
    
    -- Artifact metadata
    artifact_type STRING NOT NULL, -- 'query_result', 'visualization', 'report', 'export'
    artifact_subtype STRING, -- 'csv', 'parquet', 'json', 'chart'
    
    -- Result metadata
    row_count INT,
    column_count INT,
    
    -- Pre-computed sample (max 10 rows, 128KB)
    sample_rows VARIANT,
    
    -- Schema information for efficient rendering
    content_schema VARIANT, -- {columns: [{name, type, nullable, precision}]}
    
    -- Pagination support
    row_group_bytes ARRAY, -- [size_in_bytes] for each row group/page
    total_bytes INT,
    
    -- Storage location for large results
    s3_url STRING,
    s3_bucket STRING,
    s3_key STRING,
    storage_class STRING DEFAULT 'STANDARD', -- STANDARD, INTELLIGENT_TIERING, GLACIER
    
    -- Size and cost tracking
    size_bytes INT,
    storage_cost_usd FLOAT DEFAULT 0,
    
    -- Query provenance
    source_query_id STRING,
    source_query_tag STRING,
    source_warehouse STRING,
    execution_time_ms INT,
    
    -- Additional metadata
    metadata VARIANT, -- Flexible field for additional properties
    
    -- Lifecycle management
    expires_at TIMESTAMP_NTZ,
    is_pinned BOOLEAN DEFAULT FALSE, -- Prevent auto-deletion
    access_count INT DEFAULT 0,
    last_accessed_at TIMESTAMP_NTZ,
    
    -- Versioning
    version INT DEFAULT 1,
    parent_artifact_id STRING, -- For tracking lineage
    
    CONSTRAINT pk_artifact_id PRIMARY KEY (artifact_id),
    CONSTRAINT chk_sample_size CHECK (LENGTH(TO_VARCHAR(sample_rows)) <= 131072) -- 128KB limit
) CLUSTER BY (customer, created_ts);

-- Indexes for efficient lookups
CREATE INDEX IF NOT EXISTS idx_artifact_customer ON ARTIFACTS (customer, created_ts);
CREATE INDEX IF NOT EXISTS idx_artifact_query ON ARTIFACTS (source_query_id);
CREATE INDEX IF NOT EXISTS idx_artifact_expires ON ARTIFACTS (expires_at) WHERE expires_at IS NOT NULL;

-- ============================================================================
-- INSIGHT ATOMS TABLE
-- For tracking discovered metrics and insights
-- ============================================================================

CREATE TABLE IF NOT EXISTS INSIGHT_ATOMS (
    -- Identification
    id STRING DEFAULT UUID_STRING(),
    ts TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    
    -- Ownership
    customer STRING NOT NULL,
    org_id STRING,
    
    -- Insight definition
    subject STRING NOT NULL, -- What entity this insight is about
    metric STRING NOT NULL, -- What metric/KPI
    value VARIANT NOT NULL, -- The actual value (number, string, object)
    
    -- Granularity and scope
    grain STRING, -- 'daily', 'weekly', 'monthly', 'total'
    filter_json VARIANT, -- Filters applied to derive this insight
    
    -- Quality and confidence
    confidence FLOAT DEFAULT 1.0, -- 0-1 confidence score
    quality_score FLOAT, -- Data quality score
    
    -- Provenance
    artifact_id STRING, -- Link to source artifact
    provenance_query_id STRING, -- Original query from QUERY_HISTORY
    derivation_method STRING, -- How this insight was derived
    
    -- Validity
    valid_from TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    valid_until TIMESTAMP_NTZ,
    valid_for INTERVAL DAY TO SECOND DEFAULT INTERVAL '1 DAY',
    is_stale BOOLEAN DEFAULT FALSE,
    
    -- Tracking
    usage_count INT DEFAULT 0,
    last_used_at TIMESTAMP_NTZ,
    
    -- Schema evolution
    schema_version INT DEFAULT 1,
    is_quarantined BOOLEAN DEFAULT FALSE, -- For schema drift handling
    quarantine_reason STRING,
    
    CONSTRAINT pk_insight_id PRIMARY KEY (id),
    CONSTRAINT fk_insight_artifact FOREIGN KEY (artifact_id) REFERENCES ARTIFACTS(artifact_id)
) CLUSTER BY (customer, subject, ts);

-- Indexes for insight lookups
CREATE INDEX IF NOT EXISTS idx_insight_subject ON INSIGHT_ATOMS (subject, metric, ts);
CREATE INDEX IF NOT EXISTS idx_insight_valid ON INSIGHT_ATOMS (valid_until) WHERE is_stale = FALSE;
CREATE INDEX IF NOT EXISTS idx_insight_provenance ON INSIGHT_ATOMS (provenance_query_id);

-- ============================================================================
-- CONTEXT CACHE TABLE
-- For fast context retrieval
-- ============================================================================

CREATE TABLE IF NOT EXISTS CONTEXT_CACHE (
    customer STRING NOT NULL,
    context_type STRING DEFAULT 'default', -- 'default', 'executive', 'analyst', 'engineer'
    context_blob VARIANT NOT NULL,
    updated_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    access_count INT DEFAULT 0,
    last_accessed_at TIMESTAMP_NTZ,
    is_stale BOOLEAN DEFAULT FALSE,
    refresh_requested_at TIMESTAMP_NTZ,
    
    CONSTRAINT pk_context PRIMARY KEY (customer, context_type)
);

-- ============================================================================
-- HELPER PROCEDURES
-- ============================================================================

-- Procedure to store artifact with automatic sampling
CREATE OR REPLACE PROCEDURE STORE_ARTIFACT(
    p_customer STRING,
    p_artifact_type STRING,
    p_query_result VARIANT,
    p_query_id STRING DEFAULT NULL,
    p_expires_hours INT DEFAULT 24
)
RETURNS STRING
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    var artifactId = snowflake.createStatement({
        sqlText: "SELECT UUID_STRING()"
    }).execute().next().getColumnValue(1);
    
    // Extract sample (first 10 rows)
    var rows = JSON.parse(P_QUERY_RESULT);
    var sample = rows.slice(0, 10);
    var sampleSize = JSON.stringify(sample).length;
    
    // Check if sample exceeds 128KB
    if (sampleSize > 131072) {
        // Truncate columns if too large
        sample = sample.map(row => {
            var truncated = {};
            for (var key in row) {
                var value = row[key];
                if (typeof value === 'string' && value.length > 100) {
                    truncated[key] = value.substring(0, 100) + '...';
                } else {
                    truncated[key] = value;
                }
            }
            return truncated;
        });
    }
    
    // Extract schema
    var schema = {
        columns: Object.keys(rows[0] || {}).map(col => ({
            name: col,
            type: typeof rows[0][col],
            nullable: true
        }))
    };
    
    // Calculate row groups for pagination (1000 rows per group)
    var rowGroups = [];
    var groupSize = 1000;
    for (var i = 0; i < rows.length; i += groupSize) {
        var groupEnd = Math.min(i + groupSize, rows.length);
        var groupData = JSON.stringify(rows.slice(i, groupEnd));
        rowGroups.push(groupData.length);
    }
    
    // Determine if we need S3 storage
    var s3Url = null;
    var totalSize = JSON.stringify(rows).length;
    
    if (rows.length > 100 || totalSize > 1048576) { // >100 rows or >1MB
        // Would trigger S3 upload in production
        s3Url = 'https://artifacts.bucket.s3.amazonaws.com/' + artifactId + '.parquet';
    }
    
    // Insert artifact record
    snowflake.execute({
        sqlText: `
            INSERT INTO ARTIFACTS (
                artifact_id,
                customer,
                artifact_type,
                row_count,
                column_count,
                sample_rows,
                content_schema,
                row_group_bytes,
                total_bytes,
                s3_url,
                size_bytes,
                source_query_id,
                expires_at
            ) VALUES (
                ?, ?, ?, ?, ?,
                PARSE_JSON(?),
                PARSE_JSON(?),
                ?,
                ?, ?, ?,
                ?,
                DATEADD('hour', ?, CURRENT_TIMESTAMP())
            )
        `,
        binds: [
            artifactId,
            P_CUSTOMER,
            P_ARTIFACT_TYPE,
            rows.length,
            schema.columns.length,
            JSON.stringify(sample),
            JSON.stringify(schema),
            rowGroups,
            totalSize,
            s3Url,
            totalSize,
            P_QUERY_ID,
            P_EXPIRES_HOURS
        ]
    });
    
    return artifactId;
$$;

-- Procedure to record an insight
CREATE OR REPLACE PROCEDURE RECORD_INSIGHT(
    p_customer STRING,
    p_subject STRING,
    p_metric STRING,
    p_value VARIANT,
    p_artifact_id STRING DEFAULT NULL,
    p_confidence FLOAT DEFAULT 1.0
)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    v_insight_id STRING;
BEGIN
    v_insight_id := UUID_STRING();
    
    INSERT INTO INSIGHT_ATOMS (
        id,
        customer,
        subject,
        metric,
        value,
        artifact_id,
        confidence,
        valid_until
    ) VALUES (
        v_insight_id,
        p_customer,
        p_subject,
        p_metric,
        p_value,
        p_artifact_id,
        p_confidence,
        DATEADD('day', 1, CURRENT_TIMESTAMP())
    );
    
    RETURN v_insight_id;
END;
$$;

-- Procedure to clean expired artifacts
CREATE OR REPLACE PROCEDURE CLEAN_EXPIRED_ARTIFACTS()
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    v_deleted_count INT;
BEGIN
    -- Delete expired, unpinned artifacts
    DELETE FROM ARTIFACTS
    WHERE expires_at < CURRENT_TIMESTAMP()
      AND is_pinned = FALSE
      AND access_count < 2; -- Keep if accessed multiple times
    
    v_deleted_count := SQLROWCOUNT;
    
    -- Mark stale insights
    UPDATE INSIGHT_ATOMS
    SET is_stale = TRUE
    WHERE valid_until < CURRENT_TIMESTAMP()
      AND is_stale = FALSE;
    
    RETURN 'Cleaned ' || v_deleted_count || ' expired artifacts';
END;
$$;

-- ============================================================================
-- SCHEDULED TASKS
-- ============================================================================

-- Task to clean expired artifacts daily
CREATE TASK IF NOT EXISTS CLEAN_ARTIFACTS_TASK
    WAREHOUSE = COMPUTE_XS
    SCHEDULE = 'USING CRON 0 2 * * * America/Los_Angeles' -- 2 AM daily
AS
    CALL CLEAN_EXPIRED_ARTIFACTS();

-- ============================================================================
-- GRANTS
-- ============================================================================

GRANT SELECT, INSERT, UPDATE ON ARTIFACTS TO PUBLIC;
GRANT SELECT, INSERT, UPDATE ON INSIGHT_ATOMS TO PUBLIC;
GRANT SELECT, INSERT, UPDATE ON CONTEXT_CACHE TO PUBLIC;
GRANT EXECUTE ON PROCEDURE STORE_ARTIFACT TO PUBLIC;
GRANT EXECUTE ON PROCEDURE RECORD_INSIGHT TO PUBLIC;
GRANT EXECUTE ON PROCEDURE CLEAN_EXPIRED_ARTIFACTS TO PUBLIC;

-- ============================================================================
-- MIGRATION COMPLETION
-- ============================================================================

UPDATE ACTIVITY_SCHEMA_VERSION
SET status = 'completed',
    checksum_after = OBJECT_CONSTRUCT(
        'tables_created', 3,
        'procedures_created', 3,
        'indexes_created', 5,
        'tasks_created', 1
    )
WHERE migration_name = '02_artifacts'
  AND status = 'running';

-- Display summary
SELECT 
    'Artifacts Setup Complete' as status,
    (SELECT COUNT(*) FROM information_schema.tables 
     WHERE table_schema = 'ACTIVITIES' 
     AND table_name IN ('ARTIFACTS', 'INSIGHT_ATOMS', 'CONTEXT_CACHE')) as tables_created,
    (SELECT COUNT(*) FROM information_schema.procedures 
     WHERE procedure_schema = 'ACTIVITIES' 
     AND procedure_name IN ('STORE_ARTIFACT', 'RECORD_INSIGHT', 'CLEAN_EXPIRED_ARTIFACTS')) as procedures_created;