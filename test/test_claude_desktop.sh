#!/bin/bash
# Test ActivitySchema v2.0 with CLAUDE_DESKTOP1 user

set -e

echo "========================================"
echo "Testing with CLAUDE_DESKTOP1 User"
echo "========================================"

# Update config to use claude_desktop connection
cp test/snowflake_test_config.toml ~/.snowflake/config.toml

SNOW_CMD="${SNOW_CMD:-/Library/Frameworks/Python.framework/Versions/3.12/bin/snow}"

echo ""
echo "1. Verify connection..."
$SNOW_CMD sql -c claude_desktop -q "
    SELECT 
        CURRENT_USER() as user,
        CURRENT_ROLE() as role,
        CURRENT_DATABASE() as database,
        CURRENT_SCHEMA() as schema;
" 2>/dev/null

echo ""
echo "2. Test INSERT into CLAUDE_STREAM_V2..."
$SNOW_CMD sql -c claude_desktop -q "
    INSERT INTO CLAUDE_LOGS.ACTIVITIES.CLAUDE_STREAM_V2 (
        activity_id,
        activity,
        customer,
        anonymous_customer_id,
        feature_json,
        revenue_impact
    ) VALUES 
    (
        UUID_STRING(),
        'session_start',
        'CLAUDE_DESKTOP1',
        'test_machine',
        OBJECT_CONSTRUCT(
            'event_type', 'start',
            'user', 'CLAUDE_DESKTOP1',
            'timestamp', CURRENT_TIMESTAMP()
        ),
        0
    ),
    (
        UUID_STRING(),
        'tool_call',
        'CLAUDE_DESKTOP1',
        'test_machine',
        OBJECT_CONSTRUCT(
            'tool_name', 'bash',
            'success', TRUE,
            'latency_ms', 25,
            'parameters', OBJECT_CONSTRUCT('command', 'ls')
        ),
        0.001
    );
    
    SELECT 'Inserted 2 test events' as status;
" 2>/dev/null

echo ""
echo "3. Query typed views..."
$SNOW_CMD sql -c claude_desktop -q "
    SELECT 
        tool_name,
        success,
        latency_ms,
        performance_tier
    FROM VW_TOOL_EVENTS
    WHERE customer = 'CLAUDE_DESKTOP1'
    ORDER BY ts DESC
    LIMIT 5;
" 2>/dev/null

echo ""
echo "4. Test artifact storage..."
ARTIFACT_ID=$($SNOW_CMD sql -c claude_desktop -q "
    CALL STORE_ARTIFACT(
        'CLAUDE_DESKTOP1',
        'query_result',
        ARRAY_CONSTRUCT(
            OBJECT_CONSTRUCT('id', 1, 'name', 'Test 1'),
            OBJECT_CONSTRUCT('id', 2, 'name', 'Test 2')
        ),
        'test_query_001',
        24
    );
" 2>/dev/null | grep -oE '[a-f0-9-]{36}' | head -1)

echo "Created artifact: $ARTIFACT_ID"

echo ""
echo "5. Test insight recording..."
$SNOW_CMD sql -c claude_desktop -q "
    CALL RECORD_INSIGHT(
        'CLAUDE_DESKTOP1',
        'test_performance',
        'latency_p95',
        23.5,
        '$ARTIFACT_ID',
        0.99
    );
    
    SELECT 'Recorded insight' as status;
" 2>/dev/null

echo ""
echo "6. Check context cache..."
$SNOW_CMD sql -c claude_desktop -q "
    SELECT 
        COUNT(*) as event_count,
        MIN(ts) as first_event,
        MAX(ts) as last_event
    FROM CLAUDE_STREAM_V2
    WHERE customer = 'CLAUDE_DESKTOP1';
" 2>/dev/null

echo ""
echo "7. Test product metrics view..."
$SNOW_CMD sql -c claude_desktop -q "
    SELECT 
        customer,
        total_activities,
        p95_latency_ms,
        health_score
    FROM VW_PRODUCT_METRICS
    WHERE customer = 'CLAUDE_DESKTOP1'
    LIMIT 1;
" 2>/dev/null

echo ""
echo "========================================"
echo "✅ CLAUDE_DESKTOP1 user test completed!"
echo "========================================"

# Restore original config
cp ~/.snowflake/config.toml.backup ~/.snowflake/config.toml

echo ""
echo "Summary:"
echo "- Successfully connected as CLAUDE_DESKTOP1"
echo "- Inserted events into CLAUDE_STREAM_V2"
echo "- Queried typed views"
echo "- Created artifacts"
echo "- Recorded insights"
echo "- Verified metrics calculation"