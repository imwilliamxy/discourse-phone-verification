# frozen_string_literal: true

require "rails_helper"

RSpec.describe CurrentUserSerializer do
  fab!(:user)

  let(:json) do
    described_class.new(user, scope: Guardian.new(user), root: false).as_json
  end

  before { SiteSetting.phone_verification_enabled = true }

  it "includes phone_verified while the banner is enabled" do
    SiteSetting.phone_verification_banner_enabled = true
    expect(json[:phone_verified]).to eq(false)

    PhoneVerification::UserPhoneRecord.create!(
      user: user,
      phone_number: "+14155552671",
      verified_at: Time.zone.now,
      active: true
    )
    expect(
      described_class.new(user, scope: Guardian.new(user), root: false).as_json[
        :phone_verified
      ]
    ).to eq(true)
  end

  it "leaves it out when the banner is disabled" do
    expect(json).not_to have_key(:phone_verified)
  end
end
