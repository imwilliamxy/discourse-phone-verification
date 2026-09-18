# frozen_string_literal: true

PhoneVerification::Engine.routes.draw do
  get "status" => "phone_verification#status"
  post "send-code" => "phone_verification#send_code"
  post "verify-code" => "phone_verification#verify_code"
  post "unbind" => "phone_verification#unbind"
end

Discourse::Application.routes.draw do
  mount ::PhoneVerification::Engine, at: "/phone-verification"
end
