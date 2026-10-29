# frozen_string_literal: true

module PhoneVerification
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
