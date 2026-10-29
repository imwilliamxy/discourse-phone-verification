# frozen_string_literal: true

RSpec.describe "Phone verification banner" do
  fab!(:user) { Fabricate(:user, trust_level: TrustLevel[3]) }

  before do
    SiteSetting.phone_verification_enabled = true
    SiteSetting.phone_verification_min_trust_level = 3
    SiteSetting.phone_verification_banner_enabled = true
    SiteSetting.phone_verification_banner_until =
      1.month.from_now.to_date.iso8601
  end

  it "shows the banner to an unverified user until dismissed" do
    SiteSetting.default_locale = "zh_CN"
    sign_in(user)
    visit "/"

    expect(page).to have_css(".phone-verification-banner")
    expect(page).to have_css(
      ".phone-verification-banner__verify[href$='/my/preferences/account']"
    )
    # The plugin stylesheet is loaded
    expect(
      page.evaluate_script(
        "getComputedStyle(document.querySelector('.phone-verification-banner')).borderTopLeftRadius"
      )
    ).to eq("8px")

    find(".phone-verification-banner__dismiss").click
    expect(page).to have_no_css(".phone-verification-banner")

    visit "/"
    expect(page).to have_no_css(".phone-verification-banner")

    visit "/my/preferences/account"
    expect(page).to have_css(".phone-verification-section")
  end

  it "shows on mobile", mobile: true do
    SiteSetting.default_locale = "zh_CN"
    sign_in(user)
    visit "/"

    expect(page).to have_css(".phone-verification-banner")
  end

  it "renders the promotion PM" do
    SiteSetting.default_locale = "zh_CN"
    SiteSetting.phone_verification_prompt_pm_enabled = true
    Jobs::SendPhoneVerificationPrompt.new.execute(user_id: user.id)
    pm =
      Topic
        .private_messages_for_user(user)
        .where(subtype: TopicSubtype.system_message)
        .last

    sign_in(user)
    visit pm.relative_url

    expect(page).to have_css(
      ".cooked a[href$='/my/preferences/account']"
    )
  end

  it "uses the custom text when set" do
    SiteSetting.phone_verification_banner_text =
      "From Dec 1 the Platinum Lounge requires a verified phone number."
    sign_in(user)
    visit "/"

    expect(page).to have_css(
      ".phone-verification-banner",
      text: "From Dec 1 the Platinum Lounge requires a verified phone number."
    )
  end

  it "is hidden after the end date" do
    SiteSetting.phone_verification_banner_until =
      1.day.ago.to_date.iso8601
    sign_in(user)
    visit "/"
    expect(page).to have_no_css(".phone-verification-banner")
  end

  it "is hidden for users below the minimum trust level" do
    user.update!(trust_level: TrustLevel[2])
    sign_in(user)
    visit "/"
    expect(page).to have_no_css(".phone-verification-banner")
  end

  it "is hidden for users who already verified" do
    PhoneVerification::UserPhoneRecord.create!(
      user: user,
      phone_number: "+14155552671",
      verified_at: Time.zone.now,
      active: true
    )
    sign_in(user)
    visit "/"
    expect(page).to have_no_css(".phone-verification-banner")
  end
end
