# @class User
#
# @responsibility  A user that can log in.  Knows membership _payment_ status,
#  application status.
#
# FIXME only the class RequirementsForMembership should respond to questions
#   about whether a user is current member. (Ex: RequirementsForMembership.requirements_met?({ user: approved_and_paid }) )
#
# 2021-02-19: First step towards refactoring: have existing methods call MembershipsManager methods
#   (a kind of manual delegation).
#   TODO: should any of the methods be delegated to the MembershipsManager?
#   Next steps will be to call MembershipManager methods directly where needed.
#
class User < ApplicationRecord
  include PaymentUtility
  include ImagesUtility
  include AASM

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable

  before_destroy :adjust_related_info_for_destroy

  after_update :clear_proof_of_membership_jpg_cache,
               if: Proc.new { saved_change_to_member_photo_file_name? ||
                 saved_change_to_first_name? ||
                 saved_change_to_last_name? ||
                 saved_change_to_membership_number? }


  has_one :shf_application, dependent: :destroy
  accepts_nested_attributes_for :shf_application, update_only: true

  has_many :uploaded_files
  accepts_nested_attributes_for :uploaded_files, allow_destroy: true

  has_many :companies, through: :shf_application

  has_many :memberships, dependent: :destroy

  has_many :payments, dependent: :nullify
  # ^^ need to retain h-branding payment(s) for any associated company that
  #    is not also deleted.
  accepts_nested_attributes_for :payments

  has_many :checklists, dependent: :destroy, class_name: 'UserChecklist'

  has_attached_file :member_photo, default_url: 'photo_unavailable.png',
                    styles: { standard: ['130x130#'] }, default_style: :standard

  validates_attachment_content_type :member_photo,
                                    content_type: /\Aimage\/.*(jpg|jpeg|png)\z/
  validates_attachment_file_name :member_photo, matches: [/png\z/, /jpe?g\z/, /PNG\z/, /JPE?G\z/]

  validates :first_name, :last_name, presence: true, unless: :updating_without_name_changes
  validates :membership_number, uniqueness: true, allow_blank: true
  # validates :membership_status, inclusion: %w(not_a_member, current_member, in_grace_period, former_member)

  THIS_PAYMENT_TYPE = Payment::PAYMENT_TYPE_MEMBER
  MOST_RECENT_UPLOAD_METHOD = :created_at

  scope :admins, -> { where(admin: true) }
  scope :not_admins, -> { where(admin: nil).or(User.where(admin: false)) }

  # FIXME: this is not accurate; DO NOT USE. (Need to carefully remove any use.)  Other checks may need to be done.
  scope :members, -> { where(member: true) }

  successful_payment_with_type_and_expire_date = "payments.status = '#{Payment::SUCCESSFUL}' AND" +
    " payments.payment_type = ? AND payments.expire_date = ?"

  scope :membership_expires_in_x_days, -> (num_days) { includes(:payments)
                                                         .where(successful_payment_with_type_and_expire_date,
                                                                Payment::PAYMENT_TYPE_MEMBER,
                                                                (Date.current + num_days))
                                                         .order('payments.expire_date')
                                                         .references(:payments) }

  scope :company_hbrand_expires_in_x_days, -> (num_days) { includes(:payments)
                                                             .where(successful_payment_with_type_and_expire_date,
                                                                    Payment::PAYMENT_TYPE_BRANDING,
                                                                    (Date.current + num_days))
                                                             .order('payments.expire_date')
                                                             .references(:payments) }

  scope :application_accepted, -> { joins(:shf_application).where(shf_applications: { state: 'accepted' }) }

  scope :membership_payment_current, -> { joins(:payments).where("payments.status = '#{Payment::SUCCESSFUL}' AND payments.payment_type = ? AND  payments.expire_date > ?", Payment::PAYMENT_TYPE_MEMBER, Date.current) }

  scope :agreed_to_membership_guidelines, -> { where(id: UserChecklist.top_level_for_current_membership_guidelines.completed.pluck(:user_id)) }

  scope :current_members, -> { application_accepted.membership_payment_current }


  # ===============================================================================================

  # TODO this should not be the responsibility of the User class. Need a MembershipManager class for this.
  # The next membership payment date
  def self.next_membership_payment_date(user_id)
    next_membership_payment_dates(user_id).first
  end

  # TODO this should not be the responsibility of the User class. Need a MembershipManager class for this.
  def self.next_membership_payment_dates(user_id)
    next_payment_dates(user_id, THIS_PAYMENT_TYPE)
  end

  def self.clear_all_proof_of_membership_jpg_caches
    all.each do |user|
      user.clear_proof_of_membership_jpg_cache
    end
  end


  def self.most_recent_upload_method
    MOST_RECENT_UPLOAD_METHOD
  end


  # ----------------------------------------------------------------------------------------------
  # Act As State Machine (AASM)

  aasm column: 'membership_status' do
    state :not_a_member, initial: true
    state :current_member
    state :in_grace_period
    state :former_member

    after_all_transitions :set_membership_changed_info

    # You can pass the (keyword) argument date: <Date> to provide a date that the membership should start on
    event :start_membership do
      transitions from: [:not_a_member, :current_member, :former_member], to: :current_member, after:  Proc.new {|*args| start_membership_on(*args) }
    end

    # You can pass the (keyword) argument date: <Date> to provide a date that the membership should start on
    event :renew do
      transitions from: [:current_member, :in_grace_period], to: :current_member, after: Proc.new {|*args| renew_membership_on(*args) }
    end

    event :start_grace_period do
      transitions from: :current_member, to: :in_grace_period, after: :enter_grace_period
    end

    event :make_former_member do
      transitions from: :in_grace_period, to: :former_member, after: :become_former_member
    end
  end

  # This can be used to write info to logs
  def set_membership_changed_info
    @membership_changed_info = "membership status changed from #{aasm.from_state} to #{aasm.to_state} (event: #{aasm.current_event})"
  end

  def membership_changed_info
    @membership_changed_info ||= ''
  end

  # ----------------------------------------------------------------------------------

  def memberships_manager
    @memberships_manager ||= MembershipsManager.new
  end

  # @return [nil | Members] - the oldest membership that covers today (Date.current)
  #   nil if no memberships are found
  def current_membership
    memberships_manager.membership_on(self, Date.current)
  end


  def cache_key(type)
    "user_#{id}_cache_#{type}"
  end

  def proof_of_membership_jpg
    Rails.cache.read(cache_key('pom'))
  end

  def proof_of_membership_jpg=(image)
    Rails.cache.write(cache_key('pom'), image)
  end

  def clear_proof_of_membership_jpg_cache
    Rails.cache.delete(cache_key('pom'))
  end

  def updating_without_name_changes
    # Not a new record and not saving changes to either first or last name

    # https://github.com/rails/rails/pull/25337#issuecomment-225166796
    # ^^ Useful background

    !new_record? && !(will_save_change_to_attribute?('first_name') ||
      will_save_change_to_attribute?('last_name'))
  end

  def most_recent_membership_payment
    most_recent_payment(THIS_PAYMENT_TYPE)
  end

  # Make this a current member.
  # Do nothing if the user is already a current member.
  # If not a current member, start a membership
  def make_current_member
    start_membership_on(date: Date.current) unless current_member?
  end


  def start_membership_on(date: Date.current)
    # TODO membership number?
    # TODO: what if they are a current_member and the last day > the date?
    #   end the current membership on (date - 1 day) and start the new one on the date?
    new_membership = new_membership_starting(date)
    # TODO send email for starting membership?
  end


  def renew_membership_on(date: Date.current)
    # TODO: what if they are a current_member and the last day > the date?
    #   end the current membership on (date - 1 day) and start the new one on the date?
    new_membership = new_membership_starting(date)
    # TODO send email for renewed membership?
  end

  def new_membership_starting(first_day)
    Membership.new(user: self).set_first_day_and_last(first_day: first_day)
  end

  def enter_grace_period
    # TODO send email for enter_grace_period (renewal overdue!)?
  end


  def become_former_member
    # TODO send email?
  end


  # TODO this should not be the responsibility of the User class. Need a MembershipManager class for this.
  # FIXME change calls to either payment_start_date or current_membership.first_day
  def membership_start_date
    payment_start_date(THIS_PAYMENT_TYPE)
  end

  # TODO this should not be the responsibility of the User class. Need a MembershipManager class for this.
  # FIXME what if no payment has been made?
  # FIXME change calls to either payment_start_date or current_membership.last_day
  def membership_expire_date
    payment_expire_date(THIS_PAYMENT_TYPE)
  end

  # TODO this should not be the responsibility of the User class. Need a MembershipManager class for this.
  # FIXME change calls to either payment_notes or current_membership.notes
  def membership_payment_notes
    payment_notes(THIS_PAYMENT_TYPE)
  end


  # # Return the current membership status for the User
  # # TODO this belongs in a Membership -type class
  # # @return [Symbol] - status of the membership:
  # #   :not_a_member, :current, :in_grace_period, :past_member
  # #   also include :expires_soon if include_expires_soon is true
  # def membership_status(date = Date.current, include_expires_soon: true, use_payments: self.payments)
  #   date = Date.current if date.nil?
  #   return membership_status_including_current_or_expires_soon(date,
  #                                                              include_expires_soon: include_expires_soon,
  #                                                              use_payments: self.payments) if payments_current_as_of?(date, use_payments)
  #   return :in_grace_period if membership_expired_in_grace_period?(date)
  #   return :past_member if payment_term_expired? # FIXME - must be able to query this for a specific date
  #
  #   :not_a_member
  # end


  def member_in_good_standing?(date = Date.current)
    RequirementsForMembership.requirements_met?(user: self, date: date)
  end


  # TODO this should not be the responsibility of the User class. Need a MembershipManager class for this.
  # FIXME - this is ONLY about the payments, not the membership status as a whole.
  #   so the name should be changed.  ex: membership_payments_current?  or membership_payment_term....
  def membership_current?
    # TODO can use term_expired?(THIS_PAYMENT_TYPE)
    !!membership_expire_date&.future? # using '!!' will turn a nil into false
  end

  alias_method :payments_current?, :membership_current?


  # TODO this should not be the responsibility of the User class. Need a MembershipManager class for this.
  # FIXME - this is ONLY about the payments, not the membership status as a whole.
  #   so the name should be changed.  ex: membership_payments_current_as_of?
  def membership_current_as_of?(this_date)
    return false if this_date.nil?

    membership_payment_expire_date = membership_expire_date
    !membership_payment_expire_date.nil? && (membership_payment_expire_date > this_date)
  end
  alias_method :payments_current_as_of?, :membership_current_as_of?



  # The membership term has expired, but are they still within a 'grace period'?
  def membership_expired_in_grace_period?(this_date = Date.current)
    memberships_manager.membership_in_grace_period?(self, this_date)
  end

  # the date is after the renewal grace period;
  def membership_past_grace_period_end?(this_date = Date.current)
    memberships_manager.date_after_grace_period_end?(self, this_date)
  end

  # FIXME: MembershipManager membership_expired_in_grace_period? means this is no longer used
  # def date_within_grace_period?(this_date = Date.current,
  #                               start_date = membership_expire_date,
  #                               grace_period = membership_expired_grace_period)
  #   memberships_manager.date_in_grace_period?(this_date,
  #                                             last_day: start_date,
  #                                             grace_days: grace_period )
  # end
  #
  # def membership_expired_grace_period
  #   memberships_manager.grace_period
  # end

  # @return [ActiveSupport::Duration]
  # def days_can_renew_early
  #   memberships_manager.days_can_renew_early
  # end


  def today_is_valid_renewal_date?
    memberships_manager.today_is_valid_renewal_date?(self)
  end


  def valid_date_for_renewal?(this_date = Date.current)
    memberships_manager.valid_renewal_date?(self, this_date)
  end

  # User has an approved membership application and
  # is up to date (current) on membership payments
  # FIXME: does not seem to be used
  def membership_app_and_payments_current?
    has_approved_shf_application? && membership_current?
  end

  # User has an approved membership application and
  # is up to date (current) on membership payments
  # FIXME: does not seem to be used
  def membership_app_and_payments_current_as_of?(this_date)
    has_approved_shf_application? && membership_current_as_of?(this_date)
  end

  # Business rule: user can pay membership fee if:
  # 1. the user is not the admin (an admin cannot make a payment for a member or user)
  #      AND
  # 2. the user is a current member OR user was a current member and is still in the grace period for renewing)
  #       and they are allowed to pay the renewal membership fee
  #    OR
  #    the user has is allowed to pay the new membership fee
  #
  def allowed_to_pay_member_fee?
    return false if admin?

    if current_member? || in_grace_period?
      allowed_to_pay_renewal_member_fee?
    else
      allowed_to_pay_new_membership_fee?
    end
  end

  # A user can pay a renewal membership fee if
  #   they are a current member OR are within the renewal grace period
  #   AND they have met all of the requirements for renewing,
  #     excluding any payment required.
  def allowed_to_pay_renewal_member_fee?
    return false if admin?

    (current_member? || in_grace_period?) &&
      RequirementsForRenewal.requirements_excluding_payments_met?(self)
  end

  # A user can pay a (new) membership fee if:
  #   they are not a member OR they are a former member
  #   AND they have met all of the requirements for membership,
  #     excluding any payment required.
  def allowed_to_pay_new_membership_fee?
    return false if admin?

    (not_a_member? || former_member?) &&
      RequirementsForMembership.requirements_excluding_payments_met?(self)
  end

  # Business rule: user can pay h-brand license fee if:
  # 1. user is an admin
  # OR
  # 2. user is a member AND user is in the company
  #
  # TODO this should not be the responsibility of the User class. Need a MembershipManager class for this.
  #
  # @return [Boolean]
  def allowed_to_pay_hbrand_fee?(company)
    admin? || in_company?(company) #|| has_approved_app_for_company?(company)
  end

  def member_fee_payment_due?
    # FIXME: should member? be used here?
    member? && !membership_current?
  end

  def has_shf_application?
    shf_application&.valid?
  end

  def has_approved_shf_application?
    shf_application&.accepted?
  end

  def member_or_admin?
    admin? || member?
  end

  def in_company?(company)
    in_company_numbered?(company.company_number)
  end

  def in_company_numbered?(company_num)
    member? && has_approved_app_for_company_number?(company_num)
  end

  def has_approved_app_for_company?(company)
    has_approved_app_for_company_number?(company.company_number)
  end

  def has_approved_app_for_company_number?(company_num)
    has_app_for_company_number?(company_num) && apps_for_company_number(company_num).first.accepted?
  end

  def has_app_for_company?(company)
    has_app_for_company_number?(company.company_number)
  end

  def has_app_for_company_number?(company_num)
    apps_for_company_number(company_num)&.any?
  end

  # @return [Array] all shf_applications that contain the company, sorted by the application with the expire_date furthest in the future
  def apps_for_company(company)
    apps_for_company_number(company.company_number)
  end

  # @return [Array] all shf_applications that contain a company with the company_num, sorted by the application with the expire_date furthest in the future
  #   Note that right now a User can have only 1 ShfApplication, but in the future
  #   if a User can have more than 1, we want to be sure they are sorted by expire_date with the
  #    expire_date in the future as the first one and the expire_date in the past as the last one
  def apps_for_company_number(company_num)
    result = shf_application&.companies&.find_by(company_number: company_num)
    result.nil? ? [] : [shf_application].sort(&sort_apps_by_when_approved)
  end

  SORT_BY_MOST_RECENT_APPROVED_DATE = lambda { |app1, app2| app2.when_approved <=> app1.when_approved }

  # @return [Lambda] - the block (lambda) to use to sort shf_applications by the when_approved date
  def sort_apps_by_when_approved
    SORT_BY_MOST_RECENT_APPROVED_DATE
  end

  def membership_guidelines_checklist_done?
    RequirementsForMembership.membership_guidelines_checklist_done?(self)
  end

  def full_name
    "#{first_name} #{last_name}"
  end

  def has_full_name?
    first_name.present? && last_name.present?
  end

  ransacker :padded_membership_number do
    Arel.sql("lpad(membership_number, 20, '0')")
  end

  def get_short_proof_of_membership_url(url)
    found = self.short_proof_of_membership_url
    return found if found
    short_url = ShortenUrl.short(url)
    if short_url
      self.update_attribute(:short_proof_of_membership_url, short_url)
      short_url
    else
      url
    end
  end

  def membership_packet_sent?
    !date_membership_packet_sent.nil?
  end

  # Toggle whether or not a membership package was sent to this user.
  #
  # If the old value was "true", now set it to false.
  # If the old value was "false", now make it true and set the date sent
  #
  # @param date_sent [Time] - when the packet was sent. default = now
  # @return [Boolean] - result of updating :date_membership_packet_sent
  def toggle_membership_packet_status(date_sent = Time.zone.now)
    new_sent_time = membership_packet_sent? ? nil : date_sent
    update(date_membership_packet_sent: new_sent_time)
  end


  # TODO this doesn't belong in User.  but not sure yet where it does belong.
  def file_uploaded_during_this_membership_term?
    return false unless current_member? || in_grace_period?

    if current_member?
      file_uploaded_on_or_after?(current_membership.first_day)
    else
      # is in_grace_period
      file_uploaded_on_or_after?(memberships_manager.most_recent_membership(self).first_day)
    end
  end


  def file_uploaded_on_or_after?(the_date = Date.current)
    return false if uploaded_files.blank?

    most_recent_uploaded_file.send(most_recent_upload_method) >= the_date
  end

  def most_recent_uploaded_file
    uploaded_files.order(most_recent_upload_method)&.last
  end

  def most_recent_upload_method
    self.class.most_recent_upload_method
  end

  # The fact that this can no longer be private is a smell that it should be refactored out into a separate class
  def issue_membership_number
    self.membership_number = self.membership_number.blank? ? get_next_membership_number : self.membership_number
  end

  def adjust_related_info_for_destroy
    remove_photo_from_filesystem
    record_deleted_payorinfo_in_payment_notes(self.class, email)
    MembershipsManager.create_archived_memberships_for(self)
    destroy_uploaded_files
  end

  # ===============================================================================================
  private

  # TODO this should not be the responsibility of the User class. Need a MembershipManager class for this.
  def get_next_membership_number
    self.class.connection.execute("SELECT nextval('membership_number_seq')").getvalue(0, 0).to_s
  end

  # remove the associated member photo from the file system by setting it to nil
  def remove_photo_from_filesystem
    member_photo = nil
  end

  def destroy_uploaded_files
    uploaded_files.each do |uploaded_file|
      uploaded_file.actual_file = nil
      uploaded_file.destroy
    end
    save
  end

end
