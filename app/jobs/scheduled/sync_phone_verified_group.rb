# frozen_string_literal: true

module Jobs
  # Group membership is otherwise kept current by events, but some changes
  # fire none: a timed suspension simply runs out. A daily pass puts those
  # users back and removes anyone who no longer qualifies. Also enqueued when
  # a setting that changes who qualifies is saved, so the admin's request
  # doesn't have to walk every verified user.
  class SyncPhoneVerifiedGroup < ::Jobs::Scheduled
    every 1.day

    def execute(_args)
      return unless SiteSetting.phone_verification_enabled

      PhoneVerification::GroupSyncService.sync_all
    end
  end
end
