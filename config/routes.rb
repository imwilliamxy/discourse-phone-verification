# frozen_string_literal: true

PhoneVerification::Engine.routes.draw do
  get "status" => "phone_verification#status"
  post "send-code" => "phone_verification#send_code"
  post "verify-code" => "phone_verification#verify_code"
  post "unbind" => "phone_verification#unbind"

  get "admin/lookup" => "admin#lookup"
  delete "admin/users/:user_id" => "admin#unbind"
end

Discourse::Application.routes.draw do
  mount ::PhoneVerification::Engine, at: "/phone-verification"

  # Lets a direct load or refresh of the admin lookup tab render the app
  get "/admin/plugins/discourse-phone-verification/lookup" =>
        "admin/plugins#index",
      :constraints => AdminConstraint.new
end
