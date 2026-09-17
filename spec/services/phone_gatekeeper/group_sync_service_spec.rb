# frozen_string_literal: true

require "rails_helper"

RSpec.describe PhoneGatekeeper::GroupSyncService do
  fab!(:user) { Fabricate(:user, trust_level: TrustLevel[1]) }
  let(:group_name) { "phone_verified" }

  before do
    SiteSetting.phone_gatekeeper_enabled = true
    SiteSetting.phone_gatekeeper_min_trust_level = 1
    SiteSetting.phone_gatekeeper_group_name = group_name
  end

  it "adds user to target group when phone is verified and trust level matches" do
    PhoneGatekeeper::UserPhoneRecord.create!(
      user: user,
      phone_number: "+14155552671",
      verified_at: Time.zone.now,
      active: true
    )

    described_class.sync_user(user)
    group = Group.find_by(name: group_name)
    expect(group.users).to include(user)
  end

  it "removes user from group if user trust level is below requirement" do
    user.update!(trust_level: TrustLevel[0])
    PhoneGatekeeper::UserPhoneRecord.create!(
      user: user,
      phone_number: "+14155552671",
      verified_at: Time.zone.now,
      active: true
    )

    described_class.sync_user(user)
    group = Group.find_by(name: group_name)
    expect(group.users).not_to include(user)
  end

  it "removes user from group if phone is deactivated/unbound" do
    record =
      PhoneGatekeeper::UserPhoneRecord.create!(
        user: user,
        phone_number: "+14155552671",
        verified_at: Time.zone.now,
        active: true
      )
    described_class.sync_user(user)
    group = Group.find_by(name: group_name)
    expect(group.users).to include(user)

    record.deactivate!
    described_class.sync_user(user)
    expect(group.users).not_to include(user)
  end

  describe ".sync_all" do
    fab!(:user2) { Fabricate(:user, trust_level: TrustLevel[2]) }
    fab!(:user3) { Fabricate(:user, trust_level: TrustLevel[0]) }

    it "synchronizes all eligible and ineligible users across the system" do
      # user: TL 1, verified -> eligible
      PhoneGatekeeper::UserPhoneRecord.create!(
        user: user,
        phone_number: "+14155552671",
        verified_at: Time.zone.now,
        active: true
      )

      # user2: TL 2, verified -> eligible
      PhoneGatekeeper::UserPhoneRecord.create!(
        user: user2,
        phone_number: "+14155552672",
        verified_at: Time.zone.now,
        active: true
      )

      # user3: TL 0, verified -> ineligible
      PhoneGatekeeper::UserPhoneRecord.create!(
        user: user3,
        phone_number: "+14155552673",
        verified_at: Time.zone.now,
        active: true
      )

      described_class.sync_all

      group = Group.find_by(name: group_name)
      expect(group.users).to include(user)
      expect(group.users).to include(user2)
      expect(group.users).not_to include(user3)

      # When min trust level is updated to 0, sync_all includes user3
      SiteSetting.phone_gatekeeper_min_trust_level = 0
      described_class.sync_all
      expect(group.users.reload).to include(user3)
    end
  end
end
