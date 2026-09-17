# frozen_string_literal: true

# name: uscardforum-phone-gatekeeper
# about: US (+1) Phone SMS verification and Trust Level gated category access for Discourse
# version: 0.1.0
# authors: uscardforum
# url: https://github.com/uscardforum/uscardforum-phone-gatekeeper

enabled_site_setting :phone_gatekeeper_enabled

module ::PhoneGatekeeper
  PLUGIN_NAME = "uscardforum-phone-gatekeeper"
end

require_relative "lib/phone_gatekeeper/engine"

after_initialize do
  # Event hooks for Trust Level & account status changes
  on(:user_promoted) do |payload|
    user = payload[:user] || User.find_by(id: payload[:user_id])
    PhoneGatekeeper::GroupSyncService.sync_user(user) if user
  end

  on(:user_demoted) do |payload|
    user = payload[:user] || User.find_by(id: payload[:user_id])
    PhoneGatekeeper::GroupSyncService.sync_user(user) if user
  end

  on(:user_suspended) do |payload|
    user = payload[:user] || User.find_by(id: payload[:user_id])
    PhoneGatekeeper::GroupSyncService.sync_user(user) if user
  end

  on(:user_unsuspended) do |payload|
    user = payload[:user] || User.find_by(id: payload[:user_id])
    PhoneGatekeeper::GroupSyncService.sync_user(user) if user
  end

  # Staff serializer extension to view unmasked phone number
  add_to_serializer(:admin_detailed_user, :phone_gatekeeper_record) do
    record =
      PhoneGatekeeper::UserPhoneRecord.find_by(user_id: object.id, active: true)
    return nil unless record

    {
      phone_number: record.phone_number,
      verified_at: record.verified_at,
      active: record.active
    }
  end
end
