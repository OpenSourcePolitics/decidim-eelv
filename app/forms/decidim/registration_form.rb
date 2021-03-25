# frozen_string_literal: true

module Decidim
  # A form object used to handle user registrations
  class RegistrationForm < Form
    include JsonbAttributes

    mimic :user

    attribute :name, String
    attribute :nickname, String
    attribute :email, String
    attribute :password, String
    attribute :password_confirmation, String
    attribute :newsletter, Boolean
    attribute :tos_agreement, Boolean
    attribute :current_locale, String
    jsonb_attribute :registration_metadata, [
      [:gender, String],
      [:birth_date, Integer],
      [:residence_department, String],
      [:motivations, String],
      [:primary_participation, String]
    ]

    validates :name, presence: true
    validates :nickname, presence: true, format: /\A[\w\-]+\z/, length: { maximum: Decidim::User.nickname_max_length }
    validates :email, presence: true, 'valid_email_2/email': { disposable: true }
    validates :password, confirmation: true
    validates :password, password: { name: :name, email: :email, username: :nickname }
    validates :password_confirmation, presence: true
    validates :tos_agreement, allow_nil: false, acceptance: true

    validate :email_unique_in_organization
    validate :nickname_unique_in_organization
    validate :no_pending_invitations_exist

    def newsletter_at
      return nil unless newsletter?

      Time.current
    end

    def gender_for_metadata
      [
        I18n.t("male", scope: "decidim.devise.registrations.new.registration_metadata"),
        I18n.t("female", scope: "decidim.devise.registrations.new.registration_metadata"),
        I18n.t("other", scope: "decidim.devise.registrations.new.registration_metadata")
      ]
    end

    def birth_date_for_metadata
      (Time.current.year - 100..Time.current.year).to_a.reverse
    end

    def residence_department_for_metadata
      I18n.t("residence_departments", scope: "decidim.devise.registrations.new.registration_metadata")
    end

    private

    def email_unique_in_organization
      errors.add :email, :taken if User.no_active_invitation.find_by(email: email, organization: current_organization).present?
    end

    def nickname_unique_in_organization
      errors.add :nickname, :taken if User.no_active_invitation.find_by(nickname: nickname, organization: current_organization).present?
    end

    def no_pending_invitations_exist
      errors.add :base, I18n.t("devise.failure.invited") if User.has_pending_invitations?(current_organization.id, email)
    end
  end
end
