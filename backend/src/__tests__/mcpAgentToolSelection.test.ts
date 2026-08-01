import { selectMcpToolsForPrompt } from '../services/mcpAgentService.js';

const tools = [
  'memory_get',
  'memory_put',
  'planning_plans_list',
  'planning_task_create',
  'web_search',
  'deep_research_start',
  'image_generate',
  'video_generate',
  'media_generation_status',
  'github_code_search',
].map((name) => ({
  name,
  description: name,
  inputSchema: { type: 'object', properties: {} },
}));

describe('MCP agent tool selection', () => {
  it('keeps a small read-oriented base catalog for normal chat', () => {
    const selected = selectMcpToolsForPrompt(tools, 'What did we decide yesterday?');
    expect(selected.map((tool) => tool.name)).toEqual(
      expect.arrayContaining(['memory_get', 'planning_plans_list']),
    );
    expect(selected.map((tool) => tool.name)).not.toContain('memory_put');
    expect(selected.map((tool) => tool.name)).not.toContain('video_generate');
  });

  it('adds media tools only when the request needs them', () => {
    const selected = selectMcpToolsForPrompt(
      tools,
      'Generate an image and a short video for this project.',
    );
    expect(selected.map((tool) => tool.name)).toEqual(
      expect.arrayContaining([
        'image_generate',
        'video_generate',
        'media_generation_status',
      ]),
    );
  });

  it('adds live research tools for current-information requests', () => {
    const selected = selectMcpToolsForPrompt(
      tools,
      'Search the latest news and do deep research.',
    );
    expect(selected.map((tool) => tool.name)).toEqual(
      expect.arrayContaining(['web_search', 'deep_research_start']),
    );
  });
});
