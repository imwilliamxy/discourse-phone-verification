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

  describe "#send_code abuse protection" do
    let(:today) { Time.zone.now.strftime("%Y%m%d") }

    context "when the user's trust level is below the send threshold" do
      fab!(:new_user) { Fabricate(:user, trust_level: TrustLevel[0]) }

      it "rejects the request without sending an SMS" do
        result = described_class.send_code(user: new_user, phone_number: phone)
        expect(result[:success]).to be false
        expect(result[:error]).to eq(
          I18n.t(
            "phone_verification.errors.trust_level_too_low",
            trust_level: 1
          )
        )
        expect(PhoneVerification::SmsProvider::Factory).not_to have_received(
          :get
        )
      end

      it "still allows staff" do
        new_user.update!(moderator: true)
        result = described_class.send_code(user: new_user, phone_number: phone)
        expect(result[:success]).to be true
      end
    end

    it "rejects +1 numbers outside the US" do
      result =
        described_class.send_code(user: user, phone_number: "+18765552671")
      expect(result[:success]).to be false
      expect(result[:error]).to eq(
        I18n.t("phone_verification.errors.invalid_phone_number")
      )
    end

    it "counts every successful send per user, number, IP and site" do
      described_class.send_code(
        user: user,
        phone_number: phone,
        ip_address: "1.2.3.4"
      )

      expect(
        Discourse.redis.get("phone_verification:daily:#{user.id}:#{today}")
      ).to eq("1")
      expect(
        Discourse.redis.get("phone_verification:daily_phone:#{phone}:#{today}")
      ).to eq("1")
      expect(
        Discourse.redis.get("phone_verification:daily_ip:1.2.3.4:#{today}")
      ).to eq("1")
      expect(
        Discourse.redis.get("phone_verification:daily_global:#{today}")
      ).to eq("1")
    end

    it "blocks a number that reached its daily limit, whichever account asks" do
      SiteSetting.phone_verification_sms_daily_limit_per_phone = 2
      Discourse.redis.set("phone_verification:daily_phone:#{phone}:#{today}", 2)

      result = described_class.send_code(user: user, phone_number: phone)
      expect(result[:error]).to eq(
        I18n.t("phone_verification.errors.daily_limit_exceeded")
      )
    end

    it "blocks an IP that reached its daily limit" do
      SiteSetting.phone_verification_sms_daily_limit_per_ip = 2
      Discourse.redis.set("phone_verification:daily_ip:1.2.3.4:#{today}", 2)

      result =
        described_class.send_code(
          user: user,
          phone_number: phone,
          ip_address: "1.2.3.4"
        )
      expect(result[:error]).to eq(
        I18n.t("phone_verification.errors.daily_limit_exceeded")
      )
    end

    it "blocks everyone once the site-wide limit is reached and keeps no cooldown" do
      SiteSetting.phone_verification_sms_daily_limit_global = 5
      Discourse.redis.set("phone_verification:daily_global:#{today}", 5)

      2.times do
        result = described_class.send_code(user: user, phone_number: phone)
        expect(result[:error]).to eq(
          I18n.t("phone_verification.errors.daily_limit_exceeded")
        )
      end
      expect(PhoneVerification::SmsProvider::Factory).not_to have_received(
        :get
      )
    end

    context "when the SMS provider fails" do
      before do
        failing_provider = instance_double(PhoneVerification::SmsProvider::Base)
        allow(failing_provider).to receive(:send_sms).and_return(
          PhoneVerification::SmsProvider::Result.new(
            success: false,
            error_message:
              "User: arn:aws:iam::123456789012:user/sms is not authorized to perform: SNS:Publish"
          )
        )
        allow(PhoneVerification::SmsProvider::Factory).to receive(
          :get
        ).and_return(failing_provider)
      end

      it "returns a generic error and does not start the cooldown" do
        result = described_class.send_code(user: user, phone_number: phone)
        expect(result[:success]).to be false
        expect(result[:error]).to eq(
          I18n.t("phone_verification.errors.sms_send_failed")
        )
        expect(
          Discourse.redis.get("phone_verification:cooldown:#{user.id}")
        ).to be_nil
      end
    end
  end

  describe "numbers already bound to another account" do
    fab!(:other_user, :user)

    before do
      SiteSetting.phone_verification_debug_mode = false
      PhoneVerification::UserPhoneRecord.create!(
        user: other_user,
        phone_number: phone,
        verified_at: Time.zone.now,
        active: true
      )
    end

    def sent_code
      JSON.parse(Discourse.redis.get("phone_verification:code:#{user.id}"))[
        "code"
      ]
    end

    it "does not reveal the binding when sending a code" do
      result = described_class.send_code(user: user, phone_number: phone)
      expect(result[:success]).to be true
    end

    it "does not reveal the binding for a wrong code" do
      described_class.send_code(user: user, phone_number: phone)
      wrong_code = sent_code == "000000" ? "111111" : "000000"

      result =
        described_class.verify_code(
          user: user,
          phone_number: phone,
          code: wrong_code
        )
      expect(result[:error]).to eq(
        I18n.t("phone_verification.errors.invalid_code")
      )
    end

    it "reports the binding only after the correct code, keeping both records" do
      own_record =
        PhoneVerification::UserPhoneRecord.create!(
          user: user,
          phone_number: "+14155552672",
          verified_at: Time.zone.now,
          active: true
        )
      described_class.send_code(user: user, phone_number: phone)

      result =
        described_class.verify_code(
          user: user,
          phone_number: phone,
          code: sent_code
        )
      expect(result[:success]).to be false
      expect(result[:error]).to eq(
        I18n.t("phone_verification.errors.phone_already_used")
      )
      expect(
        PhoneVerification::UserPhoneRecord
          .active
          .with_phone(phone)
          .first
          .user_id
      ).to eq(other_user.id)
      expect(own_record.reload.active).to be true
    end
  end

  describe "debug mode on a production server" do
    before do
      SiteSetting.phone_verification_debug_mode = true
      allow(Rails.env).to receive(:production?).and_return(true)
    end

    after { ENV.delete("DISCOURSE_PHONE_VERIFICATION_ALLOW_DEBUG_MODE") }

    it "is ignored unless the container env opts in" do
      expect(PhoneVerification.debug_mode?).to be false

      result =
        described_class.verify_code(
          user: user,
          phone_number: phone,
          code: "123456"
        )
      expect(result[:success]).to be false
    end

    it "takes effect when the container env opts in" do
      ENV["DISCOURSE_PHONE_VERIFICATION_ALLOW_DEBUG_MODE"] = "true"
      expect(PhoneVerification.debug_mode?).to be true
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

      it "allows at most 5 attempts per code" do
        described_class.send_code(user: user, phone_number: phone)
        code =
          JSON.parse(Discourse.redis.get("phone_verification:code:#{user.id}"))[
            "code"
          ]
        wrong_code = code == "000000" ? "111111" : "000000"

        5.times do
          result =
            described_class.verify_code(
              user: user,
              phone_number: phone,
              code: wrong_code
            )
          expect(result[:error]).to eq(
            I18n.t("phone_verification.errors.invalid_code")
          )
        end

        result =
          described_class.verify_code(user: user, phone_number: phone, code: code)
        expect(result[:error]).to eq(
          I18n.t("phone_verification.errors.too_many_attempts")
        )
        expect(
          Discourse.redis.get("phone_verification:code:#{user.id}")
        ).to be_nil
      end

      it "gives a new code a fresh attempt budget" do
        Discourse.redis.set("phone_verification:attempts:#{user.id}", 5)
        described_class.send_code(user: user, phone_number: phone)
        code =
          JSON.parse(Discourse.redis.get("phone_verification:code:#{user.id}"))[
            "code"
          ]

        result =
          described_class.verify_code(user: user, phone_number: phone, code: code)
        expect(result[:success]).to be true
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
