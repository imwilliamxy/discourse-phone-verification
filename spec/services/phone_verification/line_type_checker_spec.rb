# frozen_string_literal: true

require "rails_helper"

RSpec.describe PhoneVerification::LineTypeChecker do
  let(:phone) { "+14155552671" }
  let(:mock_provider) do
    instance_double(PhoneVerification::LookupProvider::Base)
  end

  before do
    Discourse.redis.flushdb
    SiteSetting.phone_verification_block_voip = true
    SiteSetting.phone_verification_debug_mode = false
    SiteSetting.phone_verification_lookup_cache_ttl_days = 30
    allow(PhoneVerification::LookupProvider::Factory).to receive(
      :get
    ).and_return(mock_provider)
  end

  it "returns allowed without calling provider when block_voip is disabled" do
    SiteSetting.phone_verification_block_voip = false
    allow(mock_provider).to receive(:lookup)

    result = described_class.check(phone)
    expect(result[:allowed]).to be true
    expect(mock_provider).not_to have_received(:lookup)
  end

  it "returns allowed without calling provider when debug_mode is enabled" do
    SiteSetting.phone_verification_debug_mode = true
    allow(mock_provider).to receive(:lookup)

    result = described_class.check(phone)
    expect(result[:allowed]).to be true
    expect(mock_provider).not_to have_received(:lookup)
  end

  it "allows mobile numbers and caches the result in Redis" do
    allow(mock_provider).to receive(:lookup).with(phone).and_return(
      PhoneVerification::LookupProvider::Result.new(
        success: true,
        line_type: "mobile",
        carrier_name: "AT&T"
      )
    )

    first = described_class.check(phone)
    expect(first[:allowed]).to be true

    # Second call should hit cache and not invoke provider again
    second = described_class.check(phone)
    expect(second[:allowed]).to be true
    expect(mock_provider).to have_received(:lookup).once
  end

  it "blocks VoIP numbers and caches the blocked result in Redis" do
    allow(mock_provider).to receive(:lookup).with(phone).and_return(
      PhoneVerification::LookupProvider::Result.new(
        success: true,
        line_type: "nonFixedVoip",
        carrier_name: "Google Voice"
      )
    )

    first = described_class.check(phone)
    expect(first[:allowed]).to be false
    expect(first[:error]).to eq(
      I18n.t("phone_verification.errors.voip_phone_blocked")
    )

    # Second call should hit cache and still reject without calling provider
    second = described_class.check(phone)
    expect(second[:allowed]).to be false
    expect(mock_provider).to have_received(:lookup).once
  end

  it "returns lookup_failed error without caching when provider fails" do
    allow(mock_provider).to receive(:lookup).with(phone).and_return(
      PhoneVerification::LookupProvider::Result.new(
        success: false,
        error_message: "API error"
      )
    )

    result = described_class.check(phone)
    expect(result[:allowed]).to be false
    expect(result[:error]).to eq(
      I18n.t("phone_verification.errors.lookup_failed")
    )
    expect(Discourse.redis.get(described_class.cache_key(phone))).to be_nil
  end
end
