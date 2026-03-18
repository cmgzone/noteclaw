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
    const packagePath = path.join(getProjectRoot(), 'mcp-server/dist');
    
    // Check if dist exists
    if (!fs.existsSync(packagePath)) {
      return res.status(404).json({ error: 'MCP package not found' });
    }

    // Create a simple install script response
    res.setHeader('Content-Type', 'application/gzip');
    res.setHeader('Content-Disposition', 'attachment; filename="noteclaw-mcp.tgz"');
    
    // For now, redirect to the raw files approach
    res.status(200).json({
      message: 'Use the install script instead',
      installUrl: `${req.protocol}://${req.get('host')}/api/mcp/install.sh`,
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

set -e

echo "Installing NoteClaw MCP Server..."

# Create directory
MCP_DIR="$HOME/.noteclaw-mcp"
mkdir -p "$MCP_DIR"

# Download the server
echo "Downloading MCP server..."
curl -fsSL "${backendUrl}/api/mcp/index.js" -o "$MCP_DIR/index.js"
curl -fsSL "${backendUrl}/api/mcp/package.json" -o "$MCP_DIR/package.json"

# Install dependencies
echo "Installing dependencies..."
cd "$MCP_DIR"
npm install --production

echo ""
echo "NoteClaw MCP Server installed to $MCP_DIR"
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

Write-Host "Installing NoteClaw MCP Server..." -ForegroundColor Cyan

# Create directory
$MCP_DIR = "$env:USERPROFILE\\.noteclaw-mcp"
New-Item -ItemType Directory -Force -Path $MCP_DIR | Out-Null

# Download the server
Write-Host "Downloading MCP server..." -ForegroundColor Yellow
Invoke-WebRequest -Uri "${backendUrl}/api/mcp/index.js" -OutFile "$MCP_DIR\\index.js"
Invoke-WebRequest -Uri "${backendUrl}/api/mcp/package.json" -OutFile "$MCP_DIR\\package.json"

# Install dependencies
Write-Host "Installing dependencies..." -ForegroundColor Yellow
Push-Location $MCP_DIR
npm install --production
Pop-Location

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
  const mcpDir = process.platform === 'win32' 
    ? '%USERPROFILE%\\.noteclaw-mcp'
    : '$HOME/.noteclaw-mcp';
  
  const config = {
    mcpServers: {
      noteclaw: {
        command: 'node',
        args: [`${mcpDir}/index.js`],
        env: {
          BACKEND_URL: backendUrl,
          CODING_AGENT_API_KEY: 'YOUR_API_TOKEN_HERE',
        },
      },
    },
  };

  res.json({
    config,
    instructions: {
      windows: `irm ${backendUrl}/api/mcp/install.ps1 | iex`,
      macLinux: `curl -fsSL ${backendUrl}/api/mcp/install.sh | bash`,
      manual: `Download index.js from ${backendUrl}/api/mcp/index.js`,
    },
  });
});

export default router;
