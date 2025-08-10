# Snowflake ActivitySchema v2.0

Production-ready event tracking system for Claude Code with zero-downtime migration, sub-25ms latency, and full governance.

## 🚀 Quick Start

```bash
# 1. Initialize database schema
snow sql -c poc -f sql/01_migration_setup.sql
snow sql -c poc -f sql/02_artifacts.sql
snow sql -c poc -f sql/03_streams_tasks.sql
snow sql -c poc -f sql/04_typed_views.sql

# 2. Start NDJSON queue (in one terminal)
npm install
npm start

# 3. Start Snowpipe uploader (in another terminal)
npm run uploader

# 4. Test the system
./bin/test-activity-logging.sh
```

## 🏗️ Architecture

### Core Components

1. **NDJSON Queue** - Durable, crash-safe event queue with automatic rotation
2. **Snowpipe Uploader** - Deduplicating batch uploader with backpressure handling
3. **Event-Driven Refresh** - Snowflake Streams + Tasks for <5s context updates
4. **Typed Views** - Strongly-typed views parsing feature_json VARIANT
5. **Governance Layer** - Row access policies, PII masking, retention rules

### Performance SLOs

- **MCP Latency**: P95 < 25ms (from cache)
- **Context Refresh**: P95 < 5s (via streams)
- **First Token**: < 300ms
- **End-to-End**: < 8s for insights with provenance

## 📊 Database Schema

### Tables

- `CLAUDE_STREAM_V2` - Main activity stream with feature_json
- `ARTIFACTS` - Query results with pre-computed samples
- `INSIGHT_ATOMS` - Discovered metrics with validity periods
- `CONTEXT_CACHE` - Fast context retrieval with SWR

### Views

- `VW_SQL_EVENTS` - SQL queries with QUERY_HISTORY join
- `VW_LLM_EVENTS` - LLM interactions with token tracking
- `VW_TOOL_EVENTS` - Tool executions with latency metrics
- `VW_PRODUCT_METRICS` - Aggregated metrics with health scores

## 🔄 Zero-Downtime Migration

The system supports zero-downtime migration from v1 to v2:

```sql
-- Enable dual-write (72 hours)
CALL SET_MIGRATION_FLAG('dual_write_enabled', TRUE);

-- Backfill historical data
CALL BACKFILL_TO_V2();

-- Validate migration
CALL VALIDATE_MIGRATION();

-- Cutover to v2
CALL SET_MIGRATION_FLAG('read_from_v2', TRUE);
CALL SET_MIGRATION_FLAG('dual_write_enabled', FALSE);
```

## 🔒 Security & Governance

### Row Access Policies
- Customer-level isolation
- Optional org_id support
- Admin override capability

### Data Retention
- Activities: 180 days
- Artifacts: 90 days
- Legal hold support

### PII Masking
- Automatic detection of sensitive fields
- Role-based unmasking

## 📈 Monitoring

### System Health
```sql
SELECT * FROM VW_PRODUCT_METRICS
WHERE hour > DATEADD('hour', -24, CURRENT_TIMESTAMP())
ORDER BY health_score DESC;
```

### Stream Lag
```sql
SELECT * FROM V_STREAM_LAG;
```

### Task Monitoring
```sql
SELECT * FROM V_TASK_MONITORING
WHERE task_name = 'REFRESH_CONTEXT_TASK';
```

## 🧪 Testing

### Acceptance Criteria
- First token < 300ms ✅
- MCP get_context P95 < 25ms ✅
- Ingestion lag P95 < 5s ✅
- Same-day provenance consistency ✅
- Backpressure auto-degrade ✅

### Run Tests
```bash
npm test
```

## 📦 Deployment

```bash
# Full production deployment
./deploy/production.sh

# Or step-by-step:
# 1. Deploy schema
snow sql -c poc -f sql/01_migration_setup.sql

# 2. Start services
pm2 start ecosystem.config.js

# 3. Enable tasks
snow sql -c poc -q "ALTER TASK REFRESH_CONTEXT_TASK RESUME;"

# 4. Verify health
snow sql -c poc -q "SELECT * FROM VW_PRODUCT_METRICS LIMIT 1;"
```

## 🔧 Configuration

### Environment Variables
```bash
QUEUE_DIR=/var/claude/queue      # Queue directory
SNOW_CONNECTION=poc               # Snowflake connection
BACKPRESSURE_THRESHOLD=120000    # 2 minutes
MAX_QUEUE_SIZE=52428800          # 50MB
```

### Snowflake Connection
```toml
# ~/.snowflake/config.toml
[connections.poc]
account = "your-account"
user = "your-user"
password = "your-password"
warehouse = "COMPUTE_WH"
database = "CLAUDE_LOGS"
schema = "ACTIVITIES"
```

## 📚 Event Schema

All events follow standardized JSON schemas in `schemas/event_schemas.json`:

- `sql_event` - SQL query execution
- `llm_event` - LLM interactions
- `tool_event` - Tool executions
- `file_event` - File operations
- `session_event` - Session lifecycle
- `mcp_event` - MCP protocol calls
- `system_event` - System monitoring

## 🚨 Troubleshooting

### Queue Backpressure
```bash
# Check queue depth
ls -la /var/claude/queue/

# Monitor backpressure events
snow sql -c poc -q "
  SELECT * FROM VW_SYSTEM_EVENTS 
  WHERE event_type = 'backpressure'
  ORDER BY ts DESC LIMIT 10;
"
```

### Schema Drift
```bash
# Check for drift
snow sql -c poc -q "
  SELECT * FROM VW_SYSTEM_EVENTS 
  WHERE event_type = 'schema_drift_detected'
  ORDER BY ts DESC;
"

# View quarantined insights
snow sql -c poc -q "
  SELECT COUNT(*) as quarantined_count
  FROM INSIGHT_ATOMS 
  WHERE is_quarantined = TRUE;
"
```

## 📄 License

MIT

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Run tests: `npm test`
4. Submit a pull request

## 📞 Support

- GitHub Issues: [Report bugs or request features]
- Documentation: See `/docs` directory
- Snowflake Queries: Check `sql/` directory