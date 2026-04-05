abstract final class AppRoutes {
  // New Markup routes
  static const feed = '/';
  static const search = '/search';
  static const tracking = '/tracking';
  static const trackingDetail = '/tracking/detail';
  static const play = '/play';

  // Kept routes
  static const game = '/game';
  static const unsubscribe = '/unsubscribe';
  static const suggestStore = '/suggest-store';
  static const preferences = '/preferences';

  // Legacy routes (kept for backwards compat during migration)
  static const storeSearch = '/stores';
  static const chart = '/chart';
  static const bundlePlan = '/bundle-plan';
  static const staplesOverview = '/staples';
  static const checkout = '/checkout';
  static const labelJudgement = '/label-judgement';
  static const sharedBundle = '/shared-bundle';
}
