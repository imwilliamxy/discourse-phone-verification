import Component from "@glimmer/component";
import { service } from "@ember/service";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

export default class PhoneVerificationDependencyNotice extends Component {
  @service site;

  get isPhoneVerificationEnabledSetting() {
    return (
      this.args.outletArgs?.setting?.setting === "phone_verification_enabled"
    );
  }

  get isDynamicGroupsInstalled() {
    return Boolean(this.site.phone_verification_dynamic_groups_installed);
  }

  <template>
    {{#if this.isPhoneVerificationEnabledSetting}}
      <div
        class="phone-verification-dependency-callout
          {{if this.isDynamicGroupsInstalled 'is-installed' 'is-missing'}}"
      >
        <div class="callout-header">
          {{#if this.isDynamicGroupsInstalled}}
            <span class="callout-icon is-installed">{{dIcon
                "circle-check"
              }}</span>
            <span class="callout-title">
              {{i18n "admin.phone_verification.dynamic_groups.installed_title"}}
            </span>
          {{else}}
            <span class="callout-icon is-missing">{{dIcon
                "triangle-exclamation"
              }}</span>
            <span class="callout-title">
              {{i18n "admin.phone_verification.dynamic_groups.missing_title"}}
            </span>
          {{/if}}
        </div>

        <p class="callout-body">
          {{#if this.isDynamicGroupsInstalled}}
            {{i18n
              "admin.phone_verification.dynamic_groups.installed_description"
            }}
          {{else}}
            {{i18n
              "admin.phone_verification.dynamic_groups.missing_description"
            }}
          {{/if}}
        </p>

        {{#unless this.isDynamicGroupsInstalled}}
          <div class="callout-actions">
            <a
              class="btn btn-default btn-small btn-dynamic-groups-link"
              href="https://github.com/communiteq/discourse-dynamic-groups"
              rel="noopener noreferrer"
              target="_blank"
            >
              {{dIcon "up-right-from-square"}}
              {{i18n "admin.phone_verification.dynamic_groups.learn_more"}}
            </a>
          </div>
        {{/unless}}
      </div>
    {{/if}}
  </template>
}
