#!/bin/bash
# Process queued events by marking them ready for upload

QUEUE_DIR="/tmp/claude_queue"
CURRENT_FILE="$QUEUE_DIR/current.ndjson"
READY_FILE="$QUEUE_DIR/.ready"

if [ ! -f "$CURRENT_FILE" ]; then
    echo "No queue file found at $CURRENT_FILE"
    exit 0
fi

# Rotate current file
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
ROTATED_FILE="$QUEUE_DIR/queue_${TIMESTAMP}.ndjson"

mv "$CURRENT_FILE" "$ROTATED_FILE"
echo "Rotated queue to: $ROTATED_FILE"

# Mark for processing
echo "{\"file\":\"$ROTATED_FILE\",\"offset\":0,\"marked_at\":\"$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)\"}" >> "$READY_FILE"
echo "Marked for processing in: $READY_FILE"

# Count events
EVENT_COUNT=$(wc -l < "$ROTATED_FILE")
echo "Events in queue: $EVENT_COUNT"