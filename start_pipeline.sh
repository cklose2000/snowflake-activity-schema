#!/bin/bash
# Start the ActivitySchema v2 pipeline

echo "========================================"
echo "Starting ActivitySchema v2 Pipeline"
echo "========================================"

# Configuration
export QUEUE_DIR=/tmp/claude_queue
export SNOW_CONNECTION=claude_desktop

# Ensure queue directory exists
mkdir -p $QUEUE_DIR
echo "✅ Queue directory: $QUEUE_DIR"

# Check Node.js
if ! command -v node &> /dev/null; then
    echo "❌ Node.js not found. Please install Node.js first."
    exit 1
fi

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
    echo "📦 Installing dependencies..."
    npm install
fi

echo ""
echo "Starting services..."
echo ""

# Start NDJSON queue in background
echo "🔄 Starting NDJSON queue..."
QUEUE_DIR=$QUEUE_DIR node activity_schema/ndjson_queue.js &
QUEUE_PID=$!
echo "   PID: $QUEUE_PID"

# Start uploader in background
echo "📤 Starting Snowpipe uploader..."
QUEUE_DIR=$QUEUE_DIR node activity_schema/snowpipe_uploader.js &
UPLOADER_PID=$!
echo "   PID: $UPLOADER_PID"

echo ""
echo "========================================"
echo "✅ Pipeline started successfully!"
echo "========================================"
echo ""
echo "Queue directory: $QUEUE_DIR"
echo "Queue PID: $QUEUE_PID"
echo "Uploader PID: $UPLOADER_PID"
echo ""
echo "To test:"
echo "  claude-v2 'What is 2+2'"
echo ""
echo "To check logs:"
echo "  snow sql -c poc -q 'SELECT * FROM CLAUDE_STREAM_V2 ORDER BY ts DESC LIMIT 5;'"
echo ""
echo "To stop:"
echo "  kill $QUEUE_PID $UPLOADER_PID"
echo ""

# Keep script running and show logs
echo "Showing logs (Ctrl+C to stop)..."
echo "----------------------------------------"
tail -f $QUEUE_DIR/current.ndjson 2>/dev/null