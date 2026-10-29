import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import getURL from "discourse/lib/get-url";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";

const DISMISS_KEY = "phone_verification_banner_dismissed";

function todayIso() {
  const now = new Date();
  const pad = (n) => String(n).padStart(2, "0");
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
}

export default class PhoneVerificationBanner extends Component {
  @service currentUser;
  @service siteSettings;
  @service keyValueStore;

  // Changing the end date or the text shows the banner again to people who
  // dismissed the previous one
  @tracked
  dismissed = this.keyValueStore.get(DISMISS_KEY) === this.dismissToken;

  get dismissToken() {
    return `${this.siteSettings.phone_verification_banner_until}|${this.siteSettings.phone_verification_banner_text}`;
  }

  get minTrustLevel() {
    return Number(this.siteSettings.phone_verification_min_trust_level);
  }

  get withinDateRange() {
    const until = (this.siteSettings.phone_verification_banner_until || "").trim();
    if (!until) {
      return true;
    }
    // An invalid date hides the banner rather than showing it forever
    if (!/^\d{4}-\d{2}-\d{2}$/.test(until)) {
      return false;
    }
    return todayIso() <= until;
  }

  get shouldShow() {
    const user = this.currentUser;
    return (
      user &&
      this.siteSettings.phone_verification_enabled &&
      this.siteSettings.phone_verification_banner_enabled &&
      !user.phone_verified &&
      !this.dismissed &&
      user.trust_level >= this.minTrustLevel &&
      this.withinDateRange
    );
  }

  get text() {
    return (
      this.siteSettings.phone_verification_banner_text ||
      i18n("phone_verification.banner.default_text", {
        trust_level: this.minTrustLevel,
      })
    );
  }

  get verifyUrl() {
    return getURL("/my/preferences/account");
  }

  @action
  dismiss() {
    this.keyValueStore.set({ key: DISMISS_KEY, value: this.dismissToken });
    this.dismissed = true;
  }

  <template>
    {{#if this.shouldShow}}
      <div class="phone-verification-banner">
        <span class="phone-verification-banner__text">{{this.text}}</span>
        <a
          class="btn btn-primary btn-small phone-verification-banner__verify"
          href={{this.verifyUrl}}
        >{{i18n "phone_verification.banner.verify"}}</a>
        <DButton
          class="btn-transparent phone-verification-banner__dismiss"
          @action={{this.dismiss}}
          @icon="xmark"
          @title="phone_verification.banner.dismiss"
        />
      </div>
    {{/if}}
  </template>
}
