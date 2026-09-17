# frozen_string_literal: true

PhoneGatekeeper::Engine.routes.draw do
  get "status" => "phone_gatekeeper#status"
  post "send-code" => "phone_gatekeeper#send_code"
  post "verify-code" => "phone_gatekeeper#verify_code"
  post "unbind" => "phone_gatekeeper#unbind"
end

Discourse::Application.routes.draw do
  mount ::PhoneGatekeeper::Engine, at: "/phone-gatekeeper"
end
