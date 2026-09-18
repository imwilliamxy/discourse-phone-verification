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

    it "correctly produces masked phone format" do
      record = described_class.new(phone_number: "+14155552671")
      expect(record.masked_phone_number).to eq("+1 (***) ***-2671")
    end
  end
end
