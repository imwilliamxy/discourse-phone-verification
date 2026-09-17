# frozen_string_literal: true

class ProblemCheck::PhoneGatekeeperMissingDynamicGroups < ProblemCheck
  self.priority = "low"

  def call
    return no_problem unless SiteSetting.phone_gatekeeper_enabled

    dynamic_groups_installed =
      Discourse.plugins.any? { |p| p.name == "discourse-dynamic-groups" }
    return no_problem if dynamic_groups_installed

    problem
  end
end
