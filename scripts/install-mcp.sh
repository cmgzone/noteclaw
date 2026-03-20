#!/bin/bash
# NoteClaw MCP Server Installer for macOS/Linux
# Usage: curl -fsSL https://raw.githubusercontent.com/cmgzone/noteclaw/HEAD/scripts/install-mcp.sh | bash

set -euo pipefail

GITHUB_REPO="cmgzone/noteclaw"
BACKEND_URL="https://noteclaw.onrender.com"
MCP_DIR="$HOME/.noteclaw-mcp"
DOWNLOAD_URL="https://raw.githubusercontent.com/$GITHUB_REPO/HEAD/backend/mcp-server/github-install/index.cjs"
TARGET_FILE="$MCP_DIR/index.cjs"

echo "Installing NoteClaw MCP Server from the GitHub repository..."

if ! command -v node >/dev/null 2>&1; then
    echo "Node.js is required to run the NoteClaw MCP Server. Install Node.js 20+ and try again." >&2
    exit 1
fi

echo "Downloading standalone MCP runtime from GitHub..."
rm -rf "$MCP_DIR"
mkdir -p "$MCP_DIR"
if ! curl -fsSL "$DOWNLOAD_URL" -o "$TARGET_FILE"; then
    echo "Could not download the NoteClaw MCP bundle from $DOWNLOAD_URL." >&2
    exit 1
fi

echo
echo "NoteClaw MCP Server installed to $MCP_DIR"
echo
echo "Add this to your MCP config:"
echo
cat <<EOF
{
  "mcpServers": {
    "noteclaw": {
      "command": "node",
      "args": ["$MCP_DIR/index.cjs"],
      "env": {
        "BACKEND_URL": "$BACKEND_URL",
        "CODING_AGENT_API_KEY": "YOUR_API_TOKEN_HERE"
      }
    }
  }
}
EOF
echo
echo "Get your API token from Settings -> Agent Connections in the NoteClaw app."
