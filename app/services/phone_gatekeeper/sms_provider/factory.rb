# frozen_string_literal: true

module PhoneGatekeeper
  module SmsProvider
    class Factory
      def self.get(provider_name = SiteSetting.phone_gatekeeper_sms_provider)
        case provider_name.to_s
        when "aws_sns"
          AwsSns.new
        else
          raise "Unknown SMS provider: #{provider_name}"
        end
      end
    end
  end
end
