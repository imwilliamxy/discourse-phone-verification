# frozen_string_literal: true

module PhoneVerification
  module LookupProvider
    class Result
      ALLOWED_LINE_TYPES = %w[mobile prepaid].freeze

      attr_reader :line_type, :carrier_name, :error_message

      def initialize(
        success:,
        line_type: nil,
        carrier_name: nil,
        error_message: nil
      )
        @success = success
        @line_type = line_type.to_s
        @carrier_name = carrier_name
        @error_message = error_message
      end

      def success?
        @success
      end

      def voip_or_unsupported?
        return false unless @success
        !ALLOWED_LINE_TYPES.include?(@line_type)
      end
    end

    class Base
      def lookup(_phone_number)
        raise NotImplementedError
      end
    end
  end
end
