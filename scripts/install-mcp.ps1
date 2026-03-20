# NoteClaw MCP Server Installer for Windows
# Usage: irm https://raw.githubusercontent.com/cmgzone/noteclaw/HEAD/scripts/install-mcp.ps1 | iex

$ErrorActionPreference = "Stop"

$GitHubRepo = "cmgzone/noteclaw"
$BackendUrl = "https://noteclaw.onrender.com"
$McpDir = "$env:USERPROFILE\.noteclaw-mcp"
$DownloadUrl = "https://raw.githubusercontent.com/$GitHubRepo/HEAD/backend/mcp-server/github-install/index.cjs"
$TargetFile = Join-Path $McpDir "index.cjs"

Write-Host "Installing NoteClaw MCP Server from the GitHub repository..." -ForegroundColor Cyan

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw "Node.js is required to run the NoteClaw MCP Server. Install Node.js 20+ and try again."
}

Write-Host "Downloading standalone MCP runtime from GitHub..." -ForegroundColor Yellow

if (Test-Path $McpDir) {
    Remove-Item -Recurse -Force $McpDir
}
New-Item -ItemType Directory -Force -Path $McpDir | Out-Null

try {
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $TargetFile
} catch {
    throw "Could not download the NoteClaw MCP bundle from $DownloadUrl. Make sure the file exists on GitHub and try again."
}

Write-Host ""
Write-Host "NoteClaw MCP Server installed to $McpDir" -ForegroundColor Green
Write-Host ""
Write-Host "Add this to your MCP config (for example, .kiro/settings/mcp.json):" -ForegroundColor Cyan
Write-Host ""

$escapedPath = $McpDir -replace '\\', '\\'
$config = @"
{
  "mcpServers": {
    "noteclaw": {
      "command": "node",
      "args": ["$escapedPath\\index.cjs"],
      "env": {
        "BACKEND_URL": "$BackendUrl",
        "CODING_AGENT_API_KEY": "YOUR_API_TOKEN_HERE"
      }
    }
  }
}
"@

Write-Host $config -ForegroundColor White
Write-Host ""
Write-Host "Get your API token from Settings -> Agent Connections in the NoteClaw app." -ForegroundColor Yellow
