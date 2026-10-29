# frozen_string_literal: true

require "rails_helper"

RSpec.describe Jobs::SendPhoneVerificationPrompt do
  fab!(:user) { Fabricate(:user, trust_level: TrustLevel[3]) }

  before do
    SiteSetting.phone_verification_enabled = true
    SiteSetting.phone_verification_min_trust_level = 3
    SiteSetting.phone_verification_prompt_pm_enabled = true
  end

  def prompts_for(recipient)
    Topic
      .private_messages_for_user(recipient)
      .where(subtype: TopicSubtype.system_message)
      .where(
        "title = ?",
        I18n.t(
          "system_messages.phone_verification_required.subject_template",
          trust_level: 3
        )
      )
  end

  it "sends one PM to an unverified user at the threshold" do
    2.times { described_class.new.execute(user_id: user.id) }

    expect(prompts_for(user).count).to eq(1)
    expect(prompts_for(user).first.first_post.raw).to include(
      "/my/preferences/account"
    )
  end

  it "skips users who already verified a phone number" do
    PhoneVerification::UserPhoneRecord.create!(
      user: user,
      phone_number: "+14155552671",
      verified_at: Time.zone.now,
      active: true
    )
    described_class.new.execute(user_id: user.id)
    expect(prompts_for(user)).to be_empty
  end

  it "does nothing when the setting is off" do
    SiteSetting.phone_verification_prompt_pm_enabled = false
    described_class.new.execute(user_id: user.id)
    expect(prompts_for(user)).to be_empty
  end

  it "does nothing for users below the threshold" do
    user.update!(trust_level: TrustLevel[2])
    described_class.new.execute(user_id: user.id)
    expect(prompts_for(user)).to be_empty
  end
end
