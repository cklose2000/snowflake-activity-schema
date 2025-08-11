#!/bin/bash
# Setup claude alias for ActivitySchema v2

echo "Setting up Claude ActivitySchema v2 wrapper..."

# Add to shell configuration
SHELL_CONFIG="$HOME/.zshrc"
if [ "$SHELL" = "/bin/bash" ]; then
    SHELL_CONFIG="$HOME/.bashrc"
fi

# Remove any existing claude functions/aliases
echo "Removing existing claude configurations..."
sed -i.bak '/^alias claude=/d' $SHELL_CONFIG 2>/dev/null
sed -i.bak '/^export.*claude-v2/d' $SHELL_CONFIG 2>/dev/null

# Add new configuration
echo "Adding ActivitySchema v2 configuration..."
cat >> $SHELL_CONFIG << 'EOF'

# ActivitySchema v2 - Claude wrapper
export PATH="$HOME/bin:$PATH"
unfunction claude 2>/dev/null  # Remove any existing function
unalias claude 2>/dev/null     # Remove any existing alias
alias claude='claude-v2'
EOF

echo "✅ Configuration added to $SHELL_CONFIG"
echo ""
echo "To activate now, run:"
echo "  source $SHELL_CONFIG"
echo ""
echo "Or open a new terminal window."
echo ""
echo "Test with:"
echo "  claude 'What is 2+2'"