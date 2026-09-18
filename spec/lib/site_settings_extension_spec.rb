# frozen_string_literal: true

require "rails_helper"

RSpec.describe PhoneVerification::LocalizedLabelFormatter do
  describe "SiteSettings::LabelFormatter.humanized_name" do
    it "returns localized name in zh_CN" do
      I18n.with_locale(:zh_CN) do
        expect(
          SiteSettings::LabelFormatter.humanized_name(
            :phone_verification_enabled
          )
        ).to eq("启用手机号验证插件")
        expect(
          SiteSettings::LabelFormatter.humanized_name(
            :phone_verification_min_trust_level
          )
        ).to eq("可验证手机号的用户最低信任等级")
        expect(
          SiteSettings::LabelFormatter.humanized_name(
            :phone_verification_sms_provider
          )
        ).to eq("短信服务商")
      end
    end

    it "returns localized name in en" do
      I18n.with_locale(:en) do
        expect(
          SiteSettings::LabelFormatter.humanized_name(
            :phone_verification_enabled
          )
        ).to eq("Phone Verification Enabled")
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
        name_zh = SiteSetting.humanized_names(:phone_verification_enabled)
      end

      I18n.with_locale(:en) do
        name_en = SiteSetting.humanized_names(:phone_verification_enabled)
      end

      expect(name_zh).to eq("启用手机号验证插件")
      expect(name_en).to eq("Phone Verification Enabled")
    end
  end

  describe "Site Settings Provider Dependencies" do
    let(:all_settings) { SiteSetting.all_settings }

    def find_setting(name)
      all_settings.find { |s| s[:setting] == name }
    end

    it "configures AWS SNS settings to depend on phone_verification_sms_provider being aws_sns" do
      aws_settings = %i[
        phone_verification_aws_region
        phone_verification_aws_access_key_id
        phone_verification_aws_secret_access_key
        phone_verification_sms_sender_id
      ]

      aws_settings.each do |setting_name|
        setting = find_setting(setting_name)
        expect(setting).to be_present
        expect(setting[:depends_on]).to eq([:phone_verification_sms_provider])
        expect(setting[:depends_on_values]).to eq(
          phone_verification_sms_provider: ["aws_sns"]
        )
        expect(setting[:depends_behavior]).to eq(:hidden)
      end
    end

    it "configures Twilio settings to depend on phone_verification_sms_provider being twilio" do
      twilio_settings = %i[
        phone_verification_twilio_account_sid
        phone_verification_twilio_auth_token
        phone_verification_twilio_from_phone_number
        phone_verification_twilio_messaging_service_sid
      ]

      twilio_settings.each do |setting_name|
        setting = find_setting(setting_name)
        expect(setting).to be_present
        expect(setting[:depends_on]).to eq([:phone_verification_sms_provider])
        expect(setting[:depends_on_values]).to eq(
          phone_verification_sms_provider: ["twilio"]
        )
        expect(setting[:depends_behavior]).to eq(:hidden)
      end
    end
  end
end
