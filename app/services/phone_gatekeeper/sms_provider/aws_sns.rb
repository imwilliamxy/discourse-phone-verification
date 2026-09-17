# frozen_string_literal: true

require "aws-sdk-sns"

module PhoneGatekeeper
  module SmsProvider
    class AwsSns < Base
      def send_sms(to:, message:)
        client = build_sns_client
        attributes = {
          "AWS.SNS.SMS.SMSType" => {
            data_type: "String",
            string_value: "Transactional"
          }
        }

        if SiteSetting.phone_gatekeeper_sms_sender_id.present?
          attributes["AWS.SNS.SMS.SenderID"] = {
            data_type: "String",
            string_value: SiteSetting.phone_gatekeeper_sms_sender_id
          }
        end

        response =
          client.publish(
            phone_number: to,
            message: message,
            message_attributes: attributes
          )

        Result.new(success: true, message_id: response.message_id)
      rescue Aws::SNS::Errors::ServiceError => e
        Rails.logger.error(
          "[PhoneGatekeeper] AWS SNS error sending to #{to}: #{e.message}"
        )
        Result.new(success: false, error_message: e.message)
      rescue StandardError => e
        Rails.logger.error(
          "[PhoneGatekeeper] Unexpected error sending SMS to #{to}: #{e.message}"
        )
        Result.new(success: false, error_message: e.message)
      end

      private

      def build_sns_client
        options = {
          region:
            SiteSetting.phone_gatekeeper_aws_region.presence || "us-east-1"
        }

        if SiteSetting.phone_gatekeeper_aws_access_key_id.present? &&
             SiteSetting.phone_gatekeeper_aws_secret_access_key.present?
          options[:credentials] = Aws::Credentials.new(
            SiteSetting.phone_gatekeeper_aws_access_key_id,
            SiteSetting.phone_gatekeeper_aws_secret_access_key
          )
        end

        Aws::SNS::Client.new(options)
      end
    end
  end
end
