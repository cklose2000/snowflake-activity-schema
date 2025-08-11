-- Quick setup of V2 tables for CLAUDE_DESKTOP1 testing
-- Run this with CLAUDE_DESKTOP1 user

USE DATABASE CLAUDE_LOGS;
USE SCHEMA ACTIVITIES;

-- Create simplified V2 table if not exists
CREATE TABLE IF NOT EXISTS CLAUDE_STREAM_V2 (
    activity_id STRING DEFAULT UUID_STRING(),
    ts TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    activity STRING NOT NULL,
    customer STRING NOT NULL,
    anonymous_customer_id STRING,
    feature_json VARIANT,
    revenue_impact FLOAT DEFAULT 0,
    link STRING,
    activity_occurrence INT DEFAULT 1,
    activity_repeated_at TIMESTAMP_NTZ,
    PRIMARY KEY (activity_id)
) CLUSTER BY (customer, ts);

-- Create artifacts table
CREATE TABLE IF NOT EXISTS ARTIFACTS (
    artifact_id STRING DEFAULT UUID_STRING(),
    created_ts TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    customer STRING NOT NULL,
    artifact_type STRING,
    row_count INT,
    sample_rows VARIANT,
    content_schema VARIANT,
    s3_url STRING,
    size_bytes INT,
    metadata VARIANT,
    PRIMARY KEY (artifact_id)
);

-- Create insight atoms table
CREATE TABLE IF NOT EXISTS INSIGHT_ATOMS (
    id STRING DEFAULT UUID_STRING(),
    ts TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    customer STRING NOT NULL,
    subject STRING NOT NULL,
    metric STRING NOT NULL,
    value VARIANT NOT NULL,
    confidence FLOAT DEFAULT 1.0,
    artifact_id STRING,
    PRIMARY KEY (id)
);

-- Create context cache
CREATE TABLE IF NOT EXISTS CONTEXT_CACHE (
    customer STRING NOT NULL,
    context_type STRING DEFAULT 'default',
    context_blob VARIANT,
    updated_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (customer, context_type)
);

-- Verify tables created
SELECT 'Tables created:' as status;
SHOW TABLES LIKE '%V2%';
SHOW TABLES LIKE 'ARTIFACT%';
SHOW TABLES LIKE 'INSIGHT%';
SHOW TABLES LIKE 'CONTEXT%';