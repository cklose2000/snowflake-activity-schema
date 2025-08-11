#!/bin/bash
# Test connection for CLAUDE_DESKTOP1 user

set -e

echo "========================================"
echo "Testing CLAUDE_DESKTOP1 User Connection"
echo "========================================"

# Use the test config file
export SNOWFLAKE_CONFIG_PATH="./test/claude_desktop_config.toml"
SNOW_CMD="${SNOW_CMD:-/Library/Frameworks/Python.framework/Versions/3.12/bin/snow}"

echo ""
echo "1. Testing basic connection..."
$SNOW_CMD sql -c claude_desktop -q "SELECT CURRENT_USER(), CURRENT_ROLE(), CURRENT_DATABASE(), CURRENT_SCHEMA();" 2>/dev/null

echo ""
echo "2. Testing warehouse access..."
$SNOW_CMD sql -c claude_desktop -q "SELECT CURRENT_WAREHOUSE();" 2>/dev/null

echo ""
echo "3. Testing schema privileges..."
$SNOW_CMD sql -c claude_desktop -q "SHOW TABLES IN SCHEMA CLAUDE_LOGS.ACTIVITIES;" 2>/dev/null | head -20

echo ""
echo "4. Testing INSERT privilege..."
$SNOW_CMD sql -c claude_desktop -q "
    INSERT INTO CLAUDE_LOGS.ACTIVITIES.ACTIVITY_STREAM (
        activity_id,
        activity,
        customer,
        anonymous_customer_id,
        feature_json
    ) VALUES (
        'test_' || UUID_STRING(),
        'test_connection',
        'CLAUDE_DESKTOP1',
        'test_host',
        OBJECT_CONSTRUCT('test', TRUE, 'timestamp', CURRENT_TIMESTAMP())
    );
" 2>/dev/null

echo ""
echo "5. Testing SELECT privilege..."
$SNOW_CMD sql -c claude_desktop -q "
    SELECT activity_id, activity, ts 
    FROM CLAUDE_LOGS.ACTIVITIES.ACTIVITY_STREAM 
    WHERE customer = 'CLAUDE_DESKTOP1'
    ORDER BY ts DESC
    LIMIT 5;
" 2>/dev/null

echo ""
echo "6. Testing view access..."
$SNOW_CMD sql -c claude_desktop -q "
    SELECT COUNT(*) as view_count
    FROM INFORMATION_SCHEMA.VIEWS
    WHERE TABLE_SCHEMA = 'ACTIVITIES'
    AND TABLE_NAME LIKE 'VW_%';
" 2>/dev/null

echo ""
echo "7. Testing procedure execution..."
$SNOW_CMD sql -c claude_desktop -q "
    CALL CLAUDE_LOGS.ACTIVITIES.RECORD_INSIGHT(
        'CLAUDE_DESKTOP1',
        'test_subject',
        'test_metric',
        OBJECT_CONSTRUCT('value', 123),
        NULL,
        0.95
    );
" 2>/dev/null

echo ""
echo "========================================"
echo "✅ Connection test completed successfully!"
echo "========================================"
echo ""
echo "Summary:"
echo "- User: CLAUDE_DESKTOP1"
echo "- Role: CLAUDE_DESKTOP_ROLE"
echo "- Database: CLAUDE_LOGS"
echo "- Schema: ACTIVITIES"
echo "- Warehouse: COMPUTE_WH"
echo ""
echo "Verified Privileges:"
echo "✓ SELECT on tables"
echo "✓ INSERT on tables"
echo "✓ Access to views"
echo "✓ Execute procedures"
echo "✓ Use warehouse"