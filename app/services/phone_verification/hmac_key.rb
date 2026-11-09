# frozen_string_literal: true

module PhoneVerification
  # The key behind the stored phone number hashes. It must stay the same for
  # the life of the site: if it changes, existing bindings stop matching, so
  # an already bound number can be bound to a second account and the admin
  # lookup no longer finds old bindings.
  #
  # Set DISCOURSE_PHONE_VERIFICATION_HMAC_KEY (32+ random characters) in the
  # container env. Without it the key is derived from secret_key_base, which
  # on a standard Docker install is generated and kept only in Redis unless
  # DISCOURSE_SECRET_KEY_BASE is set, so losing or moving Redis changes it.
  module HmacKey
    ENV_VAR = "DISCOURSE_PHONE_VERIFICATION_HMAC_KEY"
    # Used by every record created before the env key existed
    FALLBACK_SALT = "phone_verification phone number hmac"
    FINGERPRINT_MESSAGE = "phone_verification key fingerprint"

    def self.current
      configured || fallback
    end

    def self.configured
      ENV[ENV_VAR].to_s.strip.presence
    end

    def self.fallback
      Rails.application.key_generator.generate_key(FALLBACK_SALT)
    end

    # Identifies a key without revealing it; stored on each record so a key
    # change shows up as records whose fingerprint differs from the current one
    def self.fingerprint(key = current)
      OpenSSL::HMAC.hexdigest("SHA256", key, FINGERPRINT_MESSAGE)[0, 16]
    end
  end
end
