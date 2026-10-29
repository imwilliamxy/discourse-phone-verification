# frozen_string_literal: true

module PhoneVerification
  class VerificationService
    COOLDOWN_SECONDS = 60
    MAX_FAILED_ATTEMPTS = 5

    def self.send_code(user:, phone_number:, ip_address: nil)
      new(user: user, ip_address: ip_address).send_code(phone_number)
    end

    def self.verify_code(user:, phone_number:, code:)
      new(user: user).verify_code(phone_number: phone_number, code: code)
    end

    def self.unbind(user:)
      new(user: user).unbind
    end

    def initialize(user:, ip_address: nil)
      @user = user
      @ip_address = ip_address
    end

    def send_code(raw_phone)
      min_trust_level =
        SiteSetting.phone_verification_send_code_min_trust_level.to_i
      if !@user.staff? && @user.trust_level < min_trust_level
        return(
          {
            success: false,
            error:
              I18n.t(
                "phone_verification.errors.trust_level_too_low",
                trust_level: min_trust_level
              )
          }
        )
      end

      formatted_phone = UserPhoneRecord.normalize(raw_phone)
      unless UserPhoneRecord.valid_us_phone?(formatted_phone)
        return(
          {
            success: false,
            error: I18n.t("phone_verification.errors.invalid_phone_number")
          }
        )
      end

      # Whether the number already belongs to another account is only reported
      # by verify_code, after the code proves the requester owns the number.
      # Reporting it here would let anyone probe who has a forum account.

      # Check disposable phone number blacklist (Layer 1)
      if DisposablePhoneChecker.disposable?(formatted_phone)
        return(
          {
            success: false,
            error: I18n.t("phone_verification.errors.disposable_phone_blocked")
          }
        )
      end

      # Take the cooldown atomically so concurrent requests can't all pass it
      cooldown_key = "phone_verification:cooldown:#{@user.id}"
      unless Discourse.redis.set(
               cooldown_key,
               "1",
               ex: COOLDOWN_SECONDS,
               nx: true
             )
        remaining_ttl = [Discourse.redis.ttl(cooldown_key), 1].max
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

      sent = false
      begin
        # Check daily limits (bypassed in debug mode)
        daily_limits = daily_limits_for(formatted_phone)
        limit_reached =
          daily_limits.any? do |key, limit|
            Discourse.redis.get(key).to_i >= limit
          end
        if limit_reached && !PhoneVerification.debug_mode?
          return(
            {
              success: false,
              error: I18n.t("phone_verification.errors.daily_limit_exceeded")
            }
          )
        end

        # Check VoIP / Landline line type intelligence (Layer 2)
        line_check = LineTypeChecker.check(formatted_phone)
        unless line_check[:allowed]
          return { success: false, error: line_check[:error] }
        end

        # Generate 6-digit OTP
        code = format("%06d", SecureRandom.random_number(1_000_000))
        expiry_minutes =
          SiteSetting.phone_verification_verification_code_expiry_minutes

        # Send SMS (skipped in debug mode)
        if PhoneVerification.debug_mode?
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

          # Provider errors can contain account IDs and IAM user names; the
          # providers already log the details, users only get a generic message.
          unless result.success?
            return(
              {
                success: false,
                error: I18n.t("phone_verification.errors.sms_send_failed")
              }
            )
          end
        end

        # Save to Redis
        code_key = "phone_verification:code:#{@user.id}"
        payload = { phone: formatted_phone, code: code, attempts: 0 }.to_json
        Discourse.redis.setex(code_key, expiry_minutes * 60, payload)

        # Increment daily counts
        unless PhoneVerification.debug_mode?
          daily_limits.each_key do |key|
            Discourse.redis.incr(key)
            Discourse.redis.expire(key, 86_400)
          end
        end

        sent = true
      ensure
        Discourse.redis.del(cooldown_key) unless sent
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

      # Reject disposable phone numbers even in verify step
      if DisposablePhoneChecker.disposable?(formatted_phone)
        return(
          {
            success: false,
            error: I18n.t("phone_verification.errors.disposable_phone_blocked")
          }
        )
      end

      cleaned_code = code.to_s.strip
      code_key = "phone_verification:code:#{@user.id}"

      if PhoneVerification.debug_mode?
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

      # The requester has proven they own the number, so it is now safe to
      # tell them it is already bound to another account.
      if UserPhoneRecord
           .where(phone_number: formatted_phone, active: true)
           .where.not(user_id: @user.id)
           .exists?
        return phone_already_used_result
      end

      record =
        begin
          UserPhoneRecord.transaction do
            # Deactivate any previous active record for this user
            UserPhoneRecord.where(user_id: @user.id, active: true).update_all(
              active: false
            )

            UserPhoneRecord.create!(
              user: @user,
              phone_number: formatted_phone,
              verified_at: Time.zone.now,
              active: true
            )
          end
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
          # Another account bound the same number concurrently
          return phone_already_used_result
        end

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

    private

    # Redis counter key => daily limit. Limits per account alone don't stop
    # SMS pumping from many fresh accounts, so the number, the IP and the
    # whole site are capped too.
    def daily_limits_for(formatted_phone)
      today = Time.zone.now.strftime("%Y%m%d")
      limits = {
        "phone_verification:daily:#{@user.id}:#{today}" =>
          SiteSetting.phone_verification_sms_daily_limit_per_user,
        "phone_verification:daily_phone:#{formatted_phone}:#{today}" =>
          SiteSetting.phone_verification_sms_daily_limit_per_phone,
        "phone_verification:daily_global:#{today}" =>
          SiteSetting.phone_verification_sms_daily_limit_global
      }
      if @ip_address.present?
        limits["phone_verification:daily_ip:#{@ip_address}:#{today}"] =
          SiteSetting.phone_verification_sms_daily_limit_per_ip
      end
      limits
    end

    def phone_already_used_result
      {
        success: false,
        error: I18n.t("phone_verification.errors.phone_already_used")
      }
    end
  end
end
