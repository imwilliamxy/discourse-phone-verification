# frozen_string_literal: true

module PhoneVerification
  module SmsProvider
    class Factory
      def self.get(provider_name = SiteSetting.phone_verification_sms_provider)
        case provider_name.to_s
        when "aws_sns"
          AwsSns.new
        when "twilio"
          Twilio.new
        else
          raise "Unknown SMS provider: #{provider_name}"
        end
      end
    end
  end
end
