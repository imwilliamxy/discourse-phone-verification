# frozen_string_literal: true

module Jobs
  class SyncDisposablePhoneNumbers < ::Jobs::Scheduled
    every 1.day

    def execute(_args)
      return unless SiteSetting.phone_verification_enabled
      return unless SiteSetting.phone_verification_block_disposable

      result = PhoneVerification::DisposablePhoneChecker.fetch_and_sync!
      if result[:success]
        Rails.logger.info(
          "[PhoneVerification] Synced #{result[:count]} US disposable phone numbers from #{result[:source]}"
        )
      else
        Rails.logger.warn(
          "[PhoneVerification] Failed to sync disposable phone numbers: #{result[:error]}"
        )
      end
    end
  end
end
