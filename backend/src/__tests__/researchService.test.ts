import {
  normalizeResearchProvider,
  resolveResearchModelForProvider,
} from '../services/researchService.js';

describe('researchService model resolution', () => {
  it('forces OpenRouter for slash-delimited model ids', () => {
    expect(
      normalizeResearchProvider('gemini', 'meta-llama/llama-3.3-70b-instruct'),
    ).toBe('openrouter');
  });

  it('forces Gemini for direct Gemini model ids', () => {
    expect(
      normalizeResearchProvider('openrouter', 'gemini-2.5-flash'),
    ).toBe('gemini');
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
