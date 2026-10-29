# frozen_string_literal: true

# name: discourse-phone-verification
# about: US (+1) Phone SMS verification and Trust Level gated category access for Discourse
# version: 0.1.0
# authors: uscardforum
# url: https://github.com/imwilliamxy/discourse-phone-verification

enabled_site_setting :phone_verification_enabled

register_asset "stylesheets/phone-verification.scss"

register_svg_icon "mobile-screen"
register_svg_icon "shield-halved"
register_svg_icon "circle-info"
register_svg_icon "circle-check"

module ::PhoneVerification
  PLUGIN_NAME = "discourse-phone-verification"

  # Debug mode skips SMS and accepts any 6-digit code. On production it only
  # takes effect when the container env also opts in, so flipping the site
  # setting alone can never disable verification on a live site.
  def self.debug_mode?
    return false unless SiteSetting.phone_verification_debug_mode
    return true unless Rails.env.production?

    ENV["DISCOURSE_PHONE_VERIFICATION_ALLOW_DEBUG_MODE"].to_s == "true"
  end
end

require_relative "lib/phone_verification/engine"

# Keep phone numbers out of the request logs
Rails.application.config.filter_parameters += %i[phone_number]

after_initialize do
  add_admin_route "phone_verification.admin_page.title",
                  "discourse-phone-verification",
                  use_new_show_route: true

  require_relative "app/services/problem_check/phone_verification_missing_dynamic_groups"
  register_problem_check ProblemCheck::PhoneVerificationMissingDynamicGroups

  require_relative "app/jobs/scheduled/sync_disposable_phone_numbers"
  require_relative "app/jobs/regular/send_phone_verification_prompt"

  # Event hooks for Trust Level & account status changes
  on(:user_promoted) do |payload|
    next unless SiteSetting.phone_verification_enabled

    user = payload[:user] || User.find_by(id: payload[:user_id])
    if user
      PhoneVerification::GroupSyncService.sync_user(user)

      old_tl = payload[:old_trust_level]
      new_tl = payload[:new_trust_level]

      # Tell users who just crossed the threshold that they need to verify.
      # Runs as a job so a failure can't break the promotion itself.
      min_tl = SiteSetting.phone_verification_min_trust_level.to_i
      if SiteSetting.phone_verification_prompt_pm_enabled && old_tl && new_tl &&
           old_tl < min_tl && new_tl >= min_tl
        Jobs.enqueue(:send_phone_verification_prompt, user_id: user.id)
      end

      # Core drops trust level group memberships with delete_all on demotion,
      # which fires no user_removed_from_group events; dynamic groups need them.
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
    setting_sym = name.to_sym
    if %i[
         phone_verification_enabled
         phone_verification_min_trust_level
         phone_verification_group_name
       ].include?(setting_sym)
      PhoneVerification::GroupSyncService.sync_all
    end

    if %i[
         phone_verification_enabled
         phone_verification_block_disposable
       ].include?(setting_sym)
      if SiteSetting.phone_verification_enabled &&
           SiteSetting.phone_verification_block_disposable
        if Discourse
             .redis
             .scard(PhoneVerification::DisposablePhoneChecker::REDIS_SET_KEY)
             .to_i == 0
          Jobs.enqueue(:sync_disposable_phone_numbers)
        end
      else
        PhoneVerification::DisposablePhoneChecker.clear_cache!
      end
    end
  end

  # An anonymized account must not stay linked to a real phone number
  on(:user_anonymized) do |payload|
    user = payload[:user]
    next unless user

    PhoneVerification::UserPhoneRecord.where(user_id: user.id).delete_all
    PhoneVerification::GroupSyncService.sync_user(user)
  end

  # Staff see whether a user verified a phone; only the last 4 digits are
  # stored, so that is all they can see
  add_to_serializer(:admin_detailed_user, :phone_verification_record) do
    record =
      PhoneVerification::UserPhoneRecord.find_by(
        user_id: object.id,
        active: true
      )
    return nil unless record

    {
      phone_number_masked: record.masked_phone_number,
      verified_at: record.verified_at,
      active: record.active
    }
  end

  # Lets the banner hide itself once the current user has verified
  add_to_serializer(
    :current_user,
    :phone_verified,
    include_condition: -> { SiteSetting.phone_verification_banner_enabled }
  ) { PhoneVerification::UserPhoneRecord.active.exists?(user_id: object.id) }

  # Site serializer extension to expose whether discourse-dynamic-groups is installed
  add_to_serializer(
    :site,
    :phone_verification_dynamic_groups_installed,
    respect_plugin_enabled: false
  ) { Discourse.plugins.any? { |p| p.name == "discourse-dynamic-groups" } }
end
