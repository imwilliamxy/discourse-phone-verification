# frozen_string_literal: true

module PhoneVerification
  class UserPhoneRecord < ::ActiveRecord::Base
    self.table_name = "user_phone_records"
    # Plaintext numbers are no longer stored, see HashUserPhoneRecordNumbers
    self.ignored_columns = %w[phone_number]

    HMAC_SALT = "phone_verification phone number hmac"

    belongs_to :user

    validates :user_id, presence: true
    validates :phone_number, presence: true, on: :create
    validates :phone_number_hash, presence: true
    validates :verified_at, presence: true

    validate :validate_us_phone_format
    validate :validate_uniqueness_when_active

    scope :active, -> { where(active: true) }
    scope :with_phone,
          ->(formatted_phone) do
            where(phone_number_hash: hash_phone_number(formatted_phone))
          end

    # +1 also covers Canada, the Caribbean NANP countries (common SMS toll
    # fraud destinations), toll-free, premium-rate and non-geographic codes.
    # US territories (PR, USVI, Guam, NMI, American Samoa) stay allowed.
    NON_US_AREA_CODES = %w[
      204 226 236 249 250 257 263 289 306 343 354 365 367 368 382 387 403 416
      418 428 431 437 438 450 460 468 474 506 514 519 548 579 581 584 587 600
      604 613 622 633 639 644 647 655 672 677 683 688 705 709 742 753 778 780
      782 807 819 825 867 873 879 902 905 942
      242 246 264 268 284 345 441 473 649 658 664 721 758 767 784 809 829 849
      868 869 876
      800 822 833 844 855 866 877 880 881 882 883 884 885 886 887 888 889
      456 500 521 522 523 524 525 526 527 528 529 532 533 535 538 542 543 544
      545 546 547 549 550 552 553 554 556 558 566 569 577 578 588 589 700 710
      900
    ].to_set.freeze

    # Numbers are stored as an HMAC keyed off the site's secret_key_base plus
    # the last 4 digits, so a database dump or backup doesn't reveal them
    # (a plain hash of a 10-digit number is trivial to brute-force).
    # Changing secret_key_base means numbers bound before can be bound again.
    def self.hash_phone_number(formatted_phone)
      key = Rails.application.key_generator.generate_key(HMAC_SALT)
      OpenSSL::HMAC.hexdigest("SHA256", key, formatted_phone.to_s)
    end

    def self.mask(formatted_phone)
      digits = formatted_phone.to_s.gsub(/\D/, "")
      return "" if digits.length < 4
      "+1 (***) ***-#{digits[-4..]}"
    end

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
      match = formatted_phone.to_s.match(/\A\+1([2-9]\d{2})[2-9]\d{6}\z/)
      return false unless match

      area_code = match[1]
      # N9X area codes are reserved and N11 are service codes
      return false if area_code[1] == "9" || area_code.end_with?("11")

      NON_US_AREA_CODES.exclude?(area_code)
    end

    def deactivate!
      update!(active: false)
    end

    # Only set while binding a number; it is never written to the database
    attr_reader :phone_number

    def phone_number=(raw_phone)
      @phone_number = raw_phone.present? ? self.class.normalize(raw_phone) : nil
      self.phone_number_hash =
        @phone_number && self.class.hash_phone_number(@phone_number)
      self.phone_number_last4 = @phone_number && @phone_number[-4..]
    end

    def masked_phone_number
      return "" if phone_number_last4.blank?
      "+1 (***) ***-#{phone_number_last4}"
    end

    private

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

      if phone_number_hash.present?
        existing_phone =
          self.class.where(phone_number_hash: phone_number_hash, active: true)
        existing_phone = existing_phone.where.not(id: id) if persisted?
        errors.add(:phone_number, :taken) if existing_phone.exists?
      end
    end
  end
end
