# frozen_string_literal: true

require "rails_helper"

RSpec.describe PhoneVerification::LookupProvider::TwilioLookup do
  subject(:provider) { described_class.new }

  let(:phone) { "+14155552671" }

  before do
    SiteSetting.phone_verification_twilio_account_sid = "AC_test_sid"
    SiteSetting.phone_verification_twilio_auth_token = "test_auth_token"
  end

  it "returns failure when Twilio credentials are missing" do
    SiteSetting.phone_verification_twilio_account_sid = ""
    result = provider.lookup(phone)
    expect(result.success?).to be false
    expect(result.error_message).to include("Twilio Account SID")
  end

  it "identifies a mobile number as non-VoIP and allowed" do
    stub_request(
      :get,
      "https://lookups.twilio.com/v2/PhoneNumbers/%2B14155552671?Fields=line_type_intelligence"
    ).to_return(
      status: 200,
      body: {
        phone_number: phone,
        valid: true,
        line_type_intelligence: {
          type: "mobile",
          carrier_name: "T-Mobile USA, Inc."
        }
      }.to_json
    )

    result = provider.lookup(phone)
    expect(result.success?).to be true
    expect(result.line_type).to eq("mobile")
    expect(result.voip_or_unsupported?).to be false
    expect(result.carrier_name).to eq("T-Mobile USA, Inc.")
  end

  it "identifies nonFixedVoip (e.g. Google Voice) as blocked" do
    stub_request(
      :get,
      "https://lookups.twilio.com/v2/PhoneNumbers/%2B14155552671?Fields=line_type_intelligence"
    ).to_return(
      status: 200,
      body: {
        phone_number: phone,
        valid: true,
        line_type_intelligence: {
          type: "nonFixedVoip",
          carrier_name: "Google (Grand Central) B2B"
        }
      }.to_json
    )

    result = provider.lookup(phone)
    expect(result.success?).to be true
    expect(result.line_type).to eq("nonFixedVoip")
    expect(result.voip_or_unsupported?).to be true
  end

  it "identifies fixedVoip and landline as blocked" do
    stub_request(
      :get,
      "https://lookups.twilio.com/v2/PhoneNumbers/%2B14155552671?Fields=line_type_intelligence"
    ).to_return(
      status: 200,
      body: {
        phone_number: phone,
        valid: true,
        line_type_intelligence: {
          type: "landline",
          carrier_name: "AT&T Local"
        }
      }.to_json
    )

    result = provider.lookup(phone)
    expect(result.success?).to be true
    expect(result.voip_or_unsupported?).to be true
  end

  it "handles Twilio intelligence error_code or missing type as failure (preventing mis-caching)" do
    stub_request(
      :get,
      "https://lookups.twilio.com/v2/PhoneNumbers/%2B14155552671?Fields=line_type_intelligence"
    ).to_return(
      status: 200,
      body: {
        phone_number: phone,
        valid: true,
        line_type_intelligence: {
          error_code: 60_601,
          type: nil
        }
      }.to_json
    )

    result = provider.lookup(phone)
    expect(result.success?).to be false
    expect(result.error_message).to include("60601")
  end

  it "handles HTTP errors gracefully" do
    stub_request(
      :get,
      "https://lookups.twilio.com/v2/PhoneNumbers/%2B14155552671?Fields=line_type_intelligence"
    ).to_return(status: 401, body: { message: "Authenticate" }.to_json)

    result = provider.lookup(phone)
    expect(result.success?).to be false
    expect(result.error_message).to include("Authenticate")
  end
end
