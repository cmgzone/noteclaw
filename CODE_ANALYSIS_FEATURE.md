# Code Analysis for GitHub Sources

When a coding agent adds a GitHub file as a source via the MCP server, the system now automatically analyzes the code to provide deep knowledge that improves fact-checking results.

## How It Works

1. **Automatic Analysis**: When `github_add_as_source` is called, the code is automatically analyzed in the background
2. **AI-Powered Insights**: Uses admin-configured AI models (Gemini or OpenRouter) with automatic fallback
3. **User-Selectable Models**: Users can choose which AI model to use for analysis via the web app
4. **Stored with Source**: Analysis is stored in the database alongside the source
5. **Enhanced Fact-Checking**: The analysis context is used to improve fact-checking accuracy for code sources

## User Settings

Users can configure code analysis settings in the **MCP Dashboard → Settings** tab:

### Settings Available
- **Enable/Disable Analysis**: Toggle automatic code analysis on or off
- **AI Model Selection**: Choose which AI model to use for analysis:
  - **Auto (Recommended)**: Automatically selects the best available model with fallback
  - **Specific Model**: Choose from admin-configured models (Gemini, OpenRouter, etc.)

### Accessing Settings
1. Go to the web app: `https://noteclaw.app/dashboard/mcp`
2. Click the **Settings** tab
3. Configure your preferences
4. Click **Save Settings**

## AI Provider Support

The service supports admin-configured AI models with automatic fallback:

1. **User-Selected Model**: If user has selected a specific model, it's used first
2. **Gemini** (default fallback): Uses `gemini-1.5-flash` model
3. **OpenRouter** (secondary fallback): Uses `meta-llama/llama-3.3-70b-instruct` model
4. **Basic Analysis** (no AI): Falls back to static analysis if no AI is configured

### Admin Configuration
Administrators can configure AI models in the admin panel. Models are stored in the `ai_models` table with:
- `model_id`: The model identifier (e.g., `gemini-1.5-flash`)
- `provider`: Either `gemini` or `openrouter`
- `is_active`: Whether the model is available for use
- `is_premium`: Whether the model requires premium subscription

## Analysis Results Include

### Overall Rating (1-10)
- 9-10: Excellent - Production-ready, well-documented, follows best practices
- 7-8: Good - Solid code with minor improvements possible
- 5-6: Average - Functional but needs refactoring
- 3-4: Below Average - Significant issues, needs work
- 1-2: Poor - Major problems, not recommended for production

### Quality Metrics (each 1-10)
- **Readability**: How easy is the code to read and understand
- **Maintainability**: How easy is it to modify and extend
- **Testability**: How easy is it to write tests for
- **Documentation**: Quality of comments and documentation
- **Error Handling**: Robustness of error handling

### Code Explanation
- **Summary**: What the code does overall
- **Purpose**: One-sentence description of main purpose
- **Key Components**: Functions, classes, interfaces with descriptions

### Architecture Analysis
- Detected architectural patterns (MVC, Repository, etc.)
- Design patterns used
- Separation of concerns notes

### Recommendations
- **Strengths**: What the code does well
- **Improvements**: Areas that could be better
- **Security Notes**: Any security concerns

### Metadata
- **analyzedBy**: Human-readable name of the model used
- **provider**: Which AI provider was used (`gemini`, `openrouter`, or `basic`)
- **modelName**: The specific model name (e.g., "Gemini 1.5 Flash")

## MCP Tools

### `get_source_analysis`
Get the analysis for a source:
```javascript
const analysis = await get_source_analysis({ sourceId: "source-uuid" });
```

### `reanalyze_source`
Re-analyze a source (useful after updates):
```javascript
const analysis = await reanalyze_source({ sourceId: "source-uuid" });
```

## API Endpoints

### GET `/api/github/sources/:sourceId/analysis`
Returns the code analysis for a GitHub source.

### POST `/api/github/sources/:sourceId/reanalyze`
Triggers re-analysis of a GitHub source.

### GET `/api/coding-agent/settings`
Get user's MCP settings (code analysis model preference, enabled status).

### PUT `/api/coding-agent/settings`
Update user's MCP settings:
```json
{
  "codeAnalysisModelId": "gemini-1.5-flash",
  "codeAnalysisEnabled": true
}
```

### GET `/api/coding-agent/models`
List available AI models for code analysis.

## Database Schema

### Sources Table
New columns added to `sources` table:
- `code_analysis` (JSONB): Full analysis result
- `analysis_summary` (TEXT): Human-readable summary for fact-checking
- `analysis_rating` (SMALLINT): Quality rating 1-10
- `analyzed_at` (TIMESTAMPTZ): When analysis was performed

### MCP User Settings Table
New table `mcp_user_settings`:
- `user_id` (TEXT): Reference to users table
- `code_analysis_model_id` (TEXT): Preferred model ID
- `code_analysis_enabled` (BOOLEAN): Whether analysis is enabled

## Running the Migrations

```bash
cd backend

# Run code analysis migration
npx tsx src/scripts/run-code-analysis-migration.ts

# Run MCP user settings migration
npx tsx src/scripts/run-mcp-user-settings-migration.ts
```

## Supported Languages

Analysis is performed for these code file types:
- JavaScript/TypeScript
- Python
- Dart
- Java/Kotlin
- Swift
- Go
- Rust
- C/C++
- C#
- Ruby
- PHP
- Scala
- Groovy
- Lua
- R
- Bash/PowerShell

Non-code files (JSON, YAML, Markdown, etc.) are skipped.

## Integration with Fact-Checking

The `FactCheckService` in Flutter now accepts optional code analysis context:

```dart
final results = await factCheckService.verifyContent(
  content,
  codeAnalysis: analysisResult,
);
```

This allows fact-checking to:
- Verify claims about code quality against the analysis rating
- Verify claims about what the code does against the summary
- Verify security claims against security notes
- Verify best practice claims against improvements
