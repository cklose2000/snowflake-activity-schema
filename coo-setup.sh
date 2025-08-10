#!/bin/bash
# COO Setup - One-time setup for executives

echo "🎯 Setting up COO Dashboard for Claude Analytics"
echo "================================================"
echo ""

# 1. Add functions to shell
echo "Step 1: Adding simple commands to your shell..."
if ! grep -q "source ~/snowflake-activity-schema/shell-functions.sh" ~/.zshrc; then
    echo "" >> ~/.zshrc
    echo "# Claude Analytics (added by coo-setup)" >> ~/.zshrc
    echo "source ~/snowflake-activity-schema/shell-functions.sh" >> ~/.zshrc
    echo "✅ Added to ~/.zshrc"
else
    echo "✅ Already configured"
fi

# 2. Create desktop shortcut for dashboard
echo ""
echo "Step 2: Creating desktop shortcuts..."
cat > ~/Desktop/Claude-Dashboard.command << 'EOF'
#!/bin/bash
# Open terminal with dashboard
osascript -e 'tell app "Terminal" to do script "dashboard"'
EOF
chmod +x ~/Desktop/Claude-Dashboard.command
echo "✅ Created 'Claude-Dashboard' on desktop"

# 3. Create Snowflake bookmark
echo ""
echo "Step 3: Your Snowflake Dashboard URL:"
echo "https://yshmxno-fbc56289.snowflakecomputing.com/console#/worksheet"
echo ""
echo "📌 Bookmark this URL as 'Claude Metrics'"

# 4. Test the setup
echo ""
echo "Step 4: Testing your setup..."
echo ""

# Source and test
source ~/snowflake-activity-schema/shell-functions.sh

echo "Testing 'dashboard' command:"
dashboard

echo ""
echo "================================================================"
echo "✅ Setup Complete!"
echo ""
echo "You now have TWO simple tools:"
echo ""
echo "1. Terminal Commands:"
echo "   dashboard    - See your metrics"
echo "   why 'X'      - Ask why something looks strange"
echo "   what 'X'     - Ask what's happening"
echo "   how 'X'      - Ask how many/much"
echo ""
echo "2. Desktop Icon:"
echo "   'Claude-Dashboard' - Double-click to see metrics"
echo ""
echo "Examples:"
echo "   why 'are sessions down today'"
echo "   what 'is driving costs'"
echo "   how 'many users this week'"
echo ""
echo "That's it! No SQL, no complexity."
echo "================================================================"