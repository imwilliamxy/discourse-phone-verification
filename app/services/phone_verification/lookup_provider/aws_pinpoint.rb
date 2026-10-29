# frozen_string_literal: true

require "aws-sigv4"
require "aws-sdk-core"
require "net/http"
require "uri"
require "json"

module PhoneVerification
  module LookupProvider
    class AwsPinpoint < Base
      def lookup(phone_number)
        region =
          SiteSetting.phone_verification_aws_region.to_s.strip.presence ||
            "us-east-1"
        credentials = resolve_credentials(region)

        unless credentials&.set?
          return(
            Result.new(
              success: false,
              error_message:
                "AWS credentials must be configured for Pinpoint Lookup."
            )
          )
        end

        endpoint =
          "https://pinpoint.#{region}.amazonaws.com/v1/phone/number/validate"
        uri = URI.parse(endpoint)
        body = {
          NumberValidateRequest: {
            IsoCountryCode: "US",
            PhoneNumber: phone_number
          }
        }.to_json

        signer =
          Aws::Sigv4::Signer.new(
            service: "mobiletargeting",
            region: region,
            credentials: credentials
          )

        signature =
          signer.sign_request(
            http_method: "POST",
            url: endpoint,
            headers: {
              "Content-Type" => "application/json"
            },
            body: body
          )

        request = FinalDestination::HTTP::Post.new(uri.request_uri)
        request["Content-Type"] = "application/json"
        signature.headers.each { |k, v| request[k] = v }
        request.body = body

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
          info = parsed["NumberValidateResponse"] || {}
          raw_type = info["PhoneType"].to_s.downcase.presence || "unknown"
          carrier_name = info["Carrier"]

          Result.new(
            success: true,
            line_type: raw_type,
            carrier_name: carrier_name
          )
        else
          error_msg =
            parsed["message"].presence ||
              "AWS Pinpoint Lookup failed with HTTP #{response.code}"
          Rails.logger.error(
            "[PhoneVerification] AWS Pinpoint Lookup error for #{UserPhoneRecord.mask(phone_number)} (HTTP #{response.code}): #{error_msg}"
          )
          Result.new(success: false, error_message: error_msg)
        end
      rescue StandardError => e
        Rails.logger.error(
          "[PhoneVerification] Unexpected AWS Pinpoint Lookup error for #{UserPhoneRecord.mask(phone_number)}: #{e.message}"
        )
        Result.new(success: false, error_message: e.message)
      end

      private

      def resolve_credentials(_region)
        if SiteSetting.phone_verification_aws_access_key_id.present? &&
             SiteSetting.phone_verification_aws_secret_access_key.present?
          Aws::Credentials.new(
            SiteSetting.phone_verification_aws_access_key_id.strip,
            SiteSetting.phone_verification_aws_secret_access_key.strip
          )
        else
          Aws::CredentialProviderChain.new.resolve
        end
      end
    end
  end
end
