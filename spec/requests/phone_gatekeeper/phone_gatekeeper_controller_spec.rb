# frozen_string_literal: true

require "rails_helper"

RSpec.describe PhoneGatekeeper::PhoneGatekeeperController, type: :request do
  fab!(:user) { Fabricate(:user, trust_level: TrustLevel[1]) }
  let(:phone) { "+14155552671" }

  before do
    SiteSetting.phone_gatekeeper_enabled = true
    sign_in(user)

    mock_provider = instance_double(PhoneGatekeeper::SmsProvider::Base)
    allow(mock_provider).to receive(:send_sms).and_return(
      PhoneGatekeeper::SmsProvider::Result.new(
        success: true,
        message_id: "req_msg_id"
      )
    )
    allow(PhoneGatekeeper::SmsProvider::Factory).to receive(:get).and_return(
      mock_provider
    )
  end

  describe "GET /phone-gatekeeper/status" do
    it "returns unverified status for new user" do
      get "/phone-gatekeeper/status.json"
      expect(response.status).to eq(200)
      json = response.parsed_body
      expect(json["phone_verified"]).to be false
      expect(json["min_trust_level"]).to eq(1)
    end
  end

  describe "POST /phone-gatekeeper/send-code" do
    it "sends code and returns cooldown" do
      post "/phone-gatekeeper/send-code.json", params: { phone_number: phone }
      expect(response.status).to eq(200)
      expect(response.parsed_body["success"]).to be true
    end
  end

  describe "POST /phone-gatekeeper/verify-code" do
    it "verifies and binds phone" do
      PhoneGatekeeper::VerificationService.send_code(
        user: user,
        phone_number: phone
      )
      code =
        JSON.parse(Discourse.redis.get("phone_gatekeeper:code:#{user.id}"))[
          "code"
        ]

      post "/phone-gatekeeper/verify-code.json",
           params: {
             phone_number: phone,
             code: code
           }
      expect(response.status).to eq(200)
      expect(response.parsed_body["phone_number_masked"]).to eq(
        "+1 (***) ***-2671"
      )
    end
  end

  describe "POST /phone-gatekeeper/unbind" do
    it "unbinds phone successfully" do
      PhoneGatekeeper::UserPhoneRecord.create!(
        user: user,
        phone_number: phone,
        verified_at: Time.zone.now,
        active: true
      )

      post "/phone-gatekeeper/unbind.json"
      expect(response.status).to eq(200)
      expect(response.parsed_body["success"]).to be true
    end
  end
end
