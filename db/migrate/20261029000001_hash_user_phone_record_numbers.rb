# frozen_string_literal: true

class HashUserPhoneRecordNumbers < ActiveRecord::Migration[7.0]
  # Must match PhoneVerification::UserPhoneRecord::HMAC_SALT
  HMAC_SALT = "phone_verification phone number hmac"

  def up
    add_column :user_phone_records, :phone_number_hash, :string, limit: 64
    add_column :user_phone_records, :phone_number_last4, :string, limit: 4

    key = Rails.application.key_generator.generate_key(HMAC_SALT)
    DB
      .query(
        "SELECT id, phone_number FROM user_phone_records WHERE phone_number IS NOT NULL"
      )
      .each do |row|
        DB.exec(
          "UPDATE user_phone_records SET phone_number_hash = :hash, phone_number_last4 = :last4 WHERE id = :id",
          id: row.id,
          hash: OpenSSL::HMAC.hexdigest("SHA256", key, row.phone_number),
          last4: row.phone_number[-4..]
        )
      end

    change_column_null :user_phone_records, :phone_number, true
    execute "UPDATE user_phone_records SET phone_number = NULL"
    change_column_null :user_phone_records, :phone_number_hash, false

    remove_index :user_phone_records,
                 name: "idx_user_phone_records_unique_active_phone"
    add_index :user_phone_records,
              :phone_number_hash,
              unique: true,
              where: "active = TRUE",
              name: "idx_user_phone_records_unique_active_phone_hash"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
