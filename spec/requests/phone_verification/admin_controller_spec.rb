# frozen_string_literal: true

require "rails_helper"

RSpec.describe PhoneVerification::AdminController, type: :request do
  fab!(:admin)
  fab!(:moderator)
  fab!(:user) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:previous_owner, :user)

  let(:phone) { "+14155552671" }

  before do
    SiteSetting.phone_verification_enabled = true
    PhoneVerification::UserPhoneRecord.create!(
      user: previous_owner,
      phone_number: phone,
      verified_at: 3.days.ago,
      active: false
    )
    PhoneVerification::UserPhoneRecord.create!(
      user: user,
      phone_number: phone,
      verified_at: Time.zone.now,
      active: true
    )
    PhoneVerification::GroupSyncService.sync_user(user)
  end

  describe "GET /phone-verification/admin/lookup" do
    it "lists current and previous accounts for the number and logs the lookup" do
      sign_in(admin)
      get "/phone-verification/admin/lookup.json",
          params: {
            phone_number: "(415) 555-2671"
          }

      expect(response.status).to eq(200)
      bindings = response.parsed_body["bindings"]
      expect(bindings.map { |b| [b["user"]["username"], b["active"]] }).to eq(
        [[user.username, true], [previous_owner.username, false]]
      )

      log = UserHistory.where(custom_type: "phone_verification_lookup").last
      expect(log.acting_user_id).to eq(admin.id)
      expect(log.details).to include("2671")
      expect(log.details).not_to include("4155552671")
    end

    it "returns no bindings for an unknown number" do
      sign_in(admin)
      get "/phone-verification/admin/lookup.json",
          params: {
            phone_number: "+12125550123"
          }
      expect(response.status).to eq(200)
      expect(response.parsed_body["bindings"]).to eq([])
    end

    it "rejects numbers that can't be bound" do
      sign_in(admin)
      get "/phone-verification/admin/lookup.json",
          params: {
            phone_number: "+18765552671"
          }
      expect(response.status).to eq(400)
    end

    it "is not available to moderators" do
      sign_in(moderator)
      get "/phone-verification/admin/lookup.json",
          params: {
            phone_number: phone
          }
      expect(response.status).to eq(403)
    end
  end

  describe "DELETE /phone-verification/admin/users/:user_id" do
    let(:group_name) { SiteSetting.phone_verification_group_name }

    it "unbinds the number, updates the group and logs it" do
      expect(user.groups.where(name: group_name)).to exist

      sign_in(admin)
      delete "/phone-verification/admin/users/#{user.id}.json"

      expect(response.status).to eq(200)
      expect(PhoneVerification::UserPhoneRecord.active.where(user_id: user.id)).to be_empty
      expect(user.reload.groups.where(name: group_name)).not_to exist

      log = UserHistory.where(custom_type: "phone_verification_unbind").last
      expect(log.details).to include(user.username)
      expect(log.details).not_to include("4155552671")
    end

    it "returns 404 when the user has no bound number" do
      sign_in(admin)
      delete "/phone-verification/admin/users/#{previous_owner.id}.json"
      expect(response.status).to eq(404)
    end

    it "is not available to moderators" do
      sign_in(moderator)
      delete "/phone-verification/admin/users/#{user.id}.json"
      expect(response.status).to eq(403)
      expect(PhoneVerification::UserPhoneRecord.active.where(user_id: user.id)).to exist
    end
  end
end
