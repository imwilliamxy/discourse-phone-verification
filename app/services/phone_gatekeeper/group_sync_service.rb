# frozen_string_literal: true

module PhoneGatekeeper
  class GroupSyncService
    def self.sync_user(user)
      new(user).sync
    end

    def self.sync_all
      return unless SiteSetting.phone_gatekeeper_enabled

      group = find_or_create_target_group
      return unless group

      active_user_ids =
        UserPhoneRecord.where(active: true).pluck(:user_id).uniq

      User.where(id: active_user_ids).find_each { |user| sync_user(user) }

      group.users.find_each do |user|
        sync_user(user) if active_user_ids.exclude?(user.id)
      end
    end

    def self.find_or_create_target_group
      group_name =
        SiteSetting.phone_gatekeeper_group_name.presence || "phone_verified"
      Group.find_by(name: group_name) ||
        Group.create!(
          name: group_name,
          visibility_level: Group.visibility_levels[:staff],
          public_admission: false,
          primary_group: false
        )
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error(
        "[PhoneGatekeeper] Error ensuring group #{group_name}: #{e.message}"
      )
      nil
    end

    def initialize(user)
      @user = user
    end

    def sync
      return unless @user && !@user.anonymous?
      return unless SiteSetting.phone_gatekeeper_enabled

      group = find_or_create_target_group
      return unless group

      if eligible?
        group.add(@user) if group.users.exclude?(@user)
      elsif group.users.include?(@user)
        group.remove(@user)
      end
    end

    def eligible?
      return false if @user.suspended?
      if @user.trust_level < SiteSetting.phone_gatekeeper_min_trust_level
        return false
      end

      UserPhoneRecord.where(user_id: @user.id, active: true).exists?
    end

    private

    def find_or_create_target_group
      self.class.find_or_create_target_group
    end
  end
end
