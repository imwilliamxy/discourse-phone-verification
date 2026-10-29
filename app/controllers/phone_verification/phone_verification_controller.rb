# frozen_string_literal: true

module PhoneVerification
  class PhoneVerificationController < ::ApplicationController
    requires_plugin ::PhoneVerification::PLUGIN_NAME
    requires_login
    before_action :ensure_plugin_enabled

    def status
      record = UserPhoneRecord.find_by(user_id: current_user.id, active: true)
      group_name =
        SiteSetting.phone_verification_group_name.presence || "phone_verified"
      in_group = current_user.groups.where(name: group_name).exists?
      min_tl = SiteSetting.phone_verification_min_trust_level

      render json: {
               phone_verified: record.present?,
               phone_number_masked: record&.masked_phone_number || "",
               verified_at: record&.verified_at,
               in_gatekeeper_group: in_group,
               min_trust_level: min_tl,
               current_trust_level: current_user.trust_level
             }
    end

    def send_code
      params.require(:phone_number)
      result =
        VerificationService.send_code(
          user: current_user,
          phone_number: params[:phone_number],
          ip_address: request.remote_ip
        )

      if result[:success]
        render json: result
      else
        render_json_error(result[:error], status: 422)
      end
    end

    def verify_code
      params.require(%i[phone_number code])
      result =
        VerificationService.verify_code(
          user: current_user,
          phone_number: params[:phone_number],
          code: params[:code]
        )

      if result[:success]
        render json: result
      else
        render_json_error(result[:error], status: 422)
      end
    end

    def unbind
      result = VerificationService.unbind(user: current_user)
      if result[:success]
        render json: result
      else
        render_json_error(result[:error], status: 422)
      end
    end

    private

    def ensure_plugin_enabled
      raise Discourse::NotFound unless SiteSetting.phone_verification_enabled
    end
  end
end
