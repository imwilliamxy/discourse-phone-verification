# frozen_string_literal: true

module PhoneVerification
  module SmsProvider
    class Result
      attr_reader :success, :error_message, :message_id

      def initialize(success:, error_message: nil, message_id: nil)
        @success = success
        @error_message = error_message
        @message_id = message_id
      end

      def success?
        @success
      end
    end

    class Base
      def send_sms(to:, message:)
        raise NotImplementedError
      end
    end
  end
end
