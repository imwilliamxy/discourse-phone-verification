# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module PhoneVerification
  module LookupProvider
    class TwilioLookup < Base
      LOOKUP_API_BASE = "https://lookups.twilio.com/v2/PhoneNumbers"

      def lookup(phone_number)
        account_sid =
          SiteSetting.phone_verification_twilio_account_sid.to_s.strip
        auth_token = SiteSetting.phone_verification_twilio_auth_token.to_s.strip

        if account_sid.blank? || auth_token.blank?
          return(
            Result.new(
              success: false,
              error_message:
                "Twilio Account SID and Auth Token must be configured for Lookup."
            )
          )
        end

        encoded_phone = URI.encode_www_form_component(phone_number)
        uri =
          URI.parse(
            "#{LOOKUP_API_BASE}/#{encoded_phone}?Fields=line_type_intelligence"
          )

        request = FinalDestination::HTTP::Get.new(uri.request_uri)
        request.basic_auth(account_sid, auth_token)

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
          intelligence = parsed["line_type_intelligence"] || {}
          sub_error = intelligence["error_code"]
          line_type = intelligence["type"]

          # Defensive guard against sub-package errors or unprovisioned account entitlements
          if sub_error.present? || line_type.blank?
            err_msg =
              "Twilio Lookup intelligence unavailable: #{sub_error.presence || 'missing line type'}"
            Rails.logger.warn(
              "[PhoneVerification] #{err_msg} for #{phone_number}"
            )
            return Result.new(success: false, error_message: err_msg)
          end

          carrier_name = intelligence["carrier_name"]

          Result.new(
            success: true,
            line_type: line_type,
            carrier_name: carrier_name
          )
        else
          error_msg =
            parsed["message"].presence ||
              "Twilio Lookup failed with HTTP #{response.code}"
          Rails.logger.error(
            "[PhoneVerification] Twilio Lookup error for #{phone_number} (HTTP #{response.code}): #{error_msg}"
          )
          Result.new(success: false, error_message: error_msg)
        end
      rescue StandardError => e
        Rails.logger.error(
          "[PhoneVerification] Unexpected Twilio Lookup error for #{phone_number}: #{e.message}"
        )
        Result.new(success: false, error_message: e.message)
      end
    end
  end
end
