# frozen_string_literal: true

module ::PhoneVerification
  class Engine < ::Rails::Engine
    engine_name PLUGIN_NAME
    isolate_namespace PhoneVerification
    config.autoload_paths << File.join(config.root, "lib")
  end
end
