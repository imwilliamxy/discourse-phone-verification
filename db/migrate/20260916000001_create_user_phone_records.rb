# frozen_string_literal: true

class CreateUserPhoneRecords < ActiveRecord::Migration[7.0]
  def change
    create_table :user_phone_records do |t|
      t.integer :user_id, null: false
      t.string :phone_number, limit: 32, null: false
      t.string :country_code, limit: 8, null: false, default: "+1"
      t.datetime :verified_at, null: false
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_foreign_key :user_phone_records,
                    :users,
                    column: :user_id,
                    on_delete: :cascade
    add_index :user_phone_records, :user_id
    add_index :user_phone_records,
              :user_id,
              unique: true,
              where: "active = TRUE",
              name: "idx_user_phone_records_unique_active_user"
    add_index :user_phone_records,
              :phone_number,
              unique: true,
              where: "active = TRUE",
              name: "idx_user_phone_records_unique_active_phone"
  end
end
