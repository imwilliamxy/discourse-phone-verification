# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProblemCheck::PhoneVerificationMissingDynamicGroups do
  let(:check) { described_class.new }

  context "when phone verification plugin is disabled" do
    before { SiteSetting.phone_verification_enabled = false }

    it "returns no problem" do
      expect(check.call).to be_nil
    end
  end

  context "when phone verification plugin is enabled" do
    before { SiteSetting.phone_verification_enabled = true }

    it "returns a problem when discourse-dynamic-groups is not installed" do
      allow(Discourse).to receive(:plugins).and_return([])
      result = check.call
      expect(result).to be_present
      expect(result.identifier).to eq(
        :phone_verification_missing_dynamic_groups
      )
    end

    it "returns no problem when discourse-dynamic-groups is installed" do
      fake_plugin =
        instance_double(Plugin::Instance, name: "discourse-dynamic-groups")
      allow(Discourse).to receive(:plugins).and_return([fake_plugin])
      expect(check.call).to be_nil
    end
  end
end
