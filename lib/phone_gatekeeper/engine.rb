# frozen_string_literal: true

module ::PhoneGatekeeper
  class Engine < ::Rails::Engine
    engine_name PLUGIN_NAME
    isolate_namespace PhoneGatekeeper
    config.autoload_paths << File.join(config.root, "lib")
  end
end
