# frozen_string_literal: true

require "spec_helper"

module Decidim
  describe User do
    subject { user }

    let(:gender) { "Female" }
    let(:birth_date) { 1946 }
    let(:residence_department) { 0o1 }
    let(:motivations) { "Explanation" }
    let(:primary_participation) { "1" }
    let(:registration_metadata) do
      {
        gender: gender,
        birth_date: birth_date,
        residence_department: residence_department,
        motivations: motivations,
        primary_participation: primary_participation
      }
    end
    let(:organization) { create(:organization) }
    let(:user) { build(:user, registration_metadata: registration_metadata, organization: organization) }

    include_examples "resourceable"

    it { is_expected.to be_valid }

    it "overwrites the log presenter" do
      expect(described_class.log_presenter_class_for(:foo))
        .to eq Decidim::AdminLog::UserPresenter
    end

    it "has an association for identities" do
      expect(subject.identities).to eq([])
    end

    it "has an association for user groups" do
      user_group = create(:user_group)
      create(:user_group_membership, user: subject, user_group: user_group)
      expect(subject.user_groups).to eq([user_group])
    end

    describe "name" do
      context "when it has a name" do
        let(:user) { build(:user, name: "Oriol") }

        it "returns the name" do
          expect(user.name).to eq("Oriol")
        end
      end

      context "when it doesn't have a name" do
        let(:user) { build(:user, name: nil) }

        it "returns anonymous" do
          expect(user.name).to eq("Anonymous")
        end
      end
    end

    describe "validations", processing_uploads_for: Decidim::AvatarUploader do
      context "when the nickname is empty" do
        before do
          user.nickname = ""
        end

        it "is not valid" do
          expect(user).not_to be_valid
          expect(user.errors[:nickname].length).to eq(2)
        end

        it "can't be empty backed by an index" do
          expect { user.save(validate: false) }.not_to raise_error
        end

        context "when managed" do
          before do
            user.managed = true
          end

          it "is valid" do
            expect(user).to be_valid
          end

          it "can be saved" do
            expect(user.save).to be true
          end

          it "can have duplicates" do
            user.save!

            expect do
              create(:user, organization: user.organization,
                            nickname: user.nickname,
                            managed: true)
            end.not_to raise_error
          end
        end

        context "when deleted" do
          before do
            user.deleted_at = Time.current
          end

          it "is valid" do
            expect(user).to be_valid
          end

          it "can be saved" do
            expect(user.save).to be true
          end

          it "can have duplicates" do
            user.save!

            expect do
              create(:user, organization: user.organization,
                            nickname: user.nickname,
                            deleted_at: Time.current)
            end.not_to raise_error
          end
        end
      end

      context "when the nickname is not empty" do
        before do
          user.nickname = "a-nickname"
        end

        it "can be created" do
          expect(user.save).to eq(true)
        end

        it "can't have duplicates even when skipping validations" do
          user.save!

          expect do
            build(:user, organization: user.organization,
                         nickname: user.nickname).save(validate: false)
          end.to raise_error(ActiveRecord::RecordNotUnique)
        end
      end

      context "when the file is too big" do
        before do
          allow(subject.avatar).to receive(:size).and_return(11.megabytes)
        end

        it { is_expected.not_to be_valid }
      end

      context "when the file is a malicious image" do
        let(:avatar_path) { Decidim::Dev.asset("malicious.jpg") }
        let(:user) do
          build(
            :user,
            avatar: Rack::Test::UploadedFile.new(avatar_path, "image/jpg")
          )
        end

        it { is_expected.not_to be_valid }
      end

      context "with weird characters" do
        let(:weird_characters) do
          %w(< > ? % & ^ * # @ ( ) [ ] = + : ; " { } \ |)
        end

        it "doesn't allow them" do
          weird_characters.each do |character|
            user = build(:user)
            user.name.insert(rand(0..user.name.length), character)
            user.nickname.insert(rand(0..user.nickname.length), character)

            expect(user).not_to be_valid
            expect(user.errors[:name].length).to eq(1)
            expect(user.errors[:nickname].length).to eq(1)
          end
        end
      end
    end

    describe "validation scopes" do
      context "when a user with the same email exists in another organization" do
        let(:email) { "foo@bar.com" }
        let(:user) { create(:user, email: email) }

        before do
          create(:user, email: email)
        end

        it { is_expected.to be_valid }
      end
    end

    describe "devise emails" do
      it "sends them asynchronously" do
        create(:user)
        expect(ActionMailer::DeliveryJob).to have_been_enqueued.on_queue("mailers")
      end
    end

    describe "#deleted?" do
      it "returns true if deleted_at is present" do
        subject.deleted_at = Time.current
        expect(subject).to be_deleted
      end
    end

    describe "#tos_accepted?" do
      subject { user.tos_accepted? }

      let(:user) { create(:user, organization: organization, accepted_tos_version: accepted_tos_version) }
      let(:accepted_tos_version) { organization.tos_version }

      it { is_expected.to be_truthy }

      context "when user accepted ToS before organization last update" do
        let(:organization) { build(:organization, tos_version: Time.current) }
        let(:accepted_tos_version) { 1.year.before }

        it { is_expected.to be_falsey }

        context "when organization has no TOS" do
          let(:organization) { build(:organization, tos_version: nil) }
          let(:user) { build(:user, organization: organization) }

          it { is_expected.to be_falsey }
        end
      end

      context "when user didn't accepted ToS" do
        let(:accepted_tos_version) { nil }

        it { is_expected.to be_falsey }

        context "when user is managed" do
          let(:user) { build(:user, :managed, organization: organization, accepted_tos_version: accepted_tos_version) }

          it { is_expected.to be_truthy }
        end

        context "when organization has no TOS" do
          let(:organization) { build(:organization, tos_version: nil) }

          it { is_expected.to be_falsey }
        end
      end
    end

    describe "#find_for_authentication" do
      let(:user) { create(:user, organization: organization) }

      let(:conditions) do
        {
          env: {
            "decidim.current_organization" => organization
          },
          email: user.email.upcase
        }
      end

      it "finds the user even with weird casing in email" do
        expect(described_class.find_for_authentication(conditions)).to eq user
      end
    end

    describe "#registration_metadata" do
      before do
        user.registration_metadata[:foo] = "bar"
        user.save
      end

      it "returns registration metadata" do
        expect(user.registration_metadata).to eq(
          "gender" => gender,
          "birth_date" => birth_date,
          "foo" => "bar",
          "residence_department" => residence_department,
          "motivations" => motivations,
          "primary_participation" => primary_participation
        )
      end
    end
  end
end
