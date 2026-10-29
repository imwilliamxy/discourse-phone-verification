import Component from "@glimmer/component";
import { service } from "@ember/service";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

export default class PhoneVerificationDynamicGroupsBadge extends Component {
  @service site;

  get isThisPlugin() {
    const plugin = this.args.outletArgs?.plugin;
    return (
      plugin?.name === "discourse-phone-verification" ||
      plugin?.id === "discourse-phone-verification"
    );
  }

  get isDynamicGroupsInstalled() {
    return Boolean(this.site.phone_verification_dynamic_groups_installed);
  }

  <template>
    {{#if this.isThisPlugin}}
      {{#if this.isDynamicGroupsInstalled}}
        <span
          class="phone-verification-plugin-badge is-installed"
          title={{i18n
            "admin.phone_verification.dynamic_groups.installed_title"
          }}
        >
          {{dIcon "circle-check"}}
          {{i18n "admin.phone_verification.dynamic_groups.installed_badge"}}
        </span>
      {{else}}
        <span
          class="phone-verification-plugin-badge is-missing"
          title={{i18n "admin.phone_verification.dynamic_groups.missing_title"}}
        >
          {{dIcon "triangle-exclamation"}}
          {{i18n "admin.phone_verification.dynamic_groups.missing_badge"}}
        </span>
      {{/if}}
    {{/if}}
  </template>
}
