import { withPluginApi } from "discourse/lib/plugin-api";

const PLUGIN_ID = "discourse-phone-verification";

export default {
  name: "phone-verification-admin-nav",

  initialize(container) {
    const currentUser = container.lookup("service:current-user");
    if (!currentUser?.admin) {
      return;
    }

    withPluginApi((api) => {
      api.setAdminPluginIcon(PLUGIN_ID, "mobile-screen");
      api.addAdminPluginConfigurationNav(PLUGIN_ID, [
        {
          label: "phone_verification.admin_lookup.tab_title",
          route: "adminPlugins.show.phone-verification-lookup",
          description: "phone_verification.admin_lookup.description",
        },
      ]);
    });
  },
};
