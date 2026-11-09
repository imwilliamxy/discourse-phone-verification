# frozen_string_literal: true

class AddHmacKeyFingerprintToUserPhoneRecords < ActiveRecord::Migration[7.0]
  # Must match PhoneVerification::HmacKey
  FALLBACK_SALT = "phone_verification phone number hmac"
  FINGERPRINT_MESSAGE = "phone_verification key fingerprint"

  def up
    add_column :user_phone_records, :hmac_key_fingerprint, :string, limit: 16

    # Every existing row was hashed with the key derived from secret_key_base,
    # whatever key the container env provides from now on
    key = Rails.application.key_generator.generate_key(FALLBACK_SALT)
    fingerprint =
      OpenSSL::HMAC.hexdigest("SHA256", key, FINGERPRINT_MESSAGE)[0, 16]
    DB.exec(
      "UPDATE user_phone_records SET hmac_key_fingerprint = :fingerprint",
      fingerprint: fingerprint
    )
  end

  def down
    remove_column :user_phone_records, :hmac_key_fingerprint
  end
end
