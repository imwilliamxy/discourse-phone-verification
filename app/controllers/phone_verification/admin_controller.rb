# frozen_string_literal: true

module PhoneVerification
  # Admin-only: phone numbers tie accounts to real people, so moderators get
  # neither the lookup nor the unbind, and every use is staff-logged.
  class AdminController < ::Admin::AdminController
    requires_plugin ::PhoneVerification::PLUGIN_NAME

    # Which accounts a number is (or was) bound to. Works from the HMAC, so
    # the number itself is never stored or logged.
    def lookup
      params.require(:phone_number)
      formatted = UserPhoneRecord.normalize(params[:phone_number])
      unless UserPhoneRecord.valid_us_phone?(formatted)
        raise Discourse::InvalidParameters.new(:phone_number)
      end

      records =
        UserPhoneRecord
          .with_phone(formatted)
          .includes(:user)
          .order(active: :desc, verified_at: :desc)
          .to_a
          .select(&:user)
      masked = UserPhoneRecord.mask(formatted)

      StaffActionLogger.new(current_user).log_custom(
        "phone_verification_lookup",
        phone: masked,
        results: records.map { |r| r.user.username }.join(", ").presence || "-"
      )

      render json: {
               phone_number_masked: masked,
               bindings:
                 records.map do |record|
                   {
                     user:
                       BasicUserSerializer.new(record.user, root: false).as_json,
                     active: record.active,
                     verified_at: record.verified_at
                   }
                 end
             }
    end

    def unbind
      user = User.find_by(id: params[:user_id])
      raise Discourse::NotFound unless user

      record = UserPhoneRecord.active.find_by(user_id: user.id)
      raise Discourse::NotFound unless record

      record.deactivate!
      GroupSyncService.sync_user(user)
      DiscourseEvent.trigger(:phone_verification_user_unbound, user)

      StaffActionLogger.new(current_user).log_custom(
        "phone_verification_unbind",
        username: user.username,
        phone: record.masked_phone_number
      )

      render json: success_json
    end
  end
end
