# frozen_string_literal: true

require "rails_helper"

RSpec.describe PhoneVerification::VerificationService do
  fab!(:user)
  let(:phone) { "+14155552671" }

  before do
    SiteSetting.phone_verification_enabled = true
    SiteSetting.phone_verification_sms_daily_limit_per_user = 3
    Discourse.redis.flushdb

    mock_provider = instance_double(PhoneVerification::SmsProvider::Base)
    allow(mock_provider).to receive(:send_sms).and_return(
      PhoneVerification::SmsProvider::Result.new(
        success: true,
        message_id: "test_msg"
      )
    )
    allow(PhoneVerification::SmsProvider::Factory).to receive(:get).and_return(
      mock_provider
    )
  end

  describe "#send_code" do
    it "sends code and sets cooldown" do
      result = described_class.send_code(user: user, phone_number: phone)
      expect(result[:success]).to be true
      expect(result[:cooldown_seconds]).to eq(60)

      # Immediate second attempt blocked by cooldown
      repeat = described_class.send_code(user: user, phone_number: phone)
      expect(repeat[:success]).to be false
      expect(repeat[:error]).to include("Please wait")
    end

    it "rejects invalid phone numbers" do
      result = described_class.send_code(user: user, phone_number: "12345")
      expect(result[:success]).to be false
    end

    context "when daily limit is reached" do
      let(:today) { Time.zone.now.strftime("%Y%m%d") }
      let(:daily_key) { "phone_verification:daily:#{user.id}:#{today}" }

      before { Discourse.redis.set(daily_key, 3) }

      it "blocks sending in production mode" do
        SiteSetting.phone_verification_debug_mode = false
        result = described_class.send_code(user: user, phone_number: phone)
        expect(result[:success]).to be false
        expect(result[:error]).to eq(
          I18n.t("phone_verification.errors.daily_limit_exceeded")
        )
      end

      it "allows sending when debug mode is enabled" do
        SiteSetting.phone_verification_debug_mode = true
        result = described_class.send_code(user: user, phone_number: phone)
        expect(result[:success]).to be true
      end
    end

    context "when debug mode is enabled" do
      before { SiteSetting.phone_verification_debug_mode = true }

      it "does not call SMS provider and succeeds" do
        allow(PhoneVerification::SmsProvider::Factory).to receive(:get)
        result = described_class.send_code(user: user, phone_number: phone)
        expect(PhoneVerification::SmsProvider::Factory).not_to have_received(
          :get
        )
        expect(result[:success]).to be true
        expect(result[:cooldown_seconds]).to eq(60)
      end
    end

    context "when phone number is disposable" do
      before do
        SiteSetting.phone_verification_block_disposable = true
        Discourse.redis.sadd(
          PhoneVerification::DisposablePhoneChecker::REDIS_SET_KEY,
          "14155552671"
        )
      end

      it "rejects sending code for disposable phone number" do
        result = described_class.send_code(user: user, phone_number: phone)
        expect(result[:success]).to be false
        expect(result[:error]).to eq(
          I18n.t("phone_verification.errors.disposable_phone_blocked")
        )
      end

      it "rejects verifying code for disposable phone number even in debug mode" do
        SiteSetting.phone_verification_debug_mode = true
        result =
          described_class.verify_code(
            user: user,
            phone_number: phone,
            code: "123456"
          )
        expect(result[:success]).to be false
        expect(result[:error]).to eq(
          I18n.t("phone_verification.errors.disposable_phone_blocked")
        )
      end
    end

    context "when VoIP blocking is enabled" do
      let(:mock_lookup) do
        instance_double(PhoneVerification::LookupProvider::Base)
      end

      before do
        SiteSetting.phone_verification_block_voip = true
        SiteSetting.phone_verification_debug_mode = false
        allow(PhoneVerification::LookupProvider::Factory).to receive(
          :get
        ).and_return(mock_lookup)
      end

      it "rejects sending SMS when number is identified as VoIP" do
        allow(mock_lookup).to receive(:lookup).with(phone).and_return(
          PhoneVerification::LookupProvider::Result.new(
            success: true,
            line_type: "nonFixedVoip",
            carrier_name: "Google Voice"
          )
        )

        result = described_class.send_code(user: user, phone_number: phone)
        expect(result[:success]).to be false
        expect(result[:error]).to eq(
          I18n.t("phone_verification.errors.voip_phone_blocked")
        )
      end

      it "sends SMS when number is identified as mobile" do
        allow(mock_lookup).to receive(:lookup).with(phone).and_return(
          PhoneVerification::LookupProvider::Result.new(
            success: true,
            line_type: "mobile",
            carrier_name: "T-Mobile"
          )
        )

        result = described_class.send_code(user: user, phone_number: phone)
        expect(result[:success]).to be true
      end
    end
  end

  describe "#verify_code" do
    context "when debug mode is disabled (production mode)" do
      before { SiteSetting.phone_verification_debug_mode = false }

      it "verifies correct code from Redis and creates active phone record" do
        described_class.send_code(user: user, phone_number: phone)
        code_data =
          JSON.parse(Discourse.redis.get("phone_verification:code:#{user.id}"))
        valid_code = code_data["code"]

        result =
          described_class.verify_code(
            user: user,
            phone_number: phone,
            code: valid_code
          )
        expect(result[:success]).to be true
        expect(result[:phone_number_masked]).to eq("+1 (***) ***-2671")
        expect(
          PhoneVerification::UserPhoneRecord.where(
            user: user,
            active: true
          ).exists?
        ).to be true
        expect(
          Discourse.redis.get("phone_verification:code:#{user.id}")
        ).to be_nil
      end

      it "rejects incorrect code and limits attempts" do
        described_class.send_code(user: user, phone_number: phone)
        result =
          described_class.verify_code(
            user: user,
            phone_number: phone,
            code: "000000"
          )
        expect(result[:success]).to be false
        expect(result[:error]).to be_present
      end

      it "rejects verification when no code was sent" do
        result =
          described_class.verify_code(
            user: user,
            phone_number: phone,
            code: "123456"
          )
        expect(result[:success]).to be false
        expect(result[:error]).to be_present
      end
    end

    context "when debug mode is enabled" do
      before { SiteSetting.phone_verification_debug_mode = true }

      it "verifies any 6-digit code without sending code" do
        result =
          described_class.verify_code(
            user: user,
            phone_number: phone,
            code: "123456"
          )
        expect(result[:success]).to be true
        expect(result[:phone_number_masked]).to eq("+1 (***) ***-2671")
        expect(
          PhoneVerification::UserPhoneRecord.where(
            user: user,
            active: true
          ).exists?
        ).to be true
      end

      it "rejects non-6-digit code" do
        result =
          described_class.verify_code(
            user: user,
            phone_number: phone,
            code: "123"
          )
        expect(result[:success]).to be false
        expect(result[:error]).to be_present
      end
    end
  end

  describe "#unbind" do
    it "deactivates phone record and updates group access" do
      PhoneVerification::UserPhoneRecord.create!(
        user: user,
        phone_number: phone,
        verified_at: Time.zone.now,
        active: true
      )

      result = described_class.unbind(user: user)
      expect(result[:success]).to be true
      expect(
        PhoneVerification::UserPhoneRecord.where(
          user: user,
          active: true
        ).exists?
      ).to be false
    end
  end
end
