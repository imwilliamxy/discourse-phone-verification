# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Site Settings Localization" do
  describe "SiteSettings::LabelFormatter.humanized_name" do
    it "returns localized name in zh_CN" do
      I18n.with_locale(:zh_CN) do
        expect(SiteSettings::LabelFormatter.humanized_name(:phone_gatekeeper_enabled)).to eq("启用手机号验证门禁")
        expect(SiteSettings::LabelFormatter.humanized_name(:phone_gatekeeper_min_trust_level)).to eq("门禁准入最低信任等级")
        expect(SiteSettings::LabelFormatter.humanized_name(:phone_gatekeeper_sms_provider)).to eq("短信服务商")
      end
    end

    it "returns localized name in en" do
      I18n.with_locale(:en) do
        expect(SiteSettings::LabelFormatter.humanized_name(:phone_gatekeeper_enabled)).to eq("Phone Gatekeeper Enabled")
      end
    end

    it "falls back to default humanized name when translation is missing" do
      expect(SiteSettings::LabelFormatter.humanized_name(:title)).to eq("Title")
    end
  end

  describe "SiteSetting.humanized_names memoization with locale" do
    it "returns different humanized names for different locales" do
      name_zh = nil
      name_en = nil

      I18n.with_locale(:zh_CN) do
        name_zh = SiteSetting.humanized_names(:phone_gatekeeper_enabled)
      end

      I18n.with_locale(:en) do
        name_en = SiteSetting.humanized_names(:phone_gatekeeper_enabled)
      end

      expect(name_zh).to eq("启用手机号验证门禁")
      expect(name_en).to eq("Phone Gatekeeper Enabled")
    end
  end

  describe "Site Settings Provider Dependencies" do
    let(:all_settings) { SiteSetting.all_settings }

    def find_setting(name)
      all_settings.find { |s| s[:setting] == name }
    end

    it "configures AWS SNS settings to depend on phone_gatekeeper_sms_provider being aws_sns" do
      aws_settings = %i[
        phone_gatekeeper_aws_region
        phone_gatekeeper_aws_access_key_id
        phone_gatekeeper_aws_secret_access_key
        phone_gatekeeper_sms_sender_id
      ]

      aws_settings.each do |setting_name|
        setting = find_setting(setting_name)
        expect(setting).to be_present
        expect(setting[:depends_on]).to eq([:phone_gatekeeper_sms_provider])
        expect(setting[:depends_on_values]).to eq(phone_gatekeeper_sms_provider: ["aws_sns"])
        expect(setting[:depends_behavior]).to eq(:hidden)
      end
    end

    it "configures Twilio settings to depend on phone_gatekeeper_sms_provider being twilio" do
      twilio_settings = %i[
        phone_gatekeeper_twilio_account_sid
        phone_gatekeeper_twilio_auth_token
        phone_gatekeeper_twilio_from_phone_number
        phone_gatekeeper_twilio_messaging_service_sid
      ]

      twilio_settings.each do |setting_name|
        setting = find_setting(setting_name)
        expect(setting).to be_present
        expect(setting[:depends_on]).to eq([:phone_gatekeeper_sms_provider])
        expect(setting[:depends_on_values]).to eq(phone_gatekeeper_sms_provider: ["twilio"])
        expect(setting[:depends_behavior]).to eq(:hidden)
      end
    end
  end
end

