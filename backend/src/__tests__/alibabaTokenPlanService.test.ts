import {
  formatAlibabaModelName,
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
});
