# frozen_string_literal: true

require "json"

module PhoneVerification
  class LineTypeChecker
    CACHE_KEY_PREFIX = "phone_verification:line_type:"

    def self.cache_key(formatted_phone)
      "#{CACHE_KEY_PREFIX}#{UserPhoneRecord.hash_phone_number(formatted_phone)}"
    end

    def self.check(raw_phone)
      return { allowed: true } unless SiteSetting.phone_verification_block_voip
      return { allowed: true } if PhoneVerification.debug_mode?

      formatted = UserPhoneRecord.normalize(raw_phone)
      key = cache_key(formatted)

      cached = Discourse.redis.get(key)
      if cached.present?
        begin
          data = JSON.parse(cached)
          return evaluate_line_type(data["line_type"])
        rescue JSON::ParserError
          Discourse.redis.del(key)
        end
      end

      provider = LookupProvider::Factory.get
      result = provider.lookup(formatted)

      unless result.success?
        return(
          {
            allowed: false,
            error: I18n.t("phone_verification.errors.lookup_failed")
          }
        )
      end

      ttl_days = [
        SiteSetting.phone_verification_lookup_cache_ttl_days.to_i,
        1
      ].max
      cache_payload = {
        line_type: result.line_type,
        carrier_name: result.carrier_name,
        checked_at: Time.zone.now.iso8601
      }.to_json
      Discourse.redis.setex(key, ttl_days * 86_400, cache_payload)

      evaluate_line_type(result.line_type)
    end

    def self.evaluate_line_type(line_type)
      if LookupProvider::Result::ALLOWED_LINE_TYPES.include?(line_type.to_s)
        { allowed: true, line_type: line_type }
      else
        {
          allowed: false,
          line_type: line_type,
          error: I18n.t("phone_verification.errors.voip_phone_blocked")
        }
      end
    end
    private_class_method :evaluate_line_type
  end
end
