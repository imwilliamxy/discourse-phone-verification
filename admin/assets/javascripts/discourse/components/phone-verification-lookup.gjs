import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import getURL from "discourse/lib/get-url";
import DButton from "discourse/ui-kit/d-button";
import dFormatDate from "discourse/ui-kit/helpers/d-format-date";
import { i18n } from "discourse-i18n";
import {
  formatNational,
  nationalDigits,
} from "discourse/plugins/discourse-phone-verification/discourse/lib/phone-format";

const adminUserUrl = (user) =>
  getURL(`/admin/users/${user.id}/${user.username}`);

export default class PhoneVerificationLookup extends Component {
  @tracked phone = "";
  @tracked searching = false;
  @tracked result = null;

  get digits() {
    return nationalDigits(this.phone);
  }

  get incomplete() {
    return this.digits.length !== 10;
  }

  @action
  onInput(event) {
    const formatted = formatNational(nationalDigits(event.target.value));
    this.phone = formatted;
    event.target.value = formatted;
  }

  @action
  async search(event) {
    event?.preventDefault();
    if (this.incomplete) {
      return;
    }

    this.searching = true;
    try {
      this.result = await ajax("/phone-verification/admin/lookup.json", {
        data: { phone_number: `+1${this.digits}` },
      });
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.searching = false;
    }
  }

  <template>
    <div class="phone-verification-lookup">
      <p class="phone-verification-lookup__description">
        {{i18n "phone_verification.admin_lookup.description"}}
      </p>

      <form
        class="phone-verification-lookup__form"
        {{on "submit" this.search}}
      >
        <div class="phone-input">
          <span class="phone-input__prefix">+1</span>
          <input
            aria-label={{i18n "phone_verification.phone_label"}}
            class="phone-input__number"
            inputmode="numeric"
            placeholder={{i18n "phone_verification.phone_placeholder"}}
            type="tel"
            value={{this.phone}}
            {{on "input" this.onInput}}
          />
        </div>
        <DButton
          class="btn-primary phone-verification-lookup__search"
          @action={{this.search}}
          @disabled={{this.incomplete}}
          @icon="magnifying-glass"
          @isLoading={{this.searching}}
          @label="phone_verification.admin_lookup.search"
        />
      </form>

      {{#if this.result}}
        {{#if this.result.bindings.length}}
          <table class="phone-verification-lookup__results">
            <tbody>
              {{#each this.result.bindings as |binding|}}
                <tr>
                  <td>
                    <a href={{adminUserUrl binding.user}}>
                      {{binding.user.username}}
                    </a>
                  </td>
                  <td>
                    {{#if binding.active}}
                      <span class="phone-verification-lookup__active">
                        {{i18n "phone_verification.admin_lookup.active"}}
                      </span>
                    {{else}}
                      {{i18n "phone_verification.admin_lookup.inactive"}}
                    {{/if}}
                  </td>
                  <td>{{dFormatDate binding.verified_at}}</td>
                </tr>
              {{/each}}
            </tbody>
          </table>
        {{else}}
          <p class="phone-verification-lookup__empty">
            {{i18n
              "phone_verification.admin_lookup.no_results"
              phone=this.result.phone_number_masked
            }}
          </p>
        {{/if}}
      {{/if}}
    </div>
  </template>
}
