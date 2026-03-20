/**
 * Run planning mode migration
 * Adds support for spec-driven planning with task management and MCP integration
 * Requirements: 1.1, 3.1, 4.1
 */

import pool from '../config/database.js';

async function runMigration() {
  const client = await pool.connect();
  
  try {
    console.log('🔧 Running planning mode migration...');
    
    await client.query('BEGIN');
    
    // Create plans table
    await client.query(`
      CREATE TABLE IF NOT EXISTS plans (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        title VARCHAR(255) NOT NULL,
        description TEXT,
        status VARCHAR(20) DEFAULT 'draft' CHECK (status IN ('draft', 'active', 'completed', 'archived')),
        is_private BOOLEAN DEFAULT true,
        created_at TIMESTAMPTZ DEFAULT NOW(),
        updated_at TIMESTAMPTZ DEFAULT NOW(),
        completed_at TIMESTAMPTZ
      )
    `);
    console.log('✅ Created plans table');
    
    // Create plan_requirements table
    await client.query(`
      CREATE TABLE IF NOT EXISTS plan_requirements (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        plan_id UUID NOT NULL REFERENCES plans(id) ON DELETE CASCADE,
        title VARCHAR(255) NOT NULL,
        description TEXT,
        ears_pattern VARCHAR(20) CHECK (ears_pattern IN ('ubiquitous', 'event', 'state', 'unwanted', 'optional', 'complex')),
        acceptance_criteria JSONB DEFAULT '[]',
        sort_order INTEGER DEFAULT 0,
        created_at TIMESTAMPTZ DEFAULT NOW()
      )
    `);
    console.log('✅ Created plan_requirements table');
    
    // Create plan_design_notes table
    await client.query(`
      CREATE TABLE IF NOT EXISTS plan_design_notes (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        plan_id UUID NOT NULL REFERENCES plans(id) ON DELETE CASCADE,
        requirement_ids UUID[] DEFAULT '{}',
        content TEXT NOT NULL,
        created_at TIMESTAMPTZ DEFAULT NOW()
      )
    `);
    console.log('✅ Created plan_design_notes table');

    await client.query(`
      CREATE TABLE IF NOT EXISTS plan_design_artifacts (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        plan_id UUID NOT NULL REFERENCES plans(id) ON DELETE CASCADE,
        name VARCHAR(255) NOT NULL,
        artifact_type VARCHAR(30) NOT NULL
          CHECK (artifact_type IN ('prototype', 'design_system', 'screen_set', 'component_library', 'flow')),
        status VARCHAR(20) DEFAULT 'draft'
          CHECK (status IN ('draft', 'ready', 'archived')),
        source VARCHAR(30) DEFAULT 'manual'
          CHECK (source IN ('manual', 'ai_generated', 'imported')),
        schema_version INTEGER DEFAULT 1,
        root_data JSONB DEFAULT '{}',
        metadata JSONB DEFAULT '{}',
        created_at TIMESTAMPTZ DEFAULT NOW(),
        updated_at TIMESTAMPTZ DEFAULT NOW()
      )
    `);
    console.log('✅ Created plan_design_artifacts table');

    await client.query(`
      CREATE TABLE IF NOT EXISTS plan_design_artifact_versions (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        artifact_id UUID NOT NULL REFERENCES plan_design_artifacts(id) ON DELETE CASCADE,
        version_number INTEGER NOT NULL,
        snapshot JSONB DEFAULT '{}',
        change_summary TEXT,
        created_by TEXT,
        created_at TIMESTAMPTZ DEFAULT NOW(),
        UNIQUE (artifact_id, version_number)
      )
    `);
    console.log('✅ Created plan_design_artifact_versions table');

    
    // Create plan_tasks table
    await client.query(`
      CREATE TABLE IF NOT EXISTS plan_tasks (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        plan_id UUID NOT NULL REFERENCES plans(id) ON DELETE CASCADE,
        parent_task_id UUID REFERENCES plan_tasks(id) ON DELETE CASCADE,
        requirement_ids UUID[] DEFAULT '{}',
        title VARCHAR(255) NOT NULL,
        description TEXT,
        status VARCHAR(20) DEFAULT 'not_started' CHECK (status IN ('not_started', 'in_progress', 'paused', 'blocked', 'completed')),
        priority VARCHAR(20) DEFAULT 'medium' CHECK (priority IN ('low', 'medium', 'high', 'critical')),
        assigned_agent_id TEXT,
        time_spent_minutes INTEGER DEFAULT 0,
        blocking_reason TEXT,
        created_at TIMESTAMPTZ DEFAULT NOW(),
        updated_at TIMESTAMPTZ DEFAULT NOW(),
        completed_at TIMESTAMPTZ
      )
    `);
    console.log('✅ Created plan_tasks table');
    
    // Create task_status_history table
    await client.query(`
      CREATE TABLE IF NOT EXISTS task_status_history (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        task_id UUID NOT NULL REFERENCES plan_tasks(id) ON DELETE CASCADE,
        status VARCHAR(20) NOT NULL CHECK (status IN ('not_started', 'in_progress', 'paused', 'blocked', 'completed')),
        changed_by VARCHAR(255) NOT NULL,
        reason TEXT,
        changed_at TIMESTAMPTZ DEFAULT NOW()
      )
    `);
    console.log('✅ Created task_status_history table');
    
    // Create task_agent_outputs table
    await client.query(`
      CREATE TABLE IF NOT EXISTS task_agent_outputs (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        task_id UUID NOT NULL REFERENCES plan_tasks(id) ON DELETE CASCADE,
        agent_session_id TEXT REFERENCES agent_sessions(id) ON DELETE SET NULL,
        agent_name VARCHAR(255),
        output_type VARCHAR(20) NOT NULL CHECK (output_type IN ('comment', 'code', 'file', 'completion')),
        content TEXT NOT NULL,
        metadata JSONB,
        created_at TIMESTAMPTZ DEFAULT NOW()
      )
    `);
    console.log('✅ Created task_agent_outputs table');
    
    // Create plan_agent_access table
    await client.query(`
      CREATE TABLE IF NOT EXISTS plan_agent_access (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        plan_id UUID NOT NULL REFERENCES plans(id) ON DELETE CASCADE,
        agent_session_id TEXT NOT NULL REFERENCES agent_sessions(id) ON DELETE CASCADE,
        agent_name VARCHAR(255),
        permissions VARCHAR(20)[] DEFAULT '{read}',
        granted_at TIMESTAMPTZ DEFAULT NOW(),
        revoked_at TIMESTAMPTZ,
        UNIQUE(plan_id, agent_session_id)
      )
    `);
    console.log('✅ Created plan_agent_access table');

    
    // Create indexes for performance
    console.log('🔧 Creating indexes...');
    
    // Plans indexes
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_plans_user_id ON plans(user_id);
      CREATE INDEX IF NOT EXISTS idx_plans_status ON plans(status);
      CREATE INDEX IF NOT EXISTS idx_plans_user_status ON plans(user_id, status);
      CREATE INDEX IF NOT EXISTS idx_plans_created_at ON plans(created_at DESC);
    `);
    console.log('✅ Created plans indexes');
    
    // Requirements indexes
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_plan_requirements_plan_id ON plan_requirements(plan_id);
      CREATE INDEX IF NOT EXISTS idx_plan_requirements_sort ON plan_requirements(plan_id, sort_order);
    `);
    console.log('✅ Created plan_requirements indexes');
    
    // Design notes indexes
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_plan_design_notes_plan_id ON plan_design_notes(plan_id);
    `);
    console.log('✅ Created plan_design_notes indexes');

    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_plan_design_artifacts_plan_id ON plan_design_artifacts(plan_id);
      CREATE INDEX IF NOT EXISTS idx_plan_design_artifacts_type ON plan_design_artifacts(artifact_type);
      CREATE INDEX IF NOT EXISTS idx_plan_design_artifacts_updated_at ON plan_design_artifacts(updated_at DESC);
      CREATE INDEX IF NOT EXISTS idx_plan_design_artifact_versions_artifact_id ON plan_design_artifact_versions(artifact_id);
      CREATE INDEX IF NOT EXISTS idx_plan_design_artifact_versions_version ON plan_design_artifact_versions(artifact_id, version_number DESC);
    `);
    console.log('✅ Created plan_design_artifact indexes');
    
    // Tasks indexes
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_plan_tasks_plan_id ON plan_tasks(plan_id);
      CREATE INDEX IF NOT EXISTS idx_plan_tasks_status ON plan_tasks(status);
      CREATE INDEX IF NOT EXISTS idx_plan_tasks_parent ON plan_tasks(parent_task_id);
      CREATE INDEX IF NOT EXISTS idx_plan_tasks_plan_status ON plan_tasks(plan_id, status);
      CREATE INDEX IF NOT EXISTS idx_plan_tasks_assigned_agent ON plan_tasks(assigned_agent_id) WHERE assigned_agent_id IS NOT NULL;
    `);
    console.log('✅ Created plan_tasks indexes');
    
    // Status history indexes
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_task_status_history_task_id ON task_status_history(task_id);
      CREATE INDEX IF NOT EXISTS idx_task_status_history_changed_at ON task_status_history(changed_at DESC);
    `);
    console.log('✅ Created task_status_history indexes');
    
    // Agent outputs indexes
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_task_agent_outputs_task_id ON task_agent_outputs(task_id);
      CREATE INDEX IF NOT EXISTS idx_task_agent_outputs_agent_session ON task_agent_outputs(agent_session_id) WHERE agent_session_id IS NOT NULL;
      CREATE INDEX IF NOT EXISTS idx_task_agent_outputs_created_at ON task_agent_outputs(created_at DESC);
    `);
    console.log('✅ Created task_agent_outputs indexes');
    
    // Agent access indexes
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_plan_agent_access_plan_id ON plan_agent_access(plan_id);
      CREATE INDEX IF NOT EXISTS idx_plan_agent_access_agent ON plan_agent_access(agent_session_id);
      CREATE INDEX IF NOT EXISTS idx_plan_agent_access_active ON plan_agent_access(plan_id, agent_session_id) WHERE revoked_at IS NULL;
    `);
    console.log('✅ Created plan_agent_access indexes');
    
    // Create trigger function for updated_at
    await client.query(`
      CREATE OR REPLACE FUNCTION update_planning_updated_at()
      RETURNS TRIGGER AS $$
      BEGIN
        NEW.updated_at = NOW();
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    `);
    console.log('✅ Created update_planning_updated_at function');
    
    // Create triggers for auto-updating updated_at
    await client.query(`
      DROP TRIGGER IF EXISTS trigger_plans_updated_at ON plans;
      CREATE TRIGGER trigger_plans_updated_at
        BEFORE UPDATE ON plans
        FOR EACH ROW
        EXECUTE FUNCTION update_planning_updated_at();
    `);
    console.log('✅ Created trigger for plans.updated_at');
    
    await client.query(`
      DROP TRIGGER IF EXISTS trigger_plan_tasks_updated_at ON plan_tasks;
      CREATE TRIGGER trigger_plan_tasks_updated_at
        BEFORE UPDATE ON plan_tasks
        FOR EACH ROW
        EXECUTE FUNCTION update_planning_updated_at();
    `);
    console.log('✅ Created trigger for plan_tasks.updated_at');

    await client.query(`
      DROP TRIGGER IF EXISTS trigger_plan_design_artifacts_updated_at ON plan_design_artifacts;
      CREATE TRIGGER trigger_plan_design_artifacts_updated_at
        BEFORE UPDATE ON plan_design_artifacts
        FOR EACH ROW
        EXECUTE FUNCTION update_planning_updated_at();
    `);
    console.log('✅ Created trigger for plan_design_artifacts.updated_at');
    
    await client.query('COMMIT');
    console.log('✅ Planning mode migration completed successfully!');
    
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('❌ Migration failed:', error);
    throw error;
  } finally {
    client.release();
    await pool.end();
  }
}

runMigration().catch(console.error);
