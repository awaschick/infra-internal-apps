#!/usr/bin/env bash

set -e

echo "🔧 Installing Kubernetes Configuration Manager"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_FILE="${SCRIPT_DIR}/init-kubeconfigs.sh"

# Check if source file exists
if [[ ! -f "$SOURCE_FILE" ]]; then
    echo "❌ Error: init-kubeconfigs.sh not found at ${SOURCE_FILE}"
    exit 1
fi

# Create .zsh_init directory if it doesn't exist
ZSH_INIT_DIR="$HOME/.zsh_init"
mkdir -p "$ZSH_INIT_DIR"
echo "✅ Created/verified directory: ${ZSH_INIT_DIR}"

# Copy the init script
DEST_FILE="${ZSH_INIT_DIR}/init-kubeconfigs.sh"
cp "$SOURCE_FILE" "$DEST_FILE"
chmod +x "$DEST_FILE"
echo "✅ Copied init-kubeconfigs.sh to ${DEST_FILE}"

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

# Create .kube/config-files directory
KUBE_CONFIG_DIR="$HOME/.kube/config-files"
mkdir -p "$KUBE_CONFIG_DIR"
echo "✅ Created/verified directory: ${KUBE_CONFIG_DIR}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✨ Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Place your kubectl config files in: ${KUBE_CONFIG_DIR}"
echo "  2. Set the active config:"
echo "     ln -sf ${KUBE_CONFIG_DIR}/your-config.yaml ~/.kube/config.active"
echo "  3. Restart your terminal or run: source ~/.zshrc"
echo "  4. Use 'kubeconfig-switch <config-name>' to switch between configs"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
