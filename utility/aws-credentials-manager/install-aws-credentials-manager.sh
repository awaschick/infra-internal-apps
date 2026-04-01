#!/usr/bin/env bash

set -e

echo "🔧 Installing AWS Credentials Manager"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_FILE="${SCRIPT_DIR}/init-aws-credentials.sh"

# Check if source file exists
if [[ ! -f "$SOURCE_FILE" ]]; then
    echo "❌ Error: init-aws-credentials.sh not found at ${SOURCE_FILE}"
    exit 1
fi

# Create .zsh_init directory if it doesn't exist
ZSH_INIT_DIR="$HOME/.zsh_init"
mkdir -p "$ZSH_INIT_DIR"
echo "✅ Created/verified directory: ${ZSH_INIT_DIR}"

# Copy the init script
DEST_FILE="${ZSH_INIT_DIR}/init-aws-credentials.sh"
cp "$SOURCE_FILE" "$DEST_FILE"
chmod +x "$DEST_FILE"
echo "✅ Copied init-aws-credentials.sh to ${DEST_FILE}"

# Check if .zshrc sources .zsh_init scripts
ZSHRC="$HOME/.zshrc"
if [[ -f "$ZSHRC" ]]; then
    if grep -q "\.zsh_init/\*\.sh" "$ZSHRC" || grep -q "source.*\.zsh_init" "$ZSHRC"; then
        echo "✅ .zshrc already configured to source .zsh_init scripts"
    else
        echo ""
        echo "⚠️  Your .zshrc doesn't appear to source .zsh_init scripts."
        echo "   Add this line to your ~/.zshrc:"
        echo ""
        echo "   for file in \$(find ~/.zsh_init/*.sh -type f); do source \"\$file\"; done"
        echo ""
    fi
else
    echo ""
    echo "⚠️  No .zshrc found. Create one and add:"
    echo ""
    echo "   for file in \$(find ~/.zsh_init/*.sh -type f); do source \"\$file\"; done"
    echo ""
fi

# Create .aws/credentials-files directory
AWS_CREDENTIALS_DIR="$HOME/.aws/credentials-files"
mkdir -p "$AWS_CREDENTIALS_DIR"
echo "✅ Created/verified directory: ${AWS_CREDENTIALS_DIR}"

# Check if there's an existing credentials file
AWS_CREDENTIALS_FILE="$HOME/.aws/credentials"
if [[ -f "$AWS_CREDENTIALS_FILE" ]] && [[ ! -L "$AWS_CREDENTIALS_FILE" ]]; then
    echo ""
    echo "⚠️  Found existing ~/.aws/credentials file (not a symlink)."
    echo "   You can:"
    echo "   1. Move it to credentials-files and create a symlink:"
    echo "      mv ~/.aws/credentials ~/.aws/credentials-files/my-default"
    echo "      ln -sf ~/.aws/credentials-files/my-default ~/.aws/credentials"
    echo "   2. Or use 'aws-switch' which will automatically back it up"
    echo ""
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✨ Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Place your AWS credentials files in: ${AWS_CREDENTIALS_DIR}"
echo "  2. Set the active credentials:"
echo "     ln -sf ${AWS_CREDENTIALS_DIR}/your-credentials ~/.aws/credentials"
echo "  3. Restart your terminal or run: source ~/.zshrc"
echo "  4. Use 'aws-switch <credentials-name>' to switch between credentials"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
