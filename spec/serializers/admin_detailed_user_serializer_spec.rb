# frozen_string_literal: true

require "rails_helper"

RSpec.describe AdminDetailedUserSerializer do
  fab!(:admin)
  fab!(:user)

  before { SiteSetting.phone_verification_enabled = true }

  it "only exposes the masked phone number to staff" do
    PhoneVerification::UserPhoneRecord.create!(
      user: user,
      phone_number: "+14155552671",
      verified_at: Time.zone.now,
      active: true
    )

    json =
      described_class.new(
        user,
        scope: Guardian.new(admin),
        root: false
      ).as_json

    record = json[:phone_verification_record]
    expect(record[:phone_number_masked]).to eq("+1 (***) ***-2671")
    expect(record.to_s).not_to include("4155552671")
  end
end
