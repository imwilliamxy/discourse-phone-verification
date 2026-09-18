# frozen_string_literal: true

module PhoneVerification
  class VerificationService
    COOLDOWN_SECONDS = 60
    MAX_FAILED_ATTEMPTS = 5

    def self.send_code(user:, phone_number:)
      new(user: user).send_code(phone_number)
    end

    def self.verify_code(user:, phone_number:, code:)
      new(user: user).verify_code(phone_number: phone_number, code: code)
    end

    def self.unbind(user:)
      new(user: user).unbind
    end

    def initialize(user:)
      @user = user
    end

    def send_code(raw_phone)
      formatted_phone = UserPhoneRecord.normalize(raw_phone)
      unless UserPhoneRecord.valid_us_phone?(formatted_phone)
        return(
          {
            success: false,
            error: I18n.t("phone_verification.errors.invalid_phone_number")
          }
        )
      end

      # Check if phone is already taken by another active user
      if UserPhoneRecord
           .where(phone_number: formatted_phone, active: true)
           .where.not(user_id: @user.id)
           .exists?
        return(
          {
            success: false,
            error: I18n.t("phone_verification.errors.phone_already_used")
          }
        )
      end

      # Check cooldown
      cooldown_key = "phone_verification:cooldown:#{@user.id}"
      remaining_ttl = Discourse.redis.ttl(cooldown_key)
      if remaining_ttl > 0
        return(
          {
            success: false,
            error:
              I18n.t(
                "phone_verification.errors.cooldown_active",
                seconds: remaining_ttl
              )
          }
        )
      end

      # Check daily limits (bypassed in debug mode)
      unless SiteSetting.phone_verification_debug_mode
        today = Time.zone.now.strftime("%Y%m%d")
        user_daily_key = "phone_verification:daily:#{@user.id}:#{today}"
        current_user_count = Discourse.redis.get(user_daily_key).to_i
        limit = SiteSetting.phone_verification_sms_daily_limit_per_user

        if current_user_count >= limit
          return(
            {
              success: false,
              error: I18n.t("phone_verification.errors.daily_limit_exceeded")
            }
          )
        end
      end

      # Generate 6-digit OTP
      code = format("%06d", SecureRandom.random_number(1_000_000))
      expiry_minutes =
        SiteSetting.phone_verification_verification_code_expiry_minutes

      # Send SMS (skipped in debug mode)
      if SiteSetting.phone_verification_debug_mode
        Rails.logger.info(
          "[PhoneVerification DEBUG] Generated verification code #{code} for #{formatted_phone} (SMS sending skipped)"
        )
      else
        site_title = SiteSetting.title
        sms_text =
          I18n.t(
            "phone_verification.sms_message",
            site_title: site_title,
            code: code,
            expiry: expiry_minutes
          )

        provider = SmsProvider::Factory.get
        result = provider.send_sms(to: formatted_phone, message: sms_text)

        unless result.success?
          return { success: false, error: result.error_message }
        end
      end

      # Save to Redis
      code_key = "phone_verification:code:#{@user.id}"
      payload = { phone: formatted_phone, code: code, attempts: 0 }.to_json
      Discourse.redis.setex(code_key, expiry_minutes * 60, payload)

      # Set cooldown & increment daily count
      Discourse.redis.setex(cooldown_key, COOLDOWN_SECONDS, "1")
      unless SiteSetting.phone_verification_debug_mode
        today = Time.zone.now.strftime("%Y%m%d")
        user_daily_key = "phone_verification:daily:#{@user.id}:#{today}"
        Discourse.redis.incr(user_daily_key)
        Discourse.redis.expire(user_daily_key, 86_400)
      end

      { success: true, cooldown_seconds: COOLDOWN_SECONDS }
    end

    def verify_code(phone_number:, code:)
      formatted_phone = UserPhoneRecord.normalize(phone_number)
      unless UserPhoneRecord.valid_us_phone?(formatted_phone)
        return(
          {
            success: false,
            error: I18n.t("phone_verification.errors.invalid_phone_number")
          }
        )
      end

      # Check if phone is already taken by another active user
      if UserPhoneRecord
           .where(phone_number: formatted_phone, active: true)
           .where.not(user_id: @user.id)
           .exists?
        return(
          {
            success: false,
            error: I18n.t("phone_verification.errors.phone_already_used")
          }
        )
      end

      cleaned_code = code.to_s.strip
      code_key = "phone_verification:code:#{@user.id}"

      if SiteSetting.phone_verification_debug_mode
        # Debug mode: accept any 6-digit code without checking Redis cache
        unless cleaned_code =~ /^\d{6}$/
          return(
            {
              success: false,
              error: I18n.t("phone_verification.errors.invalid_code")
            }
          )
        end
        Discourse.redis.del(code_key)
      else
        # Production mode: strictly verify against Redis stored code & rate limits
        data = Discourse.redis.get(code_key)
        unless data
          return(
            {
              success: false,
              error: I18n.t("phone_verification.errors.invalid_code")
            }
          )
        end

        parsed = JSON.parse(data)
        stored_phone = parsed["phone"]
        stored_code = parsed["code"]
        attempts = parsed["attempts"].to_i

        if attempts >= MAX_FAILED_ATTEMPTS
          Discourse.redis.del(code_key)
          return(
            {
              success: false,
              error: I18n.t("phone_verification.errors.too_many_attempts")
            }
          )
        end

        if stored_phone != formatted_phone || stored_code != cleaned_code
          parsed["attempts"] = attempts + 1
          ttl = Discourse.redis.ttl(code_key)
          Discourse.redis.setex(code_key, [ttl, 1].max, parsed.to_json)
          return(
            {
              success: false,
              error: I18n.t("phone_verification.errors.invalid_code")
            }
          )
        end

        # Code is valid! Consume it.
        Discourse.redis.del(code_key)
      end

      # Deactivate any previous active record for this user
      UserPhoneRecord.where(user_id: @user.id, active: true).update_all(
        active: false
      )

      record =
        UserPhoneRecord.create!(
          user: @user,
          phone_number: formatted_phone,
          verified_at: Time.zone.now,
          active: true
        )

      # Trigger Group Sync & Events
      GroupSyncService.sync_user(@user)
      DiscourseEvent.trigger(:phone_verification_user_verified, @user, record)

      {
        success: true,
        phone_number_masked: record.masked_phone_number,
        verified_at: record.verified_at
      }
    end

    def unbind
      active_record = UserPhoneRecord.find_by(user_id: @user.id, active: true)
      unless active_record
        return(
          {
            success: false,
            error: I18n.t("phone_verification.errors.not_verified")
          }
        )
      end

      active_record.deactivate!
      GroupSyncService.sync_user(@user)
      DiscourseEvent.trigger(:phone_verification_user_unbound, @user)

      { success: true }
    end
  end
end
