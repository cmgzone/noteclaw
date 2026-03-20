/**
 * MCP Package Download Routes
 * Serves the MCP server package for self-hosting
 */

import { Router, Request, Response } from 'express';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';

const router = Router();

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const GITHUB_REPO = process.env.MCP_GITHUB_REPO || 'cmgzone/noteclaw';
const GITHUB_RELEASES_URL = `https://github.com/${GITHUB_REPO}/releases`;
const RAW_INSTALL_PS1_URL =
  `https://raw.githubusercontent.com/${GITHUB_REPO}/HEAD/scripts/install-mcp.ps1`;
const RAW_INSTALL_SH_URL =
  `https://raw.githubusercontent.com/${GITHUB_REPO}/HEAD/scripts/install-mcp.sh`;

// Get the project root - works both in dev (src/routes) and prod (dist/routes)
const getProjectRoot = () => {
  // __dirname is either backend/src/routes or backend/dist/routes
  // Go up 2 levels to get to backend/
  return path.resolve(__dirname, '../..');
};

/**
 * GET /api/mcp/package.tgz
 * Download the MCP server package as a tarball
 */
router.get('/package.tgz', async (req: Request, res: Response) => {
  try {
    const packagePath = path.join(getProjectRoot(), 'mcp-server/dist/index.js');

    if (!fs.existsSync(packagePath)) {
      return res.status(404).json({ error: 'MCP package not found' });
    }

    res.status(200).json({
      message: 'The MCP package is distributed through GitHub Releases.',
      releasesUrl: GITHUB_RELEASES_URL,
      installScripts: {
        windows: RAW_INSTALL_PS1_URL,
        macLinux: RAW_INSTALL_SH_URL,
      },
    });
  } catch (error: any) {
    console.error('MCP package download error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/mcp/index.js
 * Serve the compiled MCP server JavaScript
 */
router.get('/index.js', async (req: Request, res: Response) => {
  try {
    const indexPath = path.join(getProjectRoot(), 'mcp-server/dist/index.js');
    
    if (!fs.existsSync(indexPath)) {
      return res.status(404).json({ error: 'MCP server not found' });
    }

    res.setHeader('Content-Type', 'application/javascript');
    res.sendFile(indexPath);
  } catch (error: any) {
    console.error('MCP index.js error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/mcp/package.json
 * Serve the package.json for the MCP server
 */
router.get('/package.json', async (req: Request, res: Response) => {
  try {
    const packageJsonPath = path.join(getProjectRoot(), 'mcp-server/package.json');
    
    if (!fs.existsSync(packageJsonPath)) {
      return res.status(404).json({ error: 'package.json not found' });
    }

    res.setHeader('Content-Type', 'application/json');
    res.sendFile(packageJsonPath);
  } catch (error: any) {
    console.error('MCP package.json error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/mcp/install.sh
 * Serve an install script for easy setup
 */
router.get('/install.sh', async (req: Request, res: Response) => {
  const backendUrl = process.env.BACKEND_URL || `${req.protocol}://${req.get('host')}`;
  
  const script = `#!/bin/bash
# NoteClaw MCP Server Installer
# Usage: curl -fsSL ${backendUrl}/api/mcp/install.sh | bash

set -euo pipefail

GITHUB_REPO="${GITHUB_REPO}"
BACKEND_URL="${backendUrl}"
MCP_DIR="$HOME/.noteclaw-mcp"
TEMP_ZIP="/tmp/noteclaw-mcp-server.zip"
ASSET_PATTERN='noteclaw-mcp-server-.*\\.zip'

echo "Installing NoteClaw MCP Server from GitHub Releases..."

if ! command -v node >/dev/null 2>&1; then
    echo "Node.js is required to run the NoteClaw MCP Server. Install Node.js 20+ and try again." >&2
    exit 1
fi

echo "Finding latest release..."
RELEASE_INFO="$(curl -fsSL "https://api.github.com/repos/$GITHUB_REPO/releases/latest")"
VERSION="$(printf '%s' "$RELEASE_INFO" | grep -o '"tag_name": *"[^"]*"' | head -1 | sed 's/.*"mcp-v\\([^"]*\\)".*/\\1/')"
DOWNLOAD_URL="$(printf '%s' "$RELEASE_INFO" | grep -o '"browser_download_url": *"[^"]*"' | grep -E "$ASSET_PATTERN" | head -1 | sed 's/.*"\\(https:[^"]*\\)".*/\\1/')"

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

echo ""
echo "NoteClaw MCP Server v$VERSION installed to $MCP_DIR"
echo ""
echo "Add this to your MCP config:"
echo ""
echo '{
  "mcpServers": {
    "noteclaw": {
      "command": "node",
      "args": ["'$MCP_DIR'/index.js"],
      "env": {
        "BACKEND_URL": "${backendUrl}",
        "CODING_AGENT_API_KEY": "YOUR_API_TOKEN_HERE"
      }
    }
  }
}'
echo ""
echo "Get your API token from Settings -> Agent Connections in the app"
`;

  res.setHeader('Content-Type', 'text/plain');
  res.send(script);
});

/**
 * GET /api/mcp/install.ps1
 * Serve a PowerShell install script for Windows
 */
router.get('/install.ps1', async (req: Request, res: Response) => {
  const backendUrl = process.env.BACKEND_URL || `${req.protocol}://${req.get('host')}`;
  
  const script = `# NoteClaw MCP Server Installer for Windows
# Usage: irm ${backendUrl}/api/mcp/install.ps1 | iex

$GitHubRepo = "${GITHUB_REPO}"
$BackendUrl = "${backendUrl}"
$MCP_DIR = "$env:USERPROFILE\\.noteclaw-mcp"
$TempZip = Join-Path $env:TEMP "noteclaw-mcp-server.zip"
$AssetPattern = "noteclaw-mcp-server-*.zip"

Write-Host "Installing NoteClaw MCP Server from GitHub Releases..." -ForegroundColor Cyan

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw "Node.js is required to run the NoteClaw MCP Server. Install Node.js 20+ and try again."
}

Write-Host "Finding latest release..." -ForegroundColor Yellow
$release = Invoke-RestMethod -Uri "https://api.github.com/repos/$GitHubRepo/releases/latest"
$asset = $release.assets | Where-Object { $_.name -like $AssetPattern } | Select-Object -First 1

if (-not $asset) {
    throw "Could not find a release asset matching '$AssetPattern' in $GitHubRepo."
}

$version = ($release.tag_name -replace "^mcp-v", "")
$downloadUrl = $asset.browser_download_url

Write-Host "Downloading NoteClaw MCP Server v$version..." -ForegroundColor Yellow
if (Test-Path $MCP_DIR) {
    Remove-Item -Recurse -Force $MCP_DIR
}
New-Item -ItemType Directory -Force -Path $MCP_DIR | Out-Null
Invoke-WebRequest -Uri $downloadUrl -OutFile $TempZip
Expand-Archive -Path $TempZip -DestinationPath $MCP_DIR -Force
Remove-Item $TempZip -Force

Write-Host ""
Write-Host "NoteClaw MCP Server v$version installed to $MCP_DIR" -ForegroundColor Green
Write-Host ""
Write-Host "Add this to your MCP config:" -ForegroundColor Cyan
Write-Host ""
Write-Host @"
{
  "mcpServers": {
    "noteclaw": {
      "command": "node",
      "args": ["$MCP_DIR\\index.js"],
      "env": {
        "BACKEND_URL": "${backendUrl}",
        "CODING_AGENT_API_KEY": "YOUR_API_TOKEN_HERE"
      }
    }
  }
}
"@
Write-Host ""
Write-Host "Get your API token from Settings -> Agent Connections in the app" -ForegroundColor Yellow
`;

  res.setHeader('Content-Type', 'text/plain');
  res.send(script);
});

/**
 * GET /api/mcp/config
 * Get a ready-to-use MCP config template
 */
router.get('/config', async (req: Request, res: Response) => {
  const backendUrl = process.env.BACKEND_URL || `${req.protocol}://${req.get('host')}`;
  const windowsConfig = {
    mcpServers: {
      noteclaw: {
        command: 'node',
        args: ['%USERPROFILE%\\.noteclaw-mcp\\index.js'],
        env: {
          BACKEND_URL: backendUrl,
          CODING_AGENT_API_KEY: 'YOUR_API_TOKEN_HERE',
        },
      },
    },
  };

  const unixConfig = {
    mcpServers: {
      noteclaw: {
        command: 'node',
        args: ['$HOME/.noteclaw-mcp/index.js'],
        env: {
          BACKEND_URL: backendUrl,
          CODING_AGENT_API_KEY: 'YOUR_API_TOKEN_HERE',
        },
      },
    },
  };

  res.json({
    config: {
      windows: windowsConfig,
      macLinux: unixConfig,
    },
    instructions: {
      windows: `irm ${RAW_INSTALL_PS1_URL} | iex`,
      macLinux: `curl -fsSL ${RAW_INSTALL_SH_URL} | bash`,
      manual: `Download the latest package from ${GITHUB_RELEASES_URL}`,
    },
  });
});

export default router;
