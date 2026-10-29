# frozen_string_literal: true

require "rails_helper"

RSpec.describe PhoneVerification::UserPhoneRecord, type: :model do
  fab!(:user)
  fab!(:user_two, :user)

  describe "validations and formatting" do
    it "normalizes US phone numbers into standard E.164 +1 format" do
      record =
        described_class.create!(
          user: user,
          phone_number: "(415) 555-2671",
          verified_at: Time.zone.now,
          active: true
        )
      expect(record.phone_number).to eq("+14155552671")
    end

    it "rejects invalid or non-+1 phone numbers" do
      record =
        described_class.new(
          user: user,
          phone_number: "+8613800000000",
          verified_at: Time.zone.now
        )
      expect(record.valid?).to be false
      expect(record.errors[:phone_number]).to be_present
    end

    it "enforces strict 1:1 active phone binding" do
      described_class.create!(
        user: user,
        phone_number: "+14155552671",
        verified_at: Time.zone.now,
        active: true
      )

      duplicate =
        described_class.new(
          user: user_two,
          phone_number: "+14155552671",
          verified_at: Time.zone.now,
          active: true
        )
      expect(duplicate.valid?).to be false
      expect(duplicate.errors[:phone_number]).to be_present
    end

    it "allows re-binding a phone number if the previous record is inactive (deactivated)" do
      old_record =
        described_class.create!(
          user: user,
          phone_number: "+14155552671",
          verified_at: Time.zone.now,
          active: true
        )
      old_record.deactivate!

      new_record =
        described_class.new(
          user: user_two,
          phone_number: "+14155552671",
          verified_at: Time.zone.now,
          active: true
        )
      expect(new_record.valid?).to be true
    end

    it "stores only an HMAC and the last 4 digits, never the number" do
      record =
        described_class.create!(
          user: user,
          phone_number: "(415) 555-2671",
          verified_at: Time.zone.now,
          active: true
        )

      row =
        DB.query(
          "SELECT phone_number, phone_number_hash, phone_number_last4 FROM user_phone_records WHERE id = ?",
          record.id
        ).first
      expect(row.phone_number).to be_nil
      expect(row.phone_number_last4).to eq("2671")
      expect(row.phone_number_hash).to eq(
        described_class.hash_phone_number("+14155552671")
      )
      expect(row.phone_number_hash).not_to include("4155552671")

      reloaded = described_class.find(record.id)
      expect(reloaded.phone_number).to be_nil
      expect(reloaded.masked_phone_number).to eq("+1 (***) ***-2671")
      expect(described_class.with_phone("+14155552671").first).to eq(reloaded)
    end

    it "can be deactivated after reload without the plaintext number" do
      record =
        described_class.create!(
          user: user,
          phone_number: "+14155552671",
          verified_at: Time.zone.now,
          active: true
        )
      described_class.find(record.id).deactivate!
      expect(record.reload.active).to be false
    end

    it "only accepts US area codes within +1" do
      expect(described_class.valid_us_phone?("+14155552671")).to be true
      expect(described_class.valid_us_phone?("+17875552671")).to be true # Puerto Rico

      expect(described_class.valid_us_phone?("+18765552671")).to be false # Jamaica
      expect(described_class.valid_us_phone?("+18095552671")).to be false # Dominican Republic
      expect(described_class.valid_us_phone?("+14165552671")).to be false # Toronto
      expect(described_class.valid_us_phone?("+19005552671")).to be false # premium rate
      expect(described_class.valid_us_phone?("+18005552671")).to be false # toll-free
      expect(described_class.valid_us_phone?("+14115552671")).to be false # N11
      expect(described_class.valid_us_phone?("+14915552671")).to be false # N9X reserved
      expect(described_class.valid_us_phone?("+14150552671")).to be false # exchange starts with 0
    end

    it "correctly produces masked phone format" do
      record = described_class.new(phone_number: "+14155552671")
      expect(record.masked_phone_number).to eq("+1 (***) ***-2671")
    end
  end
end
