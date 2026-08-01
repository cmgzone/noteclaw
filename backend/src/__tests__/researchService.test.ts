import {
  normalizeResearchProvider,
  resolveResearchModelForProvider,
} from '../services/researchService.js';

describe('researchService model resolution', () => {
  it('keeps explicit provider metadata authoritative', () => {
    expect(
      normalizeResearchProvider('gemini', 'meta-llama/llama-3.3-70b-instruct'),
    ).toBe('gemini');
  });

  it('keeps explicit OpenRouter routing for its Gemini aliases', () => {
    expect(
      normalizeResearchProvider('openrouter', 'gemini-2.5-flash'),
    ).toBe('openrouter');
  });

  it('preserves Alibaba Token Plan for DeepSeek and Qwen model ids', () => {
    expect(normalizeResearchProvider('alibaba_token_plan', 'deepseek-v4-pro'))
      .toBe('alibaba_token_plan');
    expect(normalizeResearchProvider('alibaba_token_plan', 'qwen3.7-max'))
      .toBe('alibaba_token_plan');
  });

  it('strips OpenRouter-specific Gemini prefixes and tiers for Gemini fallback', () => {
    expect(
      resolveResearchModelForProvider(
        'gemini',
        'google/gemini-2.0-flash-lite-preview-02-05:free',
      ),
    ).toBe('gemini-2.0-flash-lite-preview-02-05');
  });

  it('maps direct Gemini ids to OpenRouter-compatible model ids for fallback', () => {
    expect(
      resolveResearchModelForProvider('openrouter', 'gemini-2.5-flash'),
    ).toBe('google/gemini-2.5-flash');
  });
});
