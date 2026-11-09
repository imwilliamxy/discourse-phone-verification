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

      # Everything past this point can cost money (a paid line-type lookup,
      # then the SMS), so the request takes one unit of every daily limit up
      # front and keeps the cooldown whatever the outcome. Only a request
      # turned away by the limits themselves, which spends nothing, gets its
      # cooldown back.
      unless reserve_daily_quota(formatted_phone)
        Discourse.redis.del(cooldown_key)
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
          "[PhoneVerification DEBUG] Generated verification code #{code} for #{UserPhoneRecord.mask(formatted_phone)} (SMS sending skipped)"
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

      # Save to Redis; a new code gets a fresh attempt budget
      code_key = "phone_verification:code:#{@user.id}"
      payload = { phone: formatted_phone, code: code }.to_json
      Discourse.redis.setex(code_key, expiry_minutes * 60, payload)
      Discourse.redis.del(attempts_key_for(@user))

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
        stored_code = parsed["code"].to_s

        # Count every attempt with an atomic INCR before comparing, so
        # parallel requests can't each read the same counter and get extra
        # guesses at the code.
        attempts_key = attempts_key_for(@user)
        attempts = Discourse.redis.incr(attempts_key)
        if attempts == 1
          Discourse.redis.expire(
            attempts_key,
            [Discourse.redis.ttl(code_key), 1].max
          )
        end

        if attempts > MAX_FAILED_ATTEMPTS
          Discourse.redis.del(code_key, attempts_key)
          return(
            {
              success: false,
              error: I18n.t("phone_verification.errors.too_many_attempts")
            }
          )
        end

        if stored_phone != formatted_phone ||
             !ActiveSupport::SecurityUtils.secure_compare(
               stored_code,
               cleaned_code
             )
          return(
            {
              success: false,
              error: I18n.t("phone_verification.errors.invalid_code")
            }
          )
        end

        # Code is valid! Consume it.
        Discourse.redis.del(code_key, attempts_key)
      end

      # The requester has proven they own the number, so it is now safe to
      # tell them it is already bound to another account.
      if UserPhoneRecord
           .active
           .with_phone(formatted_phone)
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

    # Takes one unit of every daily limit, or none if any limit is used up.
    # INCR returns the new count atomically, so concurrent requests can't all
    # read the same count and slip under a limit together; a request that
    # would go over gives back what it took. Debug mode has no limits.
    def reserve_daily_quota(formatted_phone)
      return true if PhoneVerification.debug_mode?

      taken =
        daily_limits_for(formatted_phone).map do |key, limit|
          count = Discourse.redis.incr(key)
          Discourse.redis.expire(key, 86_400)
          [key, count <= limit]
        end
      return true if taken.all? { |_key, within_limit| within_limit }

      taken.each { |key, _within_limit| Discourse.redis.decr(key) }
      false
    end

    # Redis counter key => daily limit. Limits per account alone don't stop
    # SMS pumping from many fresh accounts, so the number, the IP and the
    # whole site are capped too.
    def daily_limits_for(formatted_phone)
      today = Time.zone.now.strftime("%Y%m%d")
      phone_hash = UserPhoneRecord.hash_phone_number(formatted_phone)
      limits = {
        "phone_verification:daily:#{@user.id}:#{today}" =>
          SiteSetting.phone_verification_sms_daily_limit_per_user,
        "phone_verification:daily_phone:#{phone_hash}:#{today}" =>
          SiteSetting.phone_verification_sms_daily_limit_per_phone,
        "phone_verification:daily_global:#{today}" =>
          SiteSetting.phone_verification_sms_daily_limit_global
      }
      if (ip_bucket = self.class.ip_bucket(@ip_address))
        limits["phone_verification:daily_ip:#{ip_bucket}:#{today}"] =
          SiteSetting.phone_verification_sms_daily_limit_per_ip
      end
      limits
    end

    # One IPv6 subscriber usually gets a whole /64, so counting exact IPv6
    # addresses would let one machine rotate through billions of them.
    def self.ip_bucket(ip_address)
      return nil if ip_address.blank?

      addr = IPAddr.new(ip_address.to_s)
      addr = addr.native if addr.ipv4_mapped?
      addr.ipv6? ? "#{addr.mask(64)}/64" : addr.to_s
    rescue IPAddr::InvalidAddressError
      ip_address.to_s
    end

    def attempts_key_for(user)
      "phone_verification:attempts:#{user.id}"
    end

    def phone_already_used_result
      {
        success: false,
        error: I18n.t("phone_verification.errors.phone_already_used")
      }
    end
  end
end
