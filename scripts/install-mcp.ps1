# NoteClaw MCP Server Installer for Windows
# Usage: irm https://raw.githubusercontent.com/cmgzone/noteclaw/HEAD/scripts/install-mcp.ps1 | iex

$ErrorActionPreference = "Stop"

$GitHubRepo = "cmgzone/noteclaw"
$BackendUrl = "https://noteclaw.onrender.com"
$McpDir = "$env:USERPROFILE\.noteclaw-mcp"
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

if (Test-Path $McpDir) {
    Remove-Item -Recurse -Force $McpDir
}
New-Item -ItemType Directory -Force -Path $McpDir | Out-Null

Invoke-WebRequest -Uri $downloadUrl -OutFile $TempZip
Expand-Archive -Path $TempZip -DestinationPath $McpDir -Force
Remove-Item $TempZip -Force

Write-Host ""
Write-Host "NoteClaw MCP Server v$version installed to $McpDir" -ForegroundColor Green
Write-Host ""
Write-Host "Add this to your MCP config (for example, .kiro/settings/mcp.json):" -ForegroundColor Cyan
Write-Host ""

$escapedPath = $McpDir -replace '\\', '\\'
$config = @"
{
  "mcpServers": {
    "noteclaw": {
      "command": "node",
      "args": ["$escapedPath\\index.js"],
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
