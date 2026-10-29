import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { and, gt, not, or } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

// Only the 10 national digits are typed; the +1 is fixed. A leading 1 is
// always a country code (US area codes never start with 1), so it is dropped
// whether typed out of habit or pasted as part of "+1 (415) 555-2671".
function nationalDigits(value) {
  return (value || "").replace(/\D/g, "").replace(/^1/, "").slice(0, 10);
}

// 4155552671 -> (415) 555-2671, applied progressively while typing
function formatNational(digits) {
  if (digits.length <= 3) {
    return digits;
  }
  if (digits.length <= 6) {
    return `(${digits.slice(0, 3)}) ${digits.slice(3)}`;
  }
  return `(${digits.slice(0, 3)}) ${digits.slice(3, 6)}-${digits.slice(6)}`;
}

export default class PhoneVerificationBox extends Component {
  @service siteSettings;
  @service currentUser;
  @service dialog;
  @service toasts;

  @tracked loading = true;
  @tracked sendingCode = false;
  @tracked verifyingCode = false;
  @tracked unbinding = false;

  @tracked phoneVerified = false;
  @tracked maskedPhoneNumber = "";
  @tracked verifiedAt = null;
  @tracked inGatekeeperGroup = false;
  @tracked minTrustLevel = 1;
  @tracked currentTrustLevel = 0;

  @tracked inputPhoneNumber = "";
  @tracked inputCode = "";
  @tracked codeSent = false;
  @tracked cooldownSeconds = 0;

  cooldownTimer = null;

  constructor() {
    super(...arguments);
    if (this.isSelf && this.siteSettings.phone_verification_enabled) {
      this.fetchStatus();
    } else {
      this.loading = false;
    }
  }

  willDestroy() {
    super.willDestroy(...arguments);
    if (this.cooldownTimer) {
      clearInterval(this.cooldownTimer);
    }
  }

  get isSelf() {
    if (!this.currentUser) {
      return false;
    }
    if (!this.args.model) {
      return true;
    }
    return this.args.model.id === this.currentUser.id;
  }

  get qualifiesForGatedCategories() {
    return this.phoneVerified && this.currentTrustLevel >= this.minTrustLevel;
  }

  get phoneDigits() {
    return nationalDigits(this.inputPhoneNumber);
  }

  get phoneComplete() {
    return this.phoneDigits.length === 10;
  }

  get fullPhoneNumber() {
    return `+1${this.phoneDigits}`;
  }

  get sendCodeButtonLabel() {
    if (this.cooldownSeconds > 0) {
      return i18n("phone_verification.resend_code_btn", {
        seconds: this.cooldownSeconds,
      });
    }
    return i18n("phone_verification.send_code_btn");
  }

  @action
  async fetchStatus() {
    this.loading = true;
    try {
      const response = await ajax("/phone-verification/status.json");
      this.phoneVerified = response.phone_verified;
      this.maskedPhoneNumber = response.phone_number_masked;
      this.verifiedAt = response.verified_at;
      this.inGatekeeperGroup = response.in_gatekeeper_group;
      this.minTrustLevel = response.min_trust_level;
      this.currentTrustLevel = response.current_trust_level;
    } catch (e) {
      if (e.status !== 404) {
        popupAjaxError(e);
      }
    } finally {
      this.loading = false;
    }
  }

  @action
  async sendCode() {
    if (!this.phoneComplete) {
      return;
    }

    this.sendingCode = true;
    try {
      const res = await ajax("/phone-verification/send-code.json", {
        type: "POST",
        data: { phone_number: this.fullPhoneNumber },
      });
      this.codeSent = true;
      this.startCooldown(res.cooldown_seconds || 60);
      this.toasts.success({
        data: { message: i18n("phone_verification.success_sent") },
      });
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.sendingCode = false;
    }
  }

  @action
  async verifyCode() {
    if (!this.phoneComplete || !this.inputCode) {
      return;
    }

    this.verifyingCode = true;
    try {
      const res = await ajax("/phone-verification/verify-code.json", {
        type: "POST",
        data: { phone_number: this.fullPhoneNumber, code: this.inputCode },
      });
      this.phoneVerified = true;
      this.maskedPhoneNumber = res.phone_number_masked;
      this.codeSent = false;
      this.inputCode = "";
      this.inputPhoneNumber = "";
      await this.fetchStatus();
      this.toasts.success({
        data: { message: i18n("phone_verification.success_verified") },
      });
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.verifyingCode = false;
    }
  }

  @action
  confirmUnbind() {
    this.dialog.confirm({
      message: i18n("phone_verification.unbind_confirm"),
      didConfirm: () => this.unbindPhone(),
    });
  }

  async unbindPhone() {
    this.unbinding = true;
    try {
      await ajax("/phone-verification/unbind.json", { type: "POST" });
      this.phoneVerified = false;
      this.maskedPhoneNumber = "";
      await this.fetchStatus();
      this.toasts.success({
        data: { message: i18n("phone_verification.success_unbound") },
      });
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.unbinding = false;
    }
  }

  @action
  onPhoneInput(event) {
    const formatted = formatNational(nationalDigits(event.target.value));
    this.inputPhoneNumber = formatted;
    // Also write it back directly: when only a non-digit was typed the
    // tracked value doesn't change, so Glimmer wouldn't re-render the input
    event.target.value = formatted;
  }

  @action
  onCodeInput(event) {
    this.inputCode = event.target.value;
  }

  startCooldown(seconds) {
    this.cooldownSeconds = seconds;
    if (this.cooldownTimer) {
      clearInterval(this.cooldownTimer);
    }
    this.cooldownTimer = setInterval(() => {
      this.cooldownSeconds -= 1;
      if (this.cooldownSeconds <= 0) {
        clearInterval(this.cooldownTimer);
      }
    }, 1000);
  }

  <template>
    {{#if (and this.siteSettings.phone_verification_enabled this.isSelf)}}
      <div class="phone-verification-section">
        <div class="phone-verification-header">
          {{dIcon "mobile-screen"}}
          <h3>{{i18n "phone_verification.title"}}</h3>
        </div>

        <p class="phone-verification-description">
          {{i18n "phone_verification.description"}}
        </p>

        {{#if this.loading}}
          <div class="spinner small"></div>
        {{else if this.phoneVerified}}
          <div class="phone-verification-verified">
            <div class="badge-verified">
              {{dIcon "circle-check"}}
              <span>{{i18n
                  "phone_verification.verified_status"
                  phone=this.maskedPhoneNumber
                }}</span>
            </div>

            {{#if this.qualifiesForGatedCategories}}
              <div class="qualification-info qualified">
                {{dIcon "shield-halved"}}
                {{i18n "phone_verification.status_qualifies"}}
              </div>
            {{else}}
              <div class="qualification-info">
                {{dIcon "circle-info"}}
                {{i18n "phone_verification.status_needs_trust_level"}}
              </div>
            {{/if}}

            <div>
              <DButton
                class="btn-danger"
                @action={{this.confirmUnbind}}
                @icon="trash-can"
                @isLoading={{this.unbinding}}
                @label="phone_verification.unbind_btn"
              />
            </div>
          </div>
        {{else}}
          <div class="phone-verification-form">
            <div class="input-group">
              <div class="phone-input">
                <span class="phone-input__prefix">+1</span>
                <input
                  aria-label={{i18n "phone_verification.phone_label"}}
                  autocomplete="tel-national"
                  class="phone-input__number"
                  disabled={{this.sendingCode}}
                  inputmode="numeric"
                  oninput={{this.onPhoneInput}}
                  placeholder={{i18n "phone_verification.phone_placeholder"}}
                  type="tel"
                  value={{this.inputPhoneNumber}}
                />
              </div>
              <DButton
                class="btn-primary"
                @action={{this.sendCode}}
                @disabled={{or
                  (not this.phoneComplete)
                  (gt this.cooldownSeconds 0)
                }}
                @icon="paper-plane"
                @isLoading={{this.sendingCode}}
                @translatedLabel={{this.sendCodeButtonLabel}}
              />
            </div>

            {{#if this.codeSent}}
              <div class="input-group">
                <input
                  aria-label={{i18n "phone_verification.code_label"}}
                  maxlength="6"
                  oninput={{this.onCodeInput}}
                  placeholder={{i18n "phone_verification.code_placeholder"}}
                  type="text"
                  value={{this.inputCode}}
                />
                <DButton
                  class="btn-success"
                  @action={{this.verifyCode}}
                  @disabled={{not this.inputCode}}
                  @icon="check"
                  @isLoading={{this.verifyingCode}}
                  @label="phone_verification.verify_btn"
                />
              </div>
            {{/if}}
          </div>
        {{/if}}
      </div>
    {{/if}}
  </template>
}
