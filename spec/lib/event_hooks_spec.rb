# frozen_string_literal: true

require "rails_helper"

RSpec.describe PhoneVerification do
  fab!(:user) { Fabricate(:user, trust_level: TrustLevel[4]) }

  before do
    SiteSetting.phone_verification_enabled = true
    # Ensure trust level automatic groups exist
    Group.refresh_automatic_groups!
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
  end
end
