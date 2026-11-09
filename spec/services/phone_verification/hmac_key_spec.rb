# frozen_string_literal: true

require "rails_helper"

RSpec.describe PhoneVerification::HmacKey do
  fab!(:user)
  let(:phone) { "+14155552671" }
  let(:env_key) { "a" * 40 }

  after { ENV.delete(PhoneVerification::HmacKey::ENV_VAR) }

  def create_record(phone_number = phone, owner = user)
    PhoneVerification::UserPhoneRecord.create!(
      user: owner,
      phone_number: phone_number,
      verified_at: Time.zone.now,
      active: true
    )
  end

  it "keeps hashing with the secret_key_base-derived key when no env key is set" do
    legacy_key =
      Rails.application.key_generator.generate_key(
        "phone_verification phone number hmac"
      )
    expect(PhoneVerification::UserPhoneRecord.hash_phone_number(phone)).to eq(
      OpenSSL::HMAC.hexdigest("SHA256", legacy_key, phone)
    )
  end

  it "hashes with the env key once it is set and records which key was used" do
    fallback_hash = PhoneVerification::UserPhoneRecord.hash_phone_number(phone)
    ENV[described_class::ENV_VAR] = env_key

    record = create_record
    expect(record.phone_number_hash).not_to eq(fallback_hash)
    expect(record.phone_number_hash).to eq(
      OpenSSL::HMAC.hexdigest("SHA256", env_key, phone)
    )
    expect(record.hmac_key_fingerprint).to eq(
      described_class.fingerprint(env_key)
    )
    expect(record.hmac_key_fingerprint).not_to include(env_key)
  end

  describe ProblemCheck::PhoneVerificationHmacKey do
    subject(:check) { described_class.new }

    before { SiteSetting.phone_verification_enabled = true }

    it "is quiet when every binding matches the current key" do
      create_record
      expect(check.call).to be_nil
    end

    it "flags bindings hashed with a different key, which can be bound again" do
      create_record
      ENV[PhoneVerification::HmacKey::ENV_VAR] = env_key

      expect(check.call.message).to eq(
        I18n.t(
          "dashboard.problem.phone_verification_hmac_key_changed",
          base_path: Discourse.base_path,
          count: 1
        )
      )
    end

    it "asks production sites to pin the key in the container env" do
      allow(Rails.env).to receive(:production?).and_return(true)
      expect(check.call.message).to eq(
        I18n.t(
          "dashboard.problem.phone_verification_hmac_key_missing",
          base_path: Discourse.base_path
        )
      )

      # Pinning the current fallback key would leave existing bindings valid,
      # but any env key clears this warning
      ENV[PhoneVerification::HmacKey::ENV_VAR] = env_key
      expect(check.call).to be_nil
    end
  end
end
