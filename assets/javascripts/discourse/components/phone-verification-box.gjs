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
    if (this.isSelf && this.siteSettings.phone_gatekeeper_enabled) {
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

  get sendCodeButtonLabel() {
    if (this.cooldownSeconds > 0) {
      return i18n("phone_gatekeeper.resend_code_btn", {
        seconds: this.cooldownSeconds,
      });
    }
    return i18n("phone_gatekeeper.send_code_btn");
  }

  @action
  async fetchStatus() {
    this.loading = true;
    try {
      const response = await ajax("/phone-gatekeeper/status.json");
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
    if (!this.inputPhoneNumber) {
      return;
    }

    this.sendingCode = true;
    try {
      const res = await ajax("/phone-gatekeeper/send-code.json", {
        type: "POST",
        data: { phone_number: this.inputPhoneNumber },
      });
      this.codeSent = true;
      this.startCooldown(res.cooldown_seconds || 60);
      this.toasts.success({
        data: { message: i18n("phone_gatekeeper.success_sent") },
      });
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.sendingCode = false;
    }
  }

  @action
  async verifyCode() {
    if (!this.inputPhoneNumber || !this.inputCode) {
      return;
    }

    this.verifyingCode = true;
    try {
      const res = await ajax("/phone-gatekeeper/verify-code.json", {
        type: "POST",
        data: { phone_number: this.inputPhoneNumber, code: this.inputCode },
      });
      this.phoneVerified = true;
      this.maskedPhoneNumber = res.phone_number_masked;
      this.codeSent = false;
      this.inputCode = "";
      this.inputPhoneNumber = "";
      await this.fetchStatus();
      this.toasts.success({
        data: { message: i18n("phone_gatekeeper.success_verified") },
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
      message: i18n("phone_gatekeeper.unbind_confirm"),
      didConfirm: () => this.unbindPhone(),
    });
  }

  async unbindPhone() {
    this.unbinding = true;
    try {
      await ajax("/phone-gatekeeper/unbind.json", { type: "POST" });
      this.phoneVerified = false;
      this.maskedPhoneNumber = "";
      await this.fetchStatus();
      this.toasts.success({
        data: { message: i18n("phone_gatekeeper.success_unbound") },
      });
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.unbinding = false;
    }
  }

  @action
  onPhoneInput(event) {
    this.inputPhoneNumber = event.target.value;
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
    {{#if (and this.siteSettings.phone_gatekeeper_enabled this.isSelf)}}
      <div class="phone-gatekeeper-section">
        <div class="phone-gatekeeper-header">
          {{dIcon "mobile-screen"}}
          <h3>{{i18n "phone_gatekeeper.title"}}</h3>
        </div>

        <p class="phone-gatekeeper-description">
          {{i18n "phone_gatekeeper.description"}}
        </p>

        {{#if this.loading}}
          <div class="spinner small"></div>
        {{else if this.phoneVerified}}
          <div class="phone-gatekeeper-verified">
            <div class="badge-verified">
              {{dIcon "circle-check"}}
              <span>{{i18n
                  "phone_gatekeeper.verified_status"
                  phone=this.maskedPhoneNumber
                }}</span>
            </div>

            {{#if this.qualifiesForGatedCategories}}
              <div class="qualification-info qualified">
                {{dIcon "shield-halved"}}
                {{i18n "phone_gatekeeper.status_qualifies"}}
              </div>
            {{else}}
              <div class="qualification-info">
                {{dIcon "circle-info"}}
                {{i18n "phone_gatekeeper.status_needs_trust_level"}}
              </div>
            {{/if}}

            <div>
              <DButton
                class="btn-danger"
                @action={{this.confirmUnbind}}
                @icon="trash-can"
                @isLoading={{this.unbinding}}
                @label="phone_gatekeeper.unbind_btn"
              />
            </div>
          </div>
        {{else}}
          <div class="phone-gatekeeper-form">
            <div class="input-group">
              <input
                aria-label={{i18n "phone_gatekeeper.phone_label"}}
                disabled={{this.sendingCode}}
                oninput={{this.onPhoneInput}}
                placeholder={{i18n "phone_gatekeeper.phone_placeholder"}}
                type="text"
                value={{this.inputPhoneNumber}}
              />
              <DButton
                class="btn-primary"
                @action={{this.sendCode}}
                @disabled={{or
                  (not this.inputPhoneNumber)
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
                  aria-label={{i18n "phone_gatekeeper.code_label"}}
                  maxlength="6"
                  oninput={{this.onCodeInput}}
                  placeholder={{i18n "phone_gatekeeper.code_placeholder"}}
                  type="text"
                  value={{this.inputCode}}
                />
                <DButton
                  class="btn-success"
                  @action={{this.verifyCode}}
                  @disabled={{not this.inputCode}}
                  @icon="check"
                  @isLoading={{this.verifyingCode}}
                  @label="phone_gatekeeper.verify_btn"
                />
              </div>
            {{/if}}
          </div>
        {{/if}}
      </div>
    {{/if}}
  </template>
}
