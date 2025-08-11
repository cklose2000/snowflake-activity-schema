#!/bin/bash
# Run all migration scripts to set up V2 schema

set -e

echo "========================================"
echo "Running ActivitySchema v2.0 Migrations"
echo "========================================"

SNOW_CMD="${SNOW_CMD:-/Library/Frameworks/Python.framework/Versions/3.12/bin/snow}"

# Use admin connection for schema creation
CONNECTION="poc"

echo ""
echo "Running migrations with admin privileges..."
echo "Connection: $CONNECTION"
echo ""

# Run migrations in order
for script in sql/01_migration_setup.sql sql/02_artifacts.sql sql/03_streams_tasks.sql sql/04_typed_views.sql; do
    echo "----------------------------------------"
    echo "Running: $script"
    echo "----------------------------------------"
    
    if $SNOW_CMD sql -c $CONNECTION -f "$script" 2>/dev/null | tail -5; then
        echo "✅ $script completed successfully"
    else
        echo "❌ Error running $script"
        exit 1
    fi
    echo ""
done

echo "========================================"
echo "✅ All migrations completed successfully!"
echo "========================================"

echo ""
echo "Verifying tables created..."
$SNOW_CMD sql -c $CONNECTION -q "
    SELECT TABLE_NAME, ROW_COUNT, BYTES
    FROM INFORMATION_SCHEMA.TABLES 
    WHERE TABLE_SCHEMA = 'ACTIVITIES'
    AND TABLE_NAME IN ('CLAUDE_STREAM_V2', 'ARTIFACTS', 'INSIGHT_ATOMS', 'CONTEXT_CACHE')
    ORDER BY TABLE_NAME;
" 2>/dev/null

echo ""
echo "Verifying views created..."
$SNOW_CMD sql -c $CONNECTION -q "
    SELECT VIEW_NAME
    FROM INFORMATION_SCHEMA.VIEWS
    WHERE TABLE_SCHEMA = 'ACTIVITIES'
    AND VIEW_NAME LIKE 'VW_%'
    ORDER BY VIEW_NAME;
" 2>/dev/null | head -20

echo ""
echo "Granting additional privileges to CLAUDE_DESKTOP_ROLE..."
$SNOW_CMD sql -c $CONNECTION -q "
    -- Grant access to new V2 tables
    GRANT SELECT, INSERT, UPDATE ON TABLE CLAUDE_LOGS.ACTIVITIES.CLAUDE_STREAM_V2 TO ROLE CLAUDE_DESKTOP_ROLE;
    GRANT SELECT, INSERT, UPDATE ON TABLE CLAUDE_LOGS.ACTIVITIES.ARTIFACTS TO ROLE CLAUDE_DESKTOP_ROLE;
    GRANT SELECT, INSERT, UPDATE ON TABLE CLAUDE_LOGS.ACTIVITIES.INSIGHT_ATOMS TO ROLE CLAUDE_DESKTOP_ROLE;
    GRANT SELECT, INSERT, UPDATE ON TABLE CLAUDE_LOGS.ACTIVITIES.CONTEXT_CACHE TO ROLE CLAUDE_DESKTOP_ROLE;
    
    -- Grant access to views
    GRANT SELECT ON ALL VIEWS IN SCHEMA CLAUDE_LOGS.ACTIVITIES TO ROLE CLAUDE_DESKTOP_ROLE;
    
    -- Grant execute on procedures
    GRANT USAGE ON ALL PROCEDURES IN SCHEMA CLAUDE_LOGS.ACTIVITIES TO ROLE CLAUDE_DESKTOP_ROLE;
    
    -- Grant monitor on tasks (for visibility)
    GRANT MONITOR ON ALL TASKS IN SCHEMA CLAUDE_LOGS.ACTIVITIES TO ROLE CLAUDE_DESKTOP_ROLE;
    
    SELECT 'Privileges granted to CLAUDE_DESKTOP_ROLE' as status;
" 2>/dev/null

echo ""
echo "Ready to test with CLAUDE_DESKTOP1 user!"