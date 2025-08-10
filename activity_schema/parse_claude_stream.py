#!/usr/bin/env python3
"""
Parse Claude Code JSON stream and log activities to Snowflake in real-time.
"""

import json
import sys
import subprocess
import os
from datetime import datetime

# Configuration
ACTIVITY_LOGGER = os.path.expanduser("~/snowflake-activity-schema/activity_schema/log_claude_activity.sh")
SESSION_ID = os.environ.get('CLAUDE_SESSION_ID', f'session-{int(datetime.now().timestamp())}')

def log_to_snowflake(activity_type, *args):
    """Call the shell script to log to Snowflake."""
    try:
        cmd = [ACTIVITY_LOGGER, activity_type] + list(args)
        subprocess.run(cmd, capture_output=True, text=True)
    except Exception as e:
        print(f"Error logging to Snowflake: {e}", file=sys.stderr)

def parse_tool_use(data):
    """Extract tool use information from Claude JSON event."""
    tool_name = data.get('tool', 'unknown')
    parameters = data.get('parameters', {})
    
    # Convert parameters to JSON string
    params_json = json.dumps(parameters) if parameters else '{}'
    
    # Estimate duration and tokens (would need actual tracking in production)
    duration_ms = 100  # Default
    tokens_used = len(json.dumps(data)) // 4  # Rough estimate
    
    return tool_name, params_json, duration_ms, tokens_used

def main():
    """Process Claude Code JSON stream from stdin."""
    print(f"Starting Claude stream parser (session: {SESSION_ID})", file=sys.stderr)
    
    # Log session start
    log_to_snowflake('session_start', os.getcwd())
    
    activity_count = 0
    total_tokens = 0
    start_time = datetime.now()
    
    try:
        for line in sys.stdin:
            # Pass through to stdout
            print(line, end='', flush=True)
            
            # Try to parse as JSON
            try:
                data = json.loads(line.strip())
                
                # Handle different event types
                if data.get('type') == 'tool_use':
                    activity_count += 1
                    tool_name, params_json, duration_ms, tokens_used = parse_tool_use(data)
                    total_tokens += tokens_used
                    
                    # Log tool use
                    log_to_snowflake('tool_call', tool_name, params_json, 'success', 
                                   str(duration_ms), str(tokens_used))
                    
                elif data.get('type') == 'error':
                    # Log errors as failed tool calls
                    error_msg = data.get('message', 'Unknown error')
                    log_to_snowflake('tool_call', 'error', 
                                   json.dumps({'error': error_msg}), 'error', '0', '0')
                
                # Add more event type handlers as needed
                
            except json.JSONDecodeError:
                # Not JSON or malformed, just pass through
                pass
                
    except KeyboardInterrupt:
        print("\nStream parsing interrupted", file=sys.stderr)
    finally:
        # Log session end
        duration_ms = int((datetime.now() - start_time).total_seconds() * 1000)
        log_to_snowflake('session_end', str(activity_count), str(total_tokens), str(duration_ms))
        print(f"Session ended: {activity_count} activities logged", file=sys.stderr)

if __name__ == '__main__':
    main()