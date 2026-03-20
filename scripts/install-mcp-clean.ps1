# NotebookLLM MCP Server Installer for Windows
# Usage: irm https://raw.githubusercontent.com/cmgzone/notebookllmmcp/main/install.ps1 | iex

$ErrorActionPreference = "Stop"

Write-Host "[*] Installing NotebookLLM MCP Server..." -ForegroundColor Cyan

$GITHUB_REPO = "cmgzone/notebookllmmcp"
$BACKEND_URL = "https://noteclaw.onrender.com"

Write-Host "[*] Finding latest release..." -ForegroundColor Yellow
$version = "1.0.0"
$downloadUrl = "https://raw.githubusercontent.com/$GITHUB_REPO/main/dist/index.js"
$packageUrl = "https://raw.githubusercontent.com/$GITHUB_REPO/main/package.json"

Write-Host "[*] Downloading MCP server..." -ForegroundColor Yellow

$MCP_DIR = "$env:USERPROFILE\.notebookllm-mcp"
if (Test-Path $MCP_DIR) {
    Remove-Item -Recurse -Force $MCP_DIR
}
New-Item -ItemType Directory -Force -Path $MCP_DIR | Out-Null

Invoke-WebRequest -Uri $downloadUrl -OutFile "$MCP_DIR\index.js"
Invoke-WebRequest -Uri $packageUrl -OutFile "$MCP_DIR\package.json"

Write-Host "[*] Installing dependencies..." -ForegroundColor Yellow
Push-Location $MCP_DIR
npm install --production --silent 2>$null
Pop-Location

Write-Host ""
Write-Host "[OK] NotebookLLM MCP Server installed to $MCP_DIR" -ForegroundColor Green
Write-Host ""
Write-Host "Add this to your MCP config:" -ForegroundColor Cyan
Write-Host ""

$configJson = @"
{
  "mcpServers": {
    "notebookllm": {
      "command": "node",
      "args": ["$($MCP_DIR -replace '\\', '/')//index.js"],
      "env": {
        "BACKEND_URL": "$BACKEND_URL",
        "CODING_AGENT_API_KEY": "YOUR_API_TOKEN_HERE"
      }
    }
  }
}
"@

Write-Host $configJson
Write-Host ""
Write-Host "Get your API token from Settings -> Agent Connections in the app" -ForegroundColor Yellow
