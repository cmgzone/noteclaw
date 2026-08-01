import {
  defaultPlanFeatureAccess,
  normalizePlanFeatureAccess,
  PLAN_FEATURE_KEYS,
} from '../services/planFeatureService.js';

describe('plan feature access', () => {
  it('includes independent image and video generation permissions', () => {
    expect(PLAN_FEATURE_KEYS).toEqual(
      expect.arrayContaining(['image_generation', 'video_generation']),
    );
    expect(defaultPlanFeatureAccess(true)).toMatchObject({
      image_generation: false,
      video_generation: false,
    });
    expect(defaultPlanFeatureAccess(false)).toMatchObject({
      image_generation: true,
      video_generation: true,
    });
  });

  it('backfills new permissions without changing existing plan choices', () => {
    expect(normalizePlanFeatureAccess({ web_search: false }, false)).toMatchObject({
      web_search: false,
      image_generation: true,
      video_generation: true,
    });
    expect(normalizePlanFeatureAccess({ image_generation: true }, true)).toMatchObject({
      memory_bank: true,
      image_generation: true,
      video_generation: false,
    });
  });
});
