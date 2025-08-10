#!/bin/bash
# Test script to find your working Snowflake URL

echo "Testing Snowflake URLs for your account..."
echo "Account Identifier: yshmxno-fbc56289"
echo "Region: us-east-1"
echo ""

# Test query
QUERY="SELECT 1 AS test"
ENCODED=$(echo "$QUERY" | python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip()))")

echo "Please try these URLs in order:"
echo ""
echo "1. Classic Console (known to work):"
echo "   https://yshmxno-fbc56289.snowflakecomputing.com/console"
echo ""
echo "2. Classic with query:"
echo "   https://yshmxno-fbc56289.snowflakecomputing.com/console#/worksheet?query=${ENCODED}"
echo ""
echo "3. Modern Snowsight variations:"
echo "   a) https://app.snowflake.com/us-east-1/yshmxno-fbc56289/worksheets"
echo "   b) https://app.snowflake.com/yshmxno-fbc56289/worksheets"
echo "   c) https://app.snowflake.com/#account=yshmxno-fbc56289&worksheet"
echo ""
echo "4. With encoded query:"
echo "   https://app.snowflake.com/us-east-1/yshmxno-fbc56289/worksheets?query=${ENCODED}"
echo ""
echo "Please let me know which URL works and I'll update the cq script accordingly!"