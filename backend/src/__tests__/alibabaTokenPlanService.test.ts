import {
  formatAlibabaModelName,
  inferAlibabaModelCapabilities,
  parseAlibabaTokenPlanModelIds,
  validateAlibabaTokenPlanApiKey,
} from '../services/alibabaTokenPlanService.js';

describe('alibabaTokenPlanService', () => {
  it('parses, trims, de-duplicates, and sorts model IDs', () => {
    expect(
      parseAlibabaTokenPlanModelIds({
        data: [
          { id: 'qwen-plus' },
          ' qwen-coder-plus ',
          { id: 'qwen-plus' },
          { id: 123 },
          '',
        ],
      }),
    ).toEqual(['qwen-coder-plus', 'qwen-plus']);
  });

  it('rejects non-Token Plan keys', () => {
    expect(validateAlibabaTokenPlanApiKey('sk-sp-example')).toBe(
      'sk-sp-example',
    );
    expect(() => validateAlibabaTokenPlanApiKey('sk-example')).toThrow(
      'must start with sk-sp-',
    );
  });

  it('formats provider IDs for the model picker', () => {
    expect(formatAlibabaModelName('qwen3-coder-plus')).toBe(
      'Qwen3 Coder Plus',
    );
  });

  it('separates text, image, video, and audio models by capability', () => {
    expect(inferAlibabaModelCapabilities('deepseek-v4-pro')).toEqual(['text']);
    expect(inferAlibabaModelCapabilities('qwen-image-2.0')).toEqual(['image']);
    expect(inferAlibabaModelCapabilities('wan2.7-t2v')).toEqual(['video']);
    expect(inferAlibabaModelCapabilities('qwen-audio-3.0')).toEqual(['audio']);
  });
});
