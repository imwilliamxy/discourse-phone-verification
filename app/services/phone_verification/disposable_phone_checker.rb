# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module PhoneVerification
  class DisposablePhoneChecker
    REDIS_SET_KEY = "phone_verification:disposable_numbers"
    REDIS_TMP_KEY = "phone_verification:disposable_numbers:tmp"
    REDIS_SYNCED_AT_KEY = "phone_verification:disposable_numbers:synced_at"
    REDIS_COUNT_KEY = "phone_verification:disposable_numbers:count"
    REDIS_TTL_SECONDS = 7.days.to_i
    FALLBACK_URL =
      "https://raw.githubusercontent.com/iP1SMS/disposable-phone-numbers/master/number-list.json"
    BATCH_SIZE = 1000

    def self.disposable?(raw_phone)
      return false unless SiteSetting.phone_verification_block_disposable

      formatted = UserPhoneRecord.normalize(raw_phone)
      return false unless UserPhoneRecord.valid_us_phone?(formatted)

      digits = formatted.delete_prefix("+")

      return true if custom_blocked_digits.include?(digits)

      Discourse.redis.sismember(REDIS_SET_KEY, digits)
    end

    def self.clear_cache!
      Discourse.redis.del(
        REDIS_SET_KEY,
        REDIS_TMP_KEY,
        REDIS_SYNCED_AT_KEY,
        REDIS_COUNT_KEY
      )
    end

    def self.custom_blocked_digits
      raw_list = SiteSetting.phone_verification_custom_disposable_numbers.to_s
      return [] if raw_list.blank?

      raw_list
        .split("|")
        .filter_map do |item|
          norm = UserPhoneRecord.normalize(item)
          norm.delete_prefix("+") if UserPhoneRecord.valid_us_phone?(norm)
        end
    end

    def self.fetch_and_sync!
      primary_url =
        SiteSetting
          .phone_verification_disposable_list_url
          .to_s
          .strip
          .presence || FALLBACK_URL
      urls = [primary_url, FALLBACK_URL].uniq

      last_error = nil
      urls.each do |url|
        body = download_json(url)
        count = sync_from_json!(body)
        return { success: true, count: count, source: url }
      rescue StandardError => e
        last_error = e.message
        Rails.logger.warn(
          "[PhoneVerification] Failed to sync disposable numbers from #{url}: #{e.message}"
        )
      end

      { success: false, error: last_error }
    end

    def self.sync_from_json!(json_string)
      parsed = JSON.parse(json_string)
      raise ArgumentError, "Expected JSON object" unless parsed.is_a?(Hash)

      us_numbers =
        parsed.keys.select do |k|
          k.is_a?(String) && k.match?(/\A1[2-9]\d{9}\z/)
        end

      # An empty or broken remote list must not wipe the blocklist we have
      raise ArgumentError, "No US numbers in disposable list" if us_numbers.empty?

      # Build the new set under a temporary key and swap it in with RENAME,
      # so lookups never see an empty or half-filled set during a sync.
      Discourse.redis.del(REDIS_TMP_KEY)
      us_numbers.each_slice(BATCH_SIZE) do |batch|
        Discourse.redis.sadd(REDIS_TMP_KEY, batch)
      end
      # DiscourseRedis only namespaces the first key of RENAME
      Discourse.redis.rename(
        REDIS_TMP_KEY,
        Discourse.redis.namespace_key(REDIS_SET_KEY)
      )
      Discourse.redis.expire(REDIS_SET_KEY, REDIS_TTL_SECONDS)

      Discourse.redis.setex(
        REDIS_SYNCED_AT_KEY,
        REDIS_TTL_SECONDS,
        Time.zone.now.iso8601
      )
      Discourse.redis.setex(
        REDIS_COUNT_KEY,
        REDIS_TTL_SECONDS,
        us_numbers.size.to_s
      )

      us_numbers.size
    end

    def self.download_json(url)
      uri = URI.parse(url)
      request = FinalDestination::HTTP::Get.new(uri.request_uri)
      response =
        FinalDestination::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: uri.scheme == "https"
        ) do |http|
          http.read_timeout = 30
          http.open_timeout = 10
          http.request(request)
        end

      unless response.is_a?(Net::HTTPSuccess)
        raise "HTTP #{response.code} when fetching #{url}"
      end

      response.body
    end
    private_class_method :download_json
  end
end
