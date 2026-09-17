import Component from "@glimmer/component";
import { service } from "@ember/service";
import dFormatDate from "discourse/ui-kit/helpers/d-format-date";
import { i18n } from "discourse-i18n";

export default class PhoneGatekeeperUserDetails extends Component {
  @service siteSettings;

  get record() {
    return this.args.outletArgs?.model?.phone_gatekeeper_record;
  }

  get hasPhoneNumber() {
    return Boolean(this.record?.phone_number);
  }

  get phoneNumber() {
    return this.record?.phone_number;
  }

  get verifiedAt() {
    return this.record?.verified_at;
  }

  <template>
    {{#if this.siteSettings.phone_gatekeeper_enabled}}
      <section class="details phone-gatekeeper-admin-details">
        <h1>{{i18n "admin.phone_gatekeeper.title"}}</h1>
        <div class="display-row">
          <div class="field">{{i18n "admin.phone_gatekeeper.phone_number"}}</div>
          <div class="value">
            {{#if this.hasPhoneNumber}}
              {{this.phoneNumber}}
            {{else}}
              &mdash; ({{i18n "admin.phone_gatekeeper.not_verified"}})
            {{/if}}
          </div>
        </div>
        {{#if this.verifiedAt}}
          <div class="display-row">
            <div class="field">{{i18n "admin.phone_gatekeeper.verified_at"}}</div>
            <div class="value">
              {{dFormatDate this.verifiedAt}}
            </div>
          </div>
        {{/if}}
      </section>
    {{/if}}
  </template>
}
