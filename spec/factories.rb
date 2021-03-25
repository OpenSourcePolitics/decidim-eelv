# frozen_string_literal: true

require "decidim/core/test/factories"

# Factories

# require "decidim/participatory_processes/test/factories"
# require "decidim/proposals/test/factories"
# require "decidim/meetings/test/factories"
# require "decidim/accountability/test/factories"
require "decidim/system/test/factories"

FactoryBot.modify do
  factory :user, class: "Decidim::User" do
    email { generate(:email) }
    password { "password1234" }
    password_confirmation { password }
    name { generate(:name) }
    nickname { generate(:nickname) }
    organization
    locale { organization.default_locale }
    tos_agreement { "1" }
    avatar { Decidim::Dev.test_file("avatar.jpg", "image/jpeg") }
    personal_url { Faker::Internet.url }
    about { "<script>alert(\"ABOUT\");</script>" + Faker::Lorem.paragraph(2) }
    confirmation_sent_at { Time.current }
    accepted_tos_version { organization.tos_version }
    email_on_notification { true }
    registration_metadata {}

    trait :confirmed do
      confirmed_at { Time.current }
    end

    trait :deleted do
      email { "" }
      deleted_at { Time.current }
    end

    trait :admin_terms_accepted do
      admin_terms_accepted_at { Time.current }
    end

    trait :admin do
      admin { true }
      admin_terms_accepted
    end

    trait :user_manager do
      roles { ["user_manager"] }
      admin_terms_accepted
    end

    trait :managed do
      email { "" }
      password { "" }
      password_confirmation { "" }
      encrypted_password { "" }
      managed { true }
    end

    trait :officialized do
      officialized_at { Time.current }
      officialized_as { generate_localized_title }
    end
  end
end
