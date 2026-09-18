# frozen_string_literal: true

# name: uscardforum-phone-verification
# about: US (+1) Phone SMS verification and Trust Level gated category access for Discourse
# version: 0.1.0
# authors: uscardforum
# url: https://github.com/uscardforum/uscardforum-phone-verification

enabled_site_setting :phone_verification_enabled

module ::PhoneVerification
  PLUGIN_NAME = "uscardforum-phone-verification"
end

require_relative "lib/phone_verification/engine"

after_initialize do
  require_relative "lib/phone_verification/site_settings_extension"
  SiteSettings::LabelFormatter.singleton_class.prepend(
    ::PhoneVerification::LocalizedLabelFormatter
  )
  SiteSetting.singleton_class.prepend(
    ::PhoneVerification::LocalizedSiteSettingExtension
  )

  require_relative "app/services/problem_check/phone_verification_missing_dynamic_groups"
  register_problem_check ProblemCheck::PhoneVerificationMissingDynamicGroups

  # Defensive reloader compatibility for dynamic groups during Rails code reloads
  ActiveSupport::Reloader.to_prepare do
    if defined?(::DiscourseDynamicGroups)
      unless Group.method_defined?(:get_depending_group_ids)
        class ::Group
          def get_depending_group_ids
            GroupCustomField.where(name: "depends_on_#{self.name.downcase}").pluck(:group_id)
          end
        end
      end

      unless Group.method_defined?(:evaluate_membership)
        class ::Group
          def evaluate_membership(user)
            return unless defined?(::DiscourseDynamicGroups::RuleEngine)
            engine = ::DiscourseDynamicGroups::RuleEngine.new
            membership = engine.evaluate_rule(user, dynamic_rule)
            is_member = GroupUser.where(user_id: user.id).where(group_id: self.id).exists?
            if is_member && !membership
              self.remove(user)
              false
            elsif !is_member && membership
              self.add(user)
              true
            end
          end
        end
      end

      unless Badge.method_defined?(:get_depending_group_ids)
        class ::Badge
          def get_depending_group_ids
            GroupCustomField.where(name: "depends_on_badge:#{self.id}").pluck(:group_id)
          end
        end
      end
    end
  end

  # Event hooks for Trust Level & account status changes
  on(:user_promoted) do |payload|
    next unless SiteSetting.phone_verification_enabled

    user = payload[:user] || User.find_by(id: payload[:user_id])
    if user
      PhoneVerification::GroupSyncService.sync_user(user)

      old_tl = payload[:old_trust_level]
      new_tl = payload[:new_trust_level]
      if old_tl && new_tl && new_tl < old_tl
        Group.user_trust_level_change!(user.id, new_tl)
        ((new_tl + 1)..old_tl).each do |tl|
          if (group = Group.find_by(name: "trust_level_#{tl}"))
            DiscourseEvent.trigger(:user_removed_from_group, user, group)
          end
        end
      end
    end
  end

  on(:user_demoted) do |payload|
    next unless SiteSetting.phone_verification_enabled

    user = payload[:user] || User.find_by(id: payload[:user_id])
    PhoneVerification::GroupSyncService.sync_user(user) if user
  end

  on(:user_suspended) do |payload|
    next unless SiteSetting.phone_verification_enabled

    user = payload[:user] || User.find_by(id: payload[:user_id])
    PhoneVerification::GroupSyncService.sync_user(user) if user
  end

  on(:user_unsuspended) do |payload|
    next unless SiteSetting.phone_verification_enabled

    user = payload[:user] || User.find_by(id: payload[:user_id])
    PhoneVerification::GroupSyncService.sync_user(user) if user
  end

  on(:site_setting_changed) do |name, _old_value, _new_value|
    if %i[
         phone_verification_enabled
         phone_verification_min_trust_level
         phone_verification_group_name
       ].include?(name.to_sym)
      PhoneVerification::GroupSyncService.sync_all
    end
  end

  # Staff serializer extension to view unmasked phone number
  add_to_serializer(:admin_detailed_user, :phone_verification_record) do
    record =
      PhoneVerification::UserPhoneRecord.find_by(
        user_id: object.id,
        active: true
      )
    return nil unless record

    {
      phone_number: record.phone_number,
      verified_at: record.verified_at,
      active: record.active
    }
  end

  # Site serializer extension to expose whether discourse-dynamic-groups is installed
  add_to_serializer(
    :site,
    :phone_verification_dynamic_groups_installed,
    respect_plugin_enabled: false
  ) { Discourse.plugins.any? { |p| p.name == "discourse-dynamic-groups" } }
end
