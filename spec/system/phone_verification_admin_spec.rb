# frozen_string_literal: true

RSpec.describe "Phone verification admin tools" do
  fab!(:admin)
  fab!(:user) { Fabricate(:user, trust_level: TrustLevel[1]) }

  before do
    SiteSetting.phone_verification_enabled = true
    PhoneVerification::UserPhoneRecord.create!(
      user: user,
      phone_number: "+14155552671",
      verified_at: Time.zone.now,
      active: true
    )
    sign_in(admin)
  end

  it "finds an account by phone number from the plugin page" do
    visit "/admin/plugins/discourse-phone-verification"
    expect(page).to have_css(
      "a[href$='/admin/plugins/discourse-phone-verification/lookup']"
    )

    visit "/admin/plugins/discourse-phone-verification/lookup"
    find(".phone-verification-lookup .phone-input__number").send_keys(
      "4155552671"
    )
    find(".phone-verification-lookup__search").click

    expect(page).to have_css(
      ".phone-verification-lookup__results a",
      text: user.username
    )
  end

  it "says so when no account matches" do
    visit "/admin/plugins/discourse-phone-verification/lookup"
    find(".phone-verification-lookup .phone-input__number").send_keys(
      "2125550123"
    )
    find(".phone-verification-lookup__search").click

    expect(page).to have_css(".phone-verification-lookup__empty")
  end

  it "unbinds a number from the admin user page" do
    visit "/admin/users/#{user.id}/#{user.username}"
    find(".phone-verification-admin-unbind").click
    find(".dialog-footer .btn-primary").click

    expect(page).to have_no_css(".phone-verification-admin-unbind")
    expect(
      PhoneVerification::UserPhoneRecord.active.where(user_id: user.id)
    ).to be_empty
  end
end
