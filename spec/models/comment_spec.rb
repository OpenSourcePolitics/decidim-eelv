# frozen_string_literal: true

require "spec_helper"

module Decidim
  module Comments
    describe Comment do
      let!(:commentable) { create(:dummy_resource) }
      let!(:author) { create(:user, organization: commentable.organization) }
      let!(:comment) { create(:comment, commentable: commentable, author: author) }
      let!(:replies) { create_list(:comment, 3, commentable: comment, root_commentable: commentable) }
      let!(:up_vote) { create(:comment_vote, :up_vote, comment: comment) }
      let!(:down_vote) { create(:comment_vote, :down_vote, comment: comment) }

      include_examples "authorable" do
        subject { comment }
      end

      include_examples "reportable" do
        subject { comment }
      end

      it "is valid" do
        expect(comment).to be_valid
      end

      it "has an associated commentable" do
        expect(comment.commentable).to eq(commentable)
      end

      it "has an associated root commentable" do
        expect(comment.root_commentable).to eq(commentable)
      end

      it "has a up_votes association returning comment votes with weight 1" do
        expect(comment.up_votes.count).to eq(1)
      end

      it "has a down_votes association returning comment votes with weight -1" do
        expect(comment.down_votes.count).to eq(1)
      end

      it "is not valid if its parent is a comment and cannot accept new comments" do
        expect(comment.root_commentable).to receive(:accepts_new_comments?).and_return false
        expect(replies[0]).not_to be_valid
      end

      it "computes its depth before saving the model" do
        expect(comment.depth).to eq(0)
        comment.comments.each do |reply|
          expect(reply.depth).to eq(1)
        end
      end

      describe "#accepts_new_comments?" do
        it "returns true if the comment's depth is below MAX_DEPTH" do
          comment.depth = Comment::MAX_DEPTH - 1
          expect(comment).to be_accepts_new_comments
        end

        it "returns false if the comment's depth is equal or greater than MAX_DEPTH" do
          comment.depth = Comment::MAX_DEPTH
          expect(comment).not_to be_accepts_new_comments
        end
      end

      it "is not valid if alignment is not 0, 1 or -1" do
        comment.alignment = 2
        expect(comment).not_to be_valid
      end

      describe "#up_voted_by?" do
        let(:user) { create(:user, organization: comment.organization) }

        it "returns true if the given user has upvoted the comment" do
          create(:comment_vote, comment: comment, author: user, weight: 1)
          expect(comment).to be_up_voted_by(user)
        end

        it "returns false if the given user has not upvoted the comment" do
          expect(comment).not_to be_up_voted_by(user)
        end
      end

      describe "#down_voted_by?" do
        let(:user) { create(:user, organization: comment.organization) }

        it "returns true if the given user has downvoted the comment" do
          create(:comment_vote, comment: comment, author: user, weight: -1)
          expect(comment).to be_down_voted_by(user)
        end

        it "returns false if the given user has not downvoted the comment" do
          expect(comment).not_to be_down_voted_by(user)
        end
      end

      describe "#users_to_notify_on_comment_created" do
        let(:user) { create :user, organization: comment.organization }

        it "includes the comment author" do
          expect(comment.users_to_notify_on_comment_created)
            .to include(author)
        end

        it "includes the values from its commentable" do
          allow(comment.commentable)
            .to receive(:users_to_notify_on_comment_created)
            .and_return(Decidim::User.where(id: user.id))

          expect(comment.users_to_notify_on_comment_created)
            .to include(user)
        end
      end

      describe "#formatted_body" do
        let(:comment) { create(:comment, commentable: commentable, author: author, body: body) }
        let(:body) { "<b>bold text</b> %lorem% <a href='https://example.com'>link</a>" }

        before do
          allow(Decidim).to receive(:content_processors).and_return([:dummy_foo])
        end

        it "sanitizes user input" do
          expect(comment).to receive(:sanitized_body)
          comment.formatted_body
        end

        it "process the body after it is sanitized" do
          expect(Decidim::ContentProcessor).to receive(:render).with("<p>bold text %lorem% link</p>", "div")
          comment.formatted_body
        end

        it "returns the body sanitized and processed" do
          expect(comment.formatted_body).to eq("<div><p>bold text <em>neque dicta enim quasi</em> link</p></div>")
        end

        describe "when the body contains multiline quotes" do
          let(:body) { "> quote first line\n> quote second line\n\nanswer" }
          let(:result) { "<div><blockquote class=\"comment__quote\"><p>quote first line\n<br />quote second line</p></blockquote><p>answer</p></div>" }

          it "parses quotes and renders them as blockquotes" do
            expect(comment.formatted_body).to eq(result)
          end
        end

        describe "when the body contains quotes with paragraphs" do
          let(:body) { "> quote first paragraph\n>\n> quote second paragraph\n\nanswer" }
          let(:result) { "<div><blockquote class=\"comment__quote\">\n<br /><p>quote first paragraph</p>\n<br /><p>quote second paragraph</p>\n<br /></blockquote><p>answer</p></div>" }

          it "parses quotes and renders them as blockquotes" do
            expect(comment.formatted_body).to eq(result)
          end
        end

        describe "when the body contains urls" do
          before { allow(Decidim).to receive(:content_processors).and_return([:link]) }

          let(:body) do
            %(Content with <a href="http://urls.net" onmouseover="alert('hello')">URLs</a> of anchor type and text urls like https://decidim.org. And a malicous <a href="javascript:document.cookies">click me</a>)
          end
          let(:result) do
            %(<div><p>Content with URLs of anchor type and text urls like <a href="https://decidim.org" target="_blank" rel="nofollow noopener">https://decidim.org</a>. And a malicous click me</p></div>)
          end

          it "converts all URLs to links and strips attributes in anchors" do
            expect(comment.formatted_body).to eq(result)
          end
        end
      end

      describe "#comment_threads count" do
        let!(:parent) { create(:comment, commentable: commentable) }
        let!(:comments) { create_list(:comment, 3, commentable: parent, root_commentable: commentable) }

        it "return 3" do
          expect(parent.comment_threads.count).to eq 3
        end

        it "returns 2 when a comment has been moderated" do
          Decidim::Moderation.create!(reportable: comments.last, participatory_space: comments.last.participatory_space, hidden_at: 1.day.ago)

          expect(parent.comment_threads.count).to eq 2
        end
      end

      describe "#reported_content_url" do
        let!(:parent) { create(:comment, commentable: commentable) }
        let!(:comment) { create(:comment, commentable: parent, root_commentable: commentable) }

        it "returns proper url" do
          expect(comment.reported_content_url).to end_with("?commentId=#{comment.id}")
        end
      end

      describe "#user_commentators_ids_in" do
        context "when commentors belong to the given resources" do
          it "returns the autors of the resources' comments" do
            ids = Decidim::Comments::Comment.user_commentators_ids_in(Decidim::DummyResources::DummyResource.where(component: commentable.component))
            expect(ids).to match_array([author.id])
          end
        end

        context "when commentors do not belong to the given resources" do
          let(:other_component) { create(:dummy_component) }
          let!(:other_commentable) { create(:dummy_resource, component: other_component) }

          it "does not return them" do
            ids = Decidim::Comments::Comment.user_commentators_ids_in(Decidim::DummyResources::DummyResource.where(component: commentable.component))
            expect(ids).to match_array([author.id])
          end
        end

        context "when resource is not commentable" do
          let(:other_component) { create(:dummy_component) }
          let!(:non_commentable) { create(:coauthorable_dummy_resource, component: other_component) }

          it "returns nil" do
            ids = Decidim::Comments::Comment.user_commentators_ids_in(Decidim::DummyResources::CoauthorableDummyResource.where(component: other_component))
            expect(ids).to be_nil
          end
        end
      end
    end
  end
end
