# frozen_string_literal: true

require "rails_helper"

RSpec.describe PhoneVerification::SmsProvider::AwsSns do
  subject(:provider) { described_class.new }

  let(:mock_sns_client) { instance_double(Aws::SNS::Client) }

  before do
    SiteSetting.phone_verification_enabled = true
    SiteSetting.phone_verification_aws_region = "us-west-2"
    allow(Aws::SNS::Client).to receive(:new).and_return(mock_sns_client)
  end

  it "successfully publishes transactional SMS" do
    allow(mock_sns_client).to receive(:publish).and_return(
      OpenStruct.new(message_id: "msg_12345")
    )

    result = provider.send_sms(to: "+14155552671", message: "Test message")

    expect(result.success?).to be true
    expect(result.message_id).to eq("msg_12345")
    expect(mock_sns_client).to have_received(:publish).with(
      phone_number: "+14155552671",
      message: "Test message",
      message_attributes: hash_including("AWS.SNS.SMS.SMSType")
    )
  end

  it "gracefully handles AWS SNS ServiceError" do
    allow(mock_sns_client).to receive(:publish).and_raise(
      Aws::SNS::Errors::InvalidParameterException.new(
        nil,
        "Invalid phone number"
      )
    )

    result = provider.send_sms(to: "+14155552671", message: "Test message")
    expect(result.success?).to be false
    expect(result.error_message).to include("Invalid phone number")
  end
end
