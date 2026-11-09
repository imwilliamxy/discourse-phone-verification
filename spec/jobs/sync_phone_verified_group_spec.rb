# frozen_string_literal: true

require "rails_helper"

RSpec.describe Jobs::SyncPhoneVerifiedGroup do
  fab!(:user) { Fabricate(:user, trust_level: TrustLevel[3]) }
  fab!(:admin)

  let(:group) do
    PhoneVerification::GroupSyncService.find_or_create_target_group
  end

  before do
    SiteSetting.phone_verification_enabled = true
    SiteSetting.phone_verification_min_trust_level = 3
    PhoneVerification::UserPhoneRecord.create!(
      user: user,
      phone_number: "+14155552671",
      verified_at: Time.zone.now,
      active: true
    )
    PhoneVerification::GroupSyncService.sync_user(user)
  end

  it "puts a user back once a timed suspension has run out" do
    user.update!(suspended_at: Time.zone.now, suspended_till: 1.day.from_now)
    PhoneVerification::GroupSyncService.sync_user(user)
    expect(group.reload.users).not_to include(user)

    # Expiry fires no event; only the daily pass notices
    freeze_time 2.days.from_now do
      described_class.new.execute({})
      expect(group.reload.users).to include(user)
    end
  end

  it "does nothing while the plugin is disabled" do
    group.remove(user)
    SiteSetting.phone_verification_enabled = false

    described_class.new.execute({})
    expect(group.reload.users).not_to include(user)
  end

  it "runs in a job when a setting that changes who qualifies is saved" do
    expect_enqueued_with(job: :sync_phone_verified_group) do
      SiteSetting.phone_verification_min_trust_level = 2
    end
  end
end
