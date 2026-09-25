// ponytail: Amplitude removed, no-op stub preserves ~30 call sites cleanly
export class AnalyticsHelper {
  constructor({ token: analyticsToken } = {}) {
    this.analyticsToken = analyticsToken;
    this.analytics = null;
    this.user = {};
  }

  async init() {}

  identify() {}

  track() {}

  page() {}
}

export default new AnalyticsHelper(window.analyticsConfig);
