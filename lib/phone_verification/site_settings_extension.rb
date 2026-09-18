# frozen_string_literal: true

module ::PhoneVerification
  module LocalizedLabelFormatter
    def humanized_name(setting)
      setting_key = setting.to_s
      if I18n.exists?("site_settings.names.#{setting_key}")
        translated =
          I18n.t("site_settings.names.#{setting_key}", default: "").presence
        return translated if translated
      end

      super
    end
  end

  module LocalizedSiteSettingExtension
    def humanized_names(name)
      @humanized_names ||= {}
      cache_key = "#{I18n.locale}:#{name}"
      @humanized_names[cache_key] ||= humanized_name(name)
    end
  end
end
