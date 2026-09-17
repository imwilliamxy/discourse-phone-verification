# frozen_string_literal: true

require "rails_helper"

RSpec.describe PhoneGatekeeper::SmsProvider::Twilio do
  subject(:provider) { described_class.new }

  let(:account_sid) { "AC_test_dummy_account_sid_99999" }
  let(:auth_token) { "auth_token_secret_123456" }
  let(:from_phone) { "+14155550000" }
  let(:to_phone) { "+14155552671" }
  let(:message_text) { "Your verification code is 123456" }
  let(:api_url) { "https://api.twilio.com/2010-04-01/Accounts/#{account_sid}/Messages.json" }

  before do
    SiteSetting.phone_gatekeeper_enabled = true
    SiteSetting.phone_gatekeeper_twilio_account_sid = account_sid
    SiteSetting.phone_gatekeeper_twilio_auth_token = auth_token
    SiteSetting.phone_gatekeeper_twilio_from_phone_number = from_phone
    SiteSetting.phone_gatekeeper_twilio_messaging_service_sid = ""
  end

  it "returns error when Account SID or Auth Token is missing" do
    SiteSetting.phone_gatekeeper_twilio_account_sid = ""
    result = provider.send_sms(to: to_phone, message: message_text)
    expect(result.success?).to be false
    expect(result.error_message).to include("Account SID and Auth Token must be configured")
  end

  it "returns error when both From phone and Messaging Service SID are missing" do
    SiteSetting.phone_gatekeeper_twilio_from_phone_number = ""
    SiteSetting.phone_gatekeeper_twilio_messaging_service_sid = ""
    result = provider.send_sms(to: to_phone, message: message_text)
    expect(result.success?).to be false
    expect(result.error_message).to include("From Phone Number or Messaging Service SID")
  end

  it "successfully sends SMS with From phone number" do
    stub_request(:post, api_url)
      .with(
        basic_auth: [account_sid, auth_token],
        body: { "To" => to_phone, "From" => from_phone, "Body" => message_text }
      )
      .to_return(
        status: 201,
        body: { sid: "SMabcdef123456", status: "queued" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = provider.send_sms(to: to_phone, message: message_text)
    expect(result.success?).to be true
    expect(result.message_id).to eq("SMabcdef123456")
  end

  it "successfully sends SMS with MessagingServiceSid" do
    SiteSetting.phone_gatekeeper_twilio_from_phone_number = ""
    SiteSetting.phone_gatekeeper_twilio_messaging_service_sid = "MG1234567890"

    stub_request(:post, api_url)
      .with(
        basic_auth: [account_sid, auth_token],
        body: { "To" => to_phone, "MessagingServiceSid" => "MG1234567890", "Body" => message_text }
      )
      .to_return(
        status: 201,
        body: { sid: "SMservice123456", status: "queued" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = provider.send_sms(to: to_phone, message: message_text)
    expect(result.success?).to be true
    expect(result.message_id).to eq("SMservice123456")
  end

  it "handles Twilio API error response" do
    stub_request(:post, api_url)
      .to_return(
        status: 400,
        body: { code: 21211, message: "The 'To' number is not a valid phone number." }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = provider.send_sms(to: to_phone, message: message_text)
    expect(result.success?).to be false
    expect(result.error_message).to eq("The 'To' number is not a valid phone number.")
  end

  it "handles network exception gracefully" do
    stub_request(:post, api_url).to_timeout

    result = provider.send_sms(to: to_phone, message: message_text)
    expect(result.success?).to be false
    expect(result.error_message).to be_present
  end

  describe "Factory" do
    it "returns Twilio provider instance when configured" do
      SiteSetting.phone_gatekeeper_sms_provider = "twilio"
      expect(PhoneGatekeeper::SmsProvider::Factory.get).to be_a(described_class)
    end
  end
end
