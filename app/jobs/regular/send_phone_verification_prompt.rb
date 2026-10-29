# frozen_string_literal: true

module Jobs
  class SendPhoneVerificationPrompt < ::Jobs::Base
    PROMPTED_FIELD = "phone_verification_prompted_at"

    def execute(args)
      return unless SiteSetting.phone_verification_enabled
      return unless SiteSetting.phone_verification_prompt_pm_enabled

      user = User.find_by(id: args[:user_id])
      return if user.blank? || user.bot? || user.staged? || user.suspended?

      min_trust_level = SiteSetting.phone_verification_min_trust_level.to_i
      return if user.trust_level < min_trust_level
      return if PhoneVerification::UserPhoneRecord.active.exists?(user_id: user.id)
      # Users who drop below and climb back over the threshold get it only once
      return if user.custom_fields[PROMPTED_FIELD].present?

      SystemMessage.create_from_system_user(
        user,
        :phone_verification_required,
        trust_level: min_trust_level,
        verify_url: "#{Discourse.base_url}/my/preferences/account"
      )

      user.custom_fields[PROMPTED_FIELD] = Time.zone.now.iso8601
      user.save_custom_fields
    end
  end
end
