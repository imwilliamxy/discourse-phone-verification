# frozen_string_literal: true

require "rails_helper"

RSpec.describe Jobs::SyncDisposablePhoneNumbers do
  subject(:job) { described_class.new }

  before do
    Discourse.redis.flushdb
    SiteSetting.phone_verification_enabled = true
    SiteSetting.phone_verification_block_disposable = true
  end

  it "does not sync when plugin is disabled" do
    SiteSetting.phone_verification_enabled = false
    allow(PhoneVerification::DisposablePhoneChecker).to receive(:fetch_and_sync!)
    job.execute({})
    expect(
      PhoneVerification::DisposablePhoneChecker
    ).not_to have_received(:fetch_and_sync!)
  end

  it "does not sync when disposable blocking is disabled" do
    SiteSetting.phone_verification_block_disposable = false
    allow(PhoneVerification::DisposablePhoneChecker).to receive(:fetch_and_sync!)
    job.execute({})
    expect(
      PhoneVerification::DisposablePhoneChecker
    ).not_to have_received(:fetch_and_sync!)
  end

  it "calls DisposablePhoneChecker.fetch_and_sync! when enabled" do
    allow(PhoneVerification::DisposablePhoneChecker).to receive(
      :fetch_and_sync!
    ).and_return({ success: true, count: 100 })

    job.execute({})
    expect(
      PhoneVerification::DisposablePhoneChecker
    ).to have_received(:fetch_and_sync!)
  end
end
