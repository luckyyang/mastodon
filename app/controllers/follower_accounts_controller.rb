# frozen_string_literal: true

class FollowerAccountsController < ApplicationController
  include AccountControllerConcern
  include TimelineConcern

  def index
    respond_to do |format|
      format.html do
        set_initial_state_json
      end

      format.json do
        raise ActiveRecord::RecordNotFound unless @account.local?

        @follows = Follow.where(target_account: @account).recent.page(params[:page]).per(FOLLOW_PER_PAGE).preload(:account)

        render json: collection_presenter, serializer: ActivityPub::CollectionSerializer, adapter: ActivityPub::Adapter, content_type: 'application/activity+json'
      end
    end
  end

  private

  def collection_presenter
    ActivityPub::CollectionPresenter.new(
      id: account_followers_url(@account),
      type: :ordered,
      size: @account.followers_count,
      items: @follows.map { |f| ActivityPub::TagManager.instance.uri_for(f.account) }
    )
  end
end
