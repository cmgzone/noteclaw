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
const RAW_MCP_CJS_URL =
  `https://raw.githubusercontent.com/${GITHUB_REPO}/HEAD/backend/mcp-server/github-install/index.cjs`;
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
    const packagePath = path.join(getProjectRoot(), 'mcp-server/github-install/index.cjs');

    if (!fs.existsSync(packagePath)) {
      return res.status(404).json({ error: 'MCP package not found' });
    }

    res.status(200).json({
      message: 'The MCP package is distributed directly from the GitHub repository.',
      runtimeUrl: RAW_MCP_CJS_URL,
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
 * Legacy alias for the standalone MCP server bundle
 */
router.get('/index.js', async (req: Request, res: Response) => {
  try {
    const indexPath = path.join(getProjectRoot(), 'mcp-server/github-install/index.cjs');
    
    if (!fs.existsSync(indexPath)) {
      return res.status(404).json({ error: 'MCP server not found' });
    }

    res.setHeader('Content-Type', 'application/javascript');
    res.sendFile(indexPath);
  } catch (error: any) {
    console.error('MCP index.js alias error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/mcp/index.cjs
 * Serve the standalone MCP server bundle
 */
router.get('/index.cjs', async (req: Request, res: Response) => {
  try {
    const indexPath = path.join(getProjectRoot(), 'mcp-server/github-install/index.cjs');

    if (!fs.existsSync(indexPath)) {
      return res.status(404).json({ error: 'MCP server not found' });
    }

    res.setHeader('Content-Type', 'application/javascript');
    res.sendFile(indexPath);
  } catch (error: any) {
    console.error('MCP index.cjs error:', error);
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
DOWNLOAD_URL="${RAW_MCP_CJS_URL}"
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

echo ""
echo "NoteClaw MCP Server installed to $MCP_DIR"
echo ""
echo "Add this to your MCP config:"
echo ""
echo '{
  "mcpServers": {
    "noteclaw": {
      "command": "node",
      "args": ["'$MCP_DIR'/index.cjs"],
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
$DownloadUrl = "${RAW_MCP_CJS_URL}"
$TargetFile = Join-Path $MCP_DIR "index.cjs"

Write-Host "Installing NoteClaw MCP Server from the GitHub repository..." -ForegroundColor Cyan

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw "Node.js is required to run the NoteClaw MCP Server. Install Node.js 20+ and try again."
}

Write-Host "Downloading standalone MCP runtime from GitHub..." -ForegroundColor Yellow
if (Test-Path $MCP_DIR) {
    Remove-Item -Recurse -Force $MCP_DIR
}
New-Item -ItemType Directory -Force -Path $MCP_DIR | Out-Null

try {
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $TargetFile
} catch {
    throw "Could not download the NoteClaw MCP bundle from $DownloadUrl."
}

Write-Host ""
Write-Host "NoteClaw MCP Server installed to $MCP_DIR" -ForegroundColor Green
Write-Host ""
Write-Host "Add this to your MCP config:" -ForegroundColor Cyan
Write-Host ""
Write-Host @"
{
  "mcpServers": {
    "noteclaw": {
      "command": "node",
      "args": ["$MCP_DIR\\index.cjs"],
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
        args: ['%USERPROFILE%\\.noteclaw-mcp\\index.cjs'],
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
        args: ['$HOME/.noteclaw-mcp/index.cjs'],
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
      manual: `Download the standalone bundle from ${RAW_MCP_CJS_URL}`,
    },
  });
});

export default router;
