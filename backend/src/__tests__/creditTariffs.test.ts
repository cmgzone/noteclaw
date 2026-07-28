import {
    CreditCosts,
    getFeatureCreditCost,
} from '../services/creditService.js';

describe('credit tariffs', () => {
    it('charges the documented MCP feature costs', () => {
        expect(getFeatureCreditCost('notebook_chat')).toBe(1);
        expect(getFeatureCreditCost('web_search')).toBe(1);
        expect(getFeatureCreditCost('code_review')).toBe(2);
        expect(getFeatureCreditCost('deep_research')).toBe(5);
        expect(getFeatureCreditCost('deep_research', { depth: 'deep' })).toBe(10);
    });

    it('keeps shared constants aligned with tariff resolution', () => {
        expect(getFeatureCreditCost('notebook_chat')).toBe(
            CreditCosts.notebookChat,
        );
        expect(getFeatureCreditCost('web_search')).toBe(CreditCosts.webSearch);
        expect(getFeatureCreditCost('code_review')).toBe(CreditCosts.codeReview);
    });
});
