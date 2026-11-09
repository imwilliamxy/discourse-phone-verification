# frozen_string_literal: true

# Warns when the phone number hashing key isn't pinned in the container env,
# or when bound numbers were hashed with a different key than the current one
# (they can no longer be matched, so they can be bound again elsewhere).
class ProblemCheck::PhoneVerificationHmacKey < ProblemCheck
  self.priority = "high"

  def call
    return no_problem unless SiteSetting.phone_verification_enabled

    stale =
      PhoneVerification::UserPhoneRecord
        .active
        .where.not(
          hmac_key_fingerprint: PhoneVerification::HmacKey.fingerprint
        )
        .or(
          PhoneVerification::UserPhoneRecord.active.where(
            hmac_key_fingerprint: nil
          )
        )
        .count
    if stale > 0
      return(
        problem(
          override_key: "dashboard.problem.phone_verification_hmac_key_changed",
          override_data: {
            count: stale
          }
        )
      )
    end

    if Rails.env.production? && PhoneVerification::HmacKey.configured.nil?
      return(
        problem(
          override_key: "dashboard.problem.phone_verification_hmac_key_missing"
        )
      )
    end

    no_problem
  end
end
