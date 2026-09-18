# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module PhoneGatekeeper
  module SmsProvider
    class Twilio < Base
      TWILIO_API_BASE = "https://api.twilio.com/2010-04-01/Accounts"

      def send_sms(to:, message:)
        account_sid = SiteSetting.phone_gatekeeper_twilio_account_sid.to_s.strip
        auth_token = SiteSetting.phone_gatekeeper_twilio_auth_token.to_s.strip
        from_phone =
          SiteSetting.phone_gatekeeper_twilio_from_phone_number.to_s.strip
        messaging_service_sid =
          SiteSetting.phone_gatekeeper_twilio_messaging_service_sid.to_s.strip

        if account_sid.blank? || auth_token.blank?
          return(
            Result.new(
              success: false,
              error_message:
                "Twilio Account SID and Auth Token must be configured."
            )
          )
        end

        if from_phone.blank? && messaging_service_sid.blank?
          return(
            Result.new(
              success: false,
              error_message:
                "Twilio From Phone Number or Messaging Service SID must be configured."
            )
          )
        end

        uri = URI.parse("#{TWILIO_API_BASE}/#{account_sid}/Messages.json")
        request = FinalDestination::HTTP::Post.new(uri.request_uri)
        request.basic_auth(account_sid, auth_token)

        form_data = { "To" => to, "Body" => message }
        if messaging_service_sid.present?
          form_data["MessagingServiceSid"] = messaging_service_sid
        else
          form_data["From"] = from_phone
        end
        request.set_form_data(form_data)

        response =
          FinalDestination::HTTP.start(
            uri.host,
            uri.port,
            use_ssl: true
          ) do |http|
            http.read_timeout = 15
            http.open_timeout = 10
            http.request(request)
          end

        parsed =
          begin
            JSON.parse(response.body)
          rescue JSON::ParserError
            {}
          end

        if response.is_a?(Net::HTTPSuccess)
          Result.new(success: true, message_id: parsed["sid"])
        else
          error_msg =
            parsed["message"].presence ||
              "Twilio request failed with HTTP #{response.code}"
          Rails.logger.error(
            "[PhoneGatekeeper] Twilio SMS error sending to #{to} (HTTP #{response.code}): #{error_msg}"
          )
          Result.new(success: false, error_message: error_msg)
        end
      rescue StandardError => e
        Rails.logger.error(
          "[PhoneGatekeeper] Unexpected Twilio SMS error sending to #{to}: #{e.message}"
        )
        Result.new(success: false, error_message: e.message)
      end
    end
  end
end
