# frozen_string_literal: true

require "rails_helper"

RSpec.describe PhoneVerification do
  fab!(:user) { Fabricate(:user, trust_level: TrustLevel[4]) }

  before do
    SiteSetting.phone_verification_enabled = true
    # Ensure trust level automatic groups exist
    Group.refresh_automatic_groups!
  end

  describe "user_anonymized event" do
    it "deletes the user's phone records" do
      PhoneVerification::UserPhoneRecord.create!(
        user: user,
        phone_number: "+14155552671",
        verified_at: Time.zone.now,
        active: true
      )

      UserAnonymizer.make_anonymous(user, Discourse.system_user)

      expect(PhoneVerification::UserPhoneRecord.where(user_id: user.id)).to be_empty
    end
  end

  describe "user_promoted event (demotion handling)" do
    it "triggers :user_removed_from_group for higher trust level groups when user is demoted" do
      tl4_group = Group.find_by(name: "trust_level_4")
      tl3_group = Group.find_by(name: "trust_level_3")
      tl2_group = Group.find_by(name: "trust_level_2")

      removed_groups = []
      event_listener =
        proc do |removed_user, group|
          removed_groups << group.name if removed_user.id == user.id
        end

      DiscourseEvent.on(:user_removed_from_group, &event_listener)

      begin
        DiscourseEvent.trigger(
          :user_promoted,
          user_id: user.id,
          old_trust_level: 4,
          new_trust_level: 1
        )

        expect(removed_groups).to contain_exactly(
          "trust_level_2",
          "trust_level_3",
          "trust_level_4"
        )
      ensure
        DiscourseEvent.off(:user_removed_from_group, &event_listener)
      end
    end

    it "does not trigger :user_removed_from_group when user is actually promoted" do
      removed_groups = []
      event_listener =
        proc do |removed_user, group|
          removed_groups << group.name if removed_user.id == user.id
        end

      DiscourseEvent.on(:user_removed_from_group, &event_listener)

      begin
        DiscourseEvent.trigger(
          :user_promoted,
          user_id: user.id,
          old_trust_level: 1,
          new_trust_level: 3
        )

        expect(removed_groups).to be_empty
      ensure
        DiscourseEvent.off(:user_removed_from_group, &event_listener)
      end
    end

    it "bypasses sync and event emission when phone_verification_enabled is false" do
      SiteSetting.phone_verification_enabled = false

      expect(PhoneVerification::GroupSyncService).not_to receive(:sync_user)

      removed_groups = []
      event_listener =
        proc do |removed_user, group|
          removed_groups << group.name if removed_user.id == user.id
        end

      DiscourseEvent.on(:user_removed_from_group, &event_listener)

      begin
        DiscourseEvent.trigger(
          :user_promoted,
          user_id: user.id,
          old_trust_level: 4,
          new_trust_level: 1
        )

        expect(removed_groups).to be_empty
      ensure
        DiscourseEvent.off(:user_removed_from_group, &event_listener)
      end
    end
  end

  describe "user_demoted, user_suspended, and user_unsuspended events" do
    it "does not call sync_user when phone_verification_enabled is false" do
      SiteSetting.phone_verification_enabled = false

      expect(PhoneVerification::GroupSyncService).not_to receive(:sync_user)

      DiscourseEvent.trigger(:user_demoted, user_id: user.id)
      DiscourseEvent.trigger(:user_suspended, user_id: user.id)
      DiscourseEvent.trigger(:user_unsuspended, user_id: user.id)
    end

    it "calls sync_user when phone_verification_enabled is true" do
      expect(PhoneVerification::GroupSyncService).to receive(:sync_user)
        .with(user)
        .exactly(3)
        .times

      DiscourseEvent.trigger(:user_demoted, user: user)
      DiscourseEvent.trigger(:user_suspended, user: user)
      DiscourseEvent.trigger(:user_unsuspended, user: user)
    end
  end
end
