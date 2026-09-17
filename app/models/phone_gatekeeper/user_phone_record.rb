# frozen_string_literal: true

module PhoneGatekeeper
  class UserPhoneRecord < ::ActiveRecord::Base
    self.table_name = "user_phone_records"

    belongs_to :user

    validates :user_id, presence: true
    validates :phone_number, presence: true
    validates :verified_at, presence: true

    before_validation :normalize_phone_number
    validate :validate_us_phone_format
    validate :validate_uniqueness_when_active

    scope :active, -> { where(active: true) }

    def self.normalize(raw_phone)
      digits = raw_phone.to_s.gsub(/\D/, "")
      if digits.length == 10
        "+1#{digits}"
      elsif digits.length == 11 && digits.start_with?("1")
        "+#{digits}"
      else
        raw_phone.to_s.strip
      end
    end

    def self.valid_us_phone?(formatted_phone)
      !!(formatted_phone =~ /^\+1[2-9]\d{9}$/)
    end

    def deactivate!
      update!(active: false)
    end

    def masked_phone_number
      return "" if phone_number.blank?
      norm = self.class.normalize(phone_number)
      return norm unless norm =~ /^\+1(\d{3})(\d{3})(\d{4})$/
      "+1 (***) ***-#{$3}"
    end

    private

    def normalize_phone_number
      self.phone_number =
        self.class.normalize(phone_number) if phone_number.present?
    end

    def validate_us_phone_format
      return if phone_number.blank?
      unless self.class.valid_us_phone?(phone_number)
        errors.add(:phone_number, :invalid)
      end
    end

    def validate_uniqueness_when_active
      return unless active?

      if user_id.present?
        existing_user = self.class.where(user_id: user_id, active: true)
        existing_user = existing_user.where.not(id: id) if persisted?
        errors.add(:user_id, :taken) if existing_user.exists?
      end

      if phone_number.present?
        existing_phone =
          self.class.where(phone_number: phone_number, active: true)
        existing_phone = existing_phone.where.not(id: id) if persisted?
        errors.add(:phone_number, :taken) if existing_phone.exists?
      end
    end
  end
end
