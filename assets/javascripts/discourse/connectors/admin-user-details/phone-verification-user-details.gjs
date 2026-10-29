import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import DButton from "discourse/ui-kit/d-button";
import dFormatDate from "discourse/ui-kit/helpers/d-format-date";
import { i18n } from "discourse-i18n";

export default class PhoneVerificationUserDetails extends Component {
  @service currentUser;
  @service dialog;
  @service siteSettings;
  @service toasts;

  @tracked unbound = false;
  @tracked unbinding = false;

  get user() {
    return this.args.outletArgs?.model;
  }

  get record() {
    return this.unbound ? null : this.user?.phone_verification_record;
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

  // The server only allows admins; hide the button from moderators too
  get canUnbind() {
    return this.hasPhoneNumber && this.currentUser?.admin;
  }

  @action
  confirmUnbind() {
    this.dialog.confirm({
      message: i18n("admin.phone_verification.unbind_confirm"),
      didConfirm: () => this.unbind(),
    });
  }

  async unbind() {
    this.unbinding = true;
    try {
      await ajax(`/phone-verification/admin/users/${this.user.id}.json`, {
        type: "DELETE",
      });
      this.unbound = true;
      this.toasts.success({
        data: { message: i18n("admin.phone_verification.unbound") },
      });
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.unbinding = false;
    }
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
          {{#if this.canUnbind}}
            <div class="controls">
              <DButton
                class="btn-danger phone-verification-admin-unbind"
                @action={{this.confirmUnbind}}
                @icon="trash-can"
                @isLoading={{this.unbinding}}
                @label="admin.phone_verification.unbind_btn"
              />
            </div>
          {{/if}}
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
