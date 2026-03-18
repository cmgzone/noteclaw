# Update Kiro MCP Configuration for NoteClaw
# This script updates your Kiro MCP config to use the new NoteClaw branding

$configPath = "$env:USERPROFILE\.kiro\settings\mcp.json"

Write-Host "Updating Kiro MCP Configuration..." -ForegroundColor Cyan
Write-Host ""

# Check if config exists
if (-not (Test-Path $configPath)) {
    Write-Host "Kiro MCP config not found at: $configPath" -ForegroundColor Red
    Write-Host "Please create the config file first." -ForegroundColor Yellow
    exit 1
}

# Backup existing config
$backupPath = "$configPath.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Copy-Item $configPath $backupPath
Write-Host "Backup created: $backupPath" -ForegroundColor Green

# Read current config
$config = Get-Content $configPath | ConvertFrom-Json

# Get current working directory
$currentDir = (Get-Location).Path
$mcpPath = Join-Path $currentDir "noteclawmcp\dist\index.js"

# Check if notebookllm server exists
if ($config.mcpServers.PSObject.Properties.Name -contains "notebookllm") {
    Write-Host "Found 'notebookllm' server, updating to 'noteclaw'..." -ForegroundColor Yellow
    
    # Get the old config
    $oldConfig = $config.mcpServers.notebookllm
    
    # Create new config with updated values
    $newConfig = @{
        command = "node"
        args = @($mcpPath)
        env = @{
            BACKEND_URL = "http://localhost:3000"
            CODING_AGENT_API_KEY = "nclaw_your-new-token-here"
        }
        autoApprove = $oldConfig.autoApprove
        disabledTools = $oldConfig.disabledTools
    }
    
    # Remove old server
    $config.mcpServers.PSObject.Properties.Remove("notebookllm")
    
    # Add new server
    $config.mcpServers | Add-Member -MemberType NoteProperty -Name "noteclaw" -Value $newConfig -Force
    
    Write-Host "Server renamed: notebookllm -> noteclaw" -ForegroundColor Green
}
else {
    Write-Host "No 'notebookllm' server found, creating new 'noteclaw' server..." -ForegroundColor Cyan
    
    # Create new config
    $newConfig = @{
        command = "node"
        args = @($mcpPath)
        env = @{
            BACKEND_URL = "http://localhost:3000"
            CODING_AGENT_API_KEY = "nclaw_your-new-token-here"
        }
        autoApprove = @(
            "save_code_with_context",
            "verify_code",
            "analyze_code",
            "get_quota",
            "list_notebooks",
            "search_sources",
            "get_current_time",
            "github_status",
            "github_list_repos",
            "github_get_file",
            "review_code"
        )
    }
    
    # Add new server
    if (-not $config.mcpServers) {
        $config | Add-Member -MemberType NoteProperty -Name "mcpServers" -Value @{} -Force
    }
    $config.mcpServers | Add-Member -MemberType NoteProperty -Name "noteclaw" -Value $newConfig -Force
}

# Save updated config
$config | ConvertTo-Json -Depth 10 | Set-Content $configPath

Write-Host ""
Write-Host "Configuration updated successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host "1. Build the MCP server: cd noteclawmcp && npm run build" -ForegroundColor White
Write-Host "2. Generate a new API token in the NoteClaw app (Settings -> Agent Connections)" -ForegroundColor White
Write-Host "3. Update CODING_AGENT_API_KEY in the config with your new token" -ForegroundColor White
Write-Host "4. Restart Kiro IDE" -ForegroundColor White
Write-Host ""
Write-Host "Config location: $configPath" -ForegroundColor Gray
Write-Host "Backup location: $backupPath" -ForegroundColor Gray
