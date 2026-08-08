-- Migration: Add MCP User Settings
-- Allows users to configure their preferred AI model for code analysis

-- Create mcp_user_settings table
CREATE TABLE IF NOT EXISTS mcp_user_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    -- Code Analysis Settings
    code_analysis_model_id TEXT,  -- The model_id from ai_models table
    code_analysis_enabled BOOLEAN DEFAULT true,
    
    -- Future settings can be added here
    -- e.g., auto_analyze_on_add, analysis_depth, etc.
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(user_id)
);

-- Create index for fast lookups
CREATE INDEX IF NOT EXISTS idx_mcp_user_settings_user_id ON mcp_user_settings(user_id);

-- Add comment
COMMENT ON TABLE mcp_user_settings IS 'User-specific MCP settings including code analysis preferences';
COMMENT ON COLUMN mcp_user_settings.code_analysis_model_id IS 'The AI model to use for code analysis (references ai_models.model_id)';
