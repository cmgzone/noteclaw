# NotebookLLM MCP Server Installer for Windows
# Usage: irm https://raw.githubusercontent.com/cmgzone/notebookllm/master/scripts/install-mcp.ps1 | iex

$ErrorActionPreference = "Stop"

Write-Host "📦 Installing NotebookLLM MCP Server..." -ForegroundColor Cyan

# Configuration - UPDATE THESE VALUES
$GITHUB_REPO = "cmgzone/notebookllm"
$BACKEND_URL = "https://noteclaw.onrender.com"

# Get latest release
Write-Host "🔍 Finding latest release..." -ForegroundColor Yellow
try {
    $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/$GITHUB_REPO/releases/latest"
    $version = $releases.tag_name -replace "mcp-v", ""
    $downloadUrl = $releases.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1 -ExpandProperty browser_download_url
} catch {
    Write-Host "⚠️  Could not fetch latest release, using fallback..." -ForegroundColor Yellow
    $version = "1.0.0"
    $downloadUrl = "https://github.com/$GITHUB_REPO/releases/latest/download/notebookllm-mcp-$version.zip"
}

Write-Host "📥 Downloading version $version..." -ForegroundColor Yellow

# Create directory
$MCP_DIR = "$env:USERPROFILE\.notebookllm-mcp"
if (Test-Path $MCP_DIR) {
    Remove-Item -Recurse -Force $MCP_DIR
}
New-Item -ItemType Directory -Force -Path $MCP_DIR | Out-Null

# Download and extract
$zipPath = "$env:TEMP\notebookllm-mcp.zip"
Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath
Expand-Archive -Path $zipPath -DestinationPath $MCP_DIR -Force
Remove-Item $zipPath

# Install dependencies
Write-Host "📥 Installing dependencies..." -ForegroundColor Yellow
Push-Location $MCP_DIR
npm install --production --silent 2>$null
Pop-Location

Write-Host ""
Write-Host "✅ NotebookLLM MCP Server v$version installed to $MCP_DIR" -ForegroundColor Green
Write-Host ""
Write-Host "📝 Add this to your MCP config (e.g., ~/.kiro/settings/mcp.json):" -ForegroundColor Cyan
Write-Host ""

$config = @"
{
  "mcpServers": {
    "notebookllm": {
      "command": "node",
      "args": ["$($MCP_DIR -replace '\\', '\\')\\index.js"],
      "env": {
        "BACKEND_URL": "$BACKEND_URL",
        "CODING_AGENT_API_KEY": "YOUR_API_TOKEN_HERE"
      }
    }
  }
}
"@

Write-Host $config -ForegroundColor White
Write-Host ""
Write-Host "🔑 Get your API token from Settings → Agent Connections in the app" -ForegroundColor Yellow
Write-Host ""
