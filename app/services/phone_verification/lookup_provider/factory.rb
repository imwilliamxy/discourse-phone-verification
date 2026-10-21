# frozen_string_literal: true

module PhoneVerification
  module LookupProvider
    class Factory
      def self.get
        case SiteSetting.phone_verification_sms_provider
        when "twilio"
          TwilioLookup.new
        when "aws_sns"
          AwsPinpoint.new
        else
          AwsPinpoint.new
        end
      end
    end
  end
end
