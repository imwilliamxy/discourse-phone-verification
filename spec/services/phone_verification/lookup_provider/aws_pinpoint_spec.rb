# frozen_string_literal: true

require "rails_helper"

RSpec.describe PhoneVerification::LookupProvider::AwsPinpoint do
  subject(:provider) { described_class.new }

  let(:phone) { "+14155552671" }

  before do
    SiteSetting.phone_verification_aws_region = "us-east-1"
    SiteSetting.phone_verification_aws_access_key_id = "AKIA_TEST"
    SiteSetting.phone_verification_aws_secret_access_key = "secret_test"
  end

  it "identifies MOBILE phone type as allowed" do
    stub_request(
      :post,
      "https://pinpoint.us-east-1.amazonaws.com/v1/phone/number/validate"
    ).to_return(
      status: 200,
      body: {
        NumberValidateResponse: {
          PhoneType: "MOBILE",
          Carrier: "Verizon Wireless"
        }
      }.to_json
    )

    result = provider.lookup(phone)
    expect(result.success?).to be true
    expect(result.line_type).to eq("mobile")
    expect(result.voip_or_unsupported?).to be false
    expect(result.carrier_name).to eq("Verizon Wireless")
  end

  it "identifies VOIP phone type as blocked" do
    stub_request(
      :post,
      "https://pinpoint.us-east-1.amazonaws.com/v1/phone/number/validate"
    ).to_return(
      status: 200,
      body: {
        NumberValidateResponse: {
          PhoneType: "VOIP",
          Carrier: "Bandwidth.com"
        }
      }.to_json
    )

    result = provider.lookup(phone)
    expect(result.success?).to be true
    expect(result.line_type).to eq("voip")
    expect(result.voip_or_unsupported?).to be true
  end
end
