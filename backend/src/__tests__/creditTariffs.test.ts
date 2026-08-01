import {
    CreditCosts,
    getDefaultFeatureCreditCost,
} from '../services/creditService.js';

describe('credit tariffs', () => {
    it('charges the documented MCP feature costs', () => {
        expect(getDefaultFeatureCreditCost('notebook_chat')).toBe(1);
        expect(getDefaultFeatureCreditCost('web_search')).toBe(1);
        expect(getDefaultFeatureCreditCost('code_review')).toBe(2);
        expect(getDefaultFeatureCreditCost('deep_research')).toBe(5);
        expect(getDefaultFeatureCreditCost('deep_research', { depth: 'deep' })).toBe(10);
    });

    it('keeps shared constants aligned with tariff resolution', () => {
        expect(getDefaultFeatureCreditCost('notebook_chat')).toBe(
            CreditCosts.notebookChat,
        );
        expect(getDefaultFeatureCreditCost('web_search')).toBe(CreditCosts.webSearch);
        expect(getDefaultFeatureCreditCost('code_review')).toBe(CreditCosts.codeReview);
    });
});
