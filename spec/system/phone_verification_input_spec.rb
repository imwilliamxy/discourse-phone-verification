# frozen_string_literal: true

RSpec.describe "Phone verification number input" do
  fab!(:user) { Fabricate(:user, trust_level: TrustLevel[1]) }

  let(:input) { find(".phone-input__number") }
  let(:send_button_disabled) { ".phone-verification-form .btn-primary[disabled]" }

  before do
    SiteSetting.phone_verification_enabled = true
    # In the test environment debug mode skips SMS and accepts any code
    SiteSetting.phone_verification_debug_mode = true
    sign_in(user)
    visit "/my/preferences/account"
  end

  it "keeps +1 fixed and formats the number while typing" do
    expect(page).to have_css(".phone-input__prefix", text: "+1")
    expect(page).to have_css(send_button_disabled)

    input.send_keys("415555")
    expect(input.value).to eq("(415) 555")
    expect(page).to have_css(send_button_disabled)

    input.send_keys("2671")
    expect(input.value).to eq("(415) 555-2671")
    expect(page).to have_no_css(send_button_disabled)

    input.send_keys("9", "a")
    expect(input.value).to eq("(415) 555-2671")
  end

  it "drops a typed or pasted country code" do
    input.send_keys("14155552671")
    expect(input.value).to eq("(415) 555-2671")

    input.fill_in(with: "+1 (415) 555-2671")
    expect(input.value).to eq("(415) 555-2671")
  end

  it "verifies the number entered without +1" do
    input.send_keys("4155552671")
    find(".phone-verification-form .btn-primary").click

    find(".phone-verification-form input[maxlength='6']").send_keys("123456")
    find(".phone-verification-form .btn-success").click

    expect(page).to have_css(".badge-verified", text: "2671")
    expect(
      PhoneVerification::UserPhoneRecord.active.with_phone("+14155552671").first.user_id
    ).to eq(user.id)
  end
end
