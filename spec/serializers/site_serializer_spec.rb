# frozen_string_literal: true

require "rails_helper"

RSpec.describe SiteSerializer do
  let(:guardian) { Guardian.new }
  let(:site) { Site.new(guardian) }
  let(:serializer) { described_class.new(site, scope: guardian, root: false) }

  describe "phone_verification_dynamic_groups_installed attribute" do
    it "returns true when discourse-dynamic-groups plugin is installed" do
      fake_plugin =
        instance_double(Plugin::Instance, name: "discourse-dynamic-groups")
      allow(Discourse).to receive(:plugins).and_return([fake_plugin])

      json = serializer.as_json
      expect(json[:phone_verification_dynamic_groups_installed]).to eq(true)
    end

    it "returns false when discourse-dynamic-groups plugin is not installed" do
      allow(Discourse).to receive(:plugins).and_return([])

      json = serializer.as_json
      expect(json[:phone_verification_dynamic_groups_installed]).to eq(false)
    end
  end
end
