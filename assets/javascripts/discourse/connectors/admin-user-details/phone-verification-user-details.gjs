import Component from "@glimmer/component";
import { service } from "@ember/service";
import dFormatDate from "discourse/ui-kit/helpers/d-format-date";
import { i18n } from "discourse-i18n";

export default class PhoneVerificationUserDetails extends Component {
  @service siteSettings;

  get record() {
    return this.args.outletArgs?.model?.phone_verification_record;
  }

  get hasPhoneNumber() {
    return Boolean(this.record?.phone_number_masked);
  }

  get phoneNumber() {
    return this.record?.phone_number_masked;
  }

  get verifiedAt() {
    return this.record?.verified_at;
  }

  <template>
    {{#if this.siteSettings.phone_verification_enabled}}
      <section class="details phone-verification-admin-details">
        <h1>{{i18n "admin.phone_verification.title"}}</h1>
        <div class="display-row">
          <div class="field">{{i18n
              "admin.phone_verification.phone_number"
            }}</div>
          <div class="value">
            {{#if this.hasPhoneNumber}}
              {{this.phoneNumber}}
            {{else}}
              &mdash; ({{i18n "admin.phone_verification.not_verified"}})
            {{/if}}
          </div>
        </div>
        {{#if this.verifiedAt}}
          <div class="display-row">
            <div class="field">{{i18n
                "admin.phone_verification.verified_at"
              }}</div>
            <div class="value">
              {{dFormatDate this.verifiedAt}}
            </div>
          </div>
        {{/if}}
      </section>
    {{/if}}
  </template>
}
