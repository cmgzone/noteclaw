#!/bin/bash
# NoteClaw MCP Server Installer for macOS/Linux
# Usage: curl -fsSL https://raw.githubusercontent.com/cmgzone/noteclaw/HEAD/scripts/install-mcp.sh | bash

set -euo pipefail

GITHUB_REPO="cmgzone/noteclaw"
BACKEND_URL="https://noteclaw.onrender.com"
MCP_DIR="$HOME/.noteclaw-mcp"
TEMP_ZIP="/tmp/noteclaw-mcp-server.zip"
ASSET_PATTERN='noteclaw-mcp-server-.*\.zip'

echo "Installing NoteClaw MCP Server from GitHub Releases..."

if ! command -v node >/dev/null 2>&1; then
    echo "Node.js is required to run the NoteClaw MCP Server. Install Node.js 20+ and try again." >&2
    exit 1
fi

echo "Finding latest release..."
RELEASE_INFO="$(curl -fsSL "https://api.github.com/repos/$GITHUB_REPO/releases/latest")"
VERSION="$(printf '%s' "$RELEASE_INFO" | grep -o '"tag_name": *"[^"]*"' | head -1 | sed 's/.*"mcp-v\([^"]*\)".*/\1/')"
DOWNLOAD_URL="$(printf '%s' "$RELEASE_INFO" | grep -o '"browser_download_url": *"[^"]*"' | grep -E "$ASSET_PATTERN" | head -1 | sed 's/.*"\(https:[^"]*\)".*/\1/')"

if [ -z "$DOWNLOAD_URL" ]; then
    echo "Could not find a GitHub release asset matching noteclaw-mcp-server-*.zip." >&2
    exit 1
fi

echo "Downloading NoteClaw MCP Server v$VERSION..."
rm -rf "$MCP_DIR"
mkdir -p "$MCP_DIR"
curl -fsSL "$DOWNLOAD_URL" -o "$TEMP_ZIP"
unzip -q "$TEMP_ZIP" -d "$MCP_DIR"
rm -f "$TEMP_ZIP"

echo
echo "NoteClaw MCP Server v$VERSION installed to $MCP_DIR"
echo
echo "Add this to your MCP config:"
echo
cat <<EOF
{
  "mcpServers": {
    "noteclaw": {
      "command": "node",
      "args": ["$MCP_DIR/index.js"],
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
