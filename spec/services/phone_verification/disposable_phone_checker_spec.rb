# frozen_string_literal: true

require "rails_helper"

RSpec.describe PhoneVerification::DisposablePhoneChecker do
  before do
    Discourse.redis.flushdb
    SiteSetting.phone_verification_block_disposable = true
    SiteSetting.phone_verification_custom_disposable_numbers = ""
  end

  describe ".disposable?" do
    it "returns false when phone_verification_block_disposable is disabled" do
      SiteSetting.phone_verification_block_disposable = false
      Discourse.redis.sadd(described_class::REDIS_SET_KEY, "12012018360")
      expect(described_class.disposable?("+12012018360")).to be false
    end

    it "returns true when phone number is in the Redis disposable set" do
      Discourse.redis.sadd(described_class::REDIS_SET_KEY, "12012018360")
      expect(described_class.disposable?("+12012018360")).to be true
      expect(described_class.disposable?("+14155552671")).to be false
    end

    it "returns true when phone number matches custom disposable numbers setting" do
      SiteSetting.phone_verification_custom_disposable_numbers =
        "+14155550199|415-555-0188"
      expect(described_class.disposable?("+14155550199")).to be true
      expect(described_class.disposable?("+14155550188")).to be true
      expect(described_class.disposable?("+14155552671")).to be false
    end
  end

  describe ".sync_from_json!" do
    it "extracts valid US (+1) numbers, atomically replaces the Redis set, and sets 7-day TTL" do
      sample_json = {
        "12012018360" => "2020-10-30",
        "12012018710" => "2025-05-06",
        "46200231" => "2023-12-20", # Non-US number (Sweden)
        "invalid" => "2025-01-01"
      }.to_json

      count = described_class.sync_from_json!(sample_json)
      expect(count).to eq(2)
      expect(described_class.disposable?("+12012018360")).to be true
      expect(described_class.disposable?("+12012018710")).to be true
      expect(Discourse.redis.scard(described_class::REDIS_SET_KEY)).to eq(2)
      expect(Discourse.redis.get(described_class::REDIS_COUNT_KEY).to_i).to eq(2)
      expect(Discourse.redis.ttl(described_class::REDIS_SET_KEY)).to be_between(
        1,
        described_class::REDIS_TTL_SECONDS
      )
    end
  end

  describe ".clear_cache!" do
    it "removes all disposable phone number Redis keys" do
      described_class.sync_from_json!({ "12012018360" => "2020-10-30" }.to_json)
      expect(Discourse.redis.exists?(described_class::REDIS_SET_KEY)).to be true

      described_class.clear_cache!
      expect(Discourse.redis.exists?(described_class::REDIS_SET_KEY)).to be false
      expect(Discourse.redis.exists?(described_class::REDIS_COUNT_KEY)).to be false
      expect(Discourse.redis.exists?(described_class::REDIS_SYNCED_AT_KEY)).to be false
    end
  end

  describe ".fetch_and_sync!" do
    it "fetches remote JSON list and populates Redis set" do
      sample_body = { "12012018360" => "2020-10-30" }.to_json
      stub_request(
        :get,
        SiteSetting.phone_verification_disposable_list_url
      ).to_return(status: 200, body: sample_body)

      result = described_class.fetch_and_sync!
      expect(result[:success]).to be true
      expect(result[:count]).to eq(1)
      expect(described_class.disposable?("+12012018360")).to be true
    end

    it "falls back to GitHub raw URL if primary URL fails" do
      stub_request(
        :get,
        SiteSetting.phone_verification_disposable_list_url
      ).to_return(status: 503, body: "Service Unavailable")

      stub_request(:get, described_class::FALLBACK_URL).to_return(
        status: 200,
        body: { "12012130064" => "2025-10-09" }.to_json
      )

      result = described_class.fetch_and_sync!
      expect(result[:success]).to be true
      expect(result[:count]).to eq(1)
      expect(described_class.disposable?("+12012130064")).to be true
    end
  end
end
