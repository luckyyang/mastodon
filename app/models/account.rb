# frozen_string_literal: true
# == Schema Information
#
# Table name: accounts
#
#  id                      :integer          not null, primary key
#  username                :string           default(""), not null
#  domain                  :string
#  secret                  :string           default(""), not null
#  private_key             :text
#  public_key              :text             default(""), not null
#  remote_url              :string           default(""), not null
#  salmon_url              :string           default(""), not null
#  hub_url                 :string           default(""), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  note                    :text             default(""), not null
#  display_name            :string           default(""), not null
#  uri                     :string           default(""), not null
#  url                     :string
#  avatar_file_name        :string
#  avatar_content_type     :string
#  avatar_file_size        :integer
#  avatar_updated_at       :datetime
#  header_file_name        :string
#  header_content_type     :string
#  header_file_size        :integer
#  header_updated_at       :datetime
#  avatar_remote_url       :string
#  subscription_expires_at :datetime
#  silenced                :boolean          default(FALSE), not null
#  suspended               :boolean          default(FALSE), not null
#  locked                  :boolean          default(FALSE), not null
#  header_remote_url       :string           default(""), not null
#  statuses_count          :integer          default(0), not null
#  followers_count         :integer          default(0), not null
#  following_count         :integer          default(0), not null
#  last_webfingered_at     :datetime
#

class Account < ApplicationRecord
  MENTION_RE = /(?:^|[^\/[:word:]])@([a-z0-9_]+(?:@[a-z0-9\.\-]+[a-z0-9]+)?)/i

  include AccountAvatar
  include AccountFinderConcern
  include AccountHeader
  include AccountInteractions
  include Attachmentable
  include Remotable

  # Local users
  has_one :user, inverse_of: :account

  validates :username, presence: true

  # Remote user validations
  validates :username, uniqueness: { scope: :domain, case_sensitive: true }, if: -> { !local? && will_save_change_to_username? }

  # Local user validations
  validates :username, format: { with: /\A[a-z0-9_]+\z/i }, uniqueness: { scope: :domain, case_sensitive: false }, length: { maximum: 30 }, if: -> { local? && will_save_change_to_username? }
  validates_with UnreservedUsernameValidator, if: -> { local? && will_save_change_to_username? }
  validates :display_name, length: { maximum: 30 }, if: -> { local? && will_save_change_to_display_name? }
  validates :note, length: { maximum: 160 }, if: -> { local? && will_save_change_to_note? }

  # Timelines
  has_many :stream_entries, inverse_of: :account, dependent: :destroy
  has_many :statuses, inverse_of: :account, dependent: :destroy
  has_many :favourites, inverse_of: :account, dependent: :destroy
  has_many :mentions, inverse_of: :account, dependent: :destroy
  has_many :notifications, inverse_of: :account, dependent: :destroy
  has_many :oauth_authentications, through: :user
  has_many :pinned_statuses, dependent: :destroy

  # Media
  has_many :media_attachments, dependent: :destroy

  # PuSH subscriptions
  has_many :subscriptions, dependent: :destroy

  # Report relationships
  has_many :reports
  has_many :targeted_reports, class_name: 'Report', foreign_key: :target_account_id

  scope :remote, -> { where.not(domain: nil) }
  scope :local, -> { where(domain: nil) }
  scope :without_followers, -> { where(followers_count: 0) }
  scope :with_followers, -> { where('followers_count > 0') }
  scope :expiring, ->(time) { remote.where.not(subscription_expires_at: nil).where('subscription_expires_at < ?', time) }
  scope :partitioned, -> { order('row_number() over (partition by domain)') }
  scope :silenced, -> { where(silenced: true) }
  scope :suspended, -> { where(suspended: true) }
  scope :recent, -> { reorder(id: :desc) }
  scope :alphabetic, -> { order(domain: :asc, username: :asc) }
  scope :by_domain_accounts, -> { group(:domain).select(:domain, 'COUNT(*) AS accounts_count').order('accounts_count desc') }
  scope :matches_username, ->(value) { where(arel_table[:username].matches("#{value}%")) }
  scope :matches_display_name, ->(value) { where(arel_table[:display_name].matches("#{value}%")) }

  delegate :email,
           :current_sign_in_ip,
           :current_sign_in_at,
           :confirmed?,
           :locale,
           to: :user,
           prefix: true,
           allow_nil: true

  delegate :filtered_languages, to: :user, prefix: false, allow_nil: true

  def local?
    domain.nil?
  end

  def acct
    local? ? username : "#{username}@#{domain}"
  end

  def local_username_and_domain
    "#{username}@#{Rails.configuration.x.local_domain}"
  end

  def to_webfinger_s
    "acct:#{local_username_and_domain}"
  end

  def subscribed?
    subscription_expires_at.present?
  end

  def keypair
    @keypair ||= OpenSSL::PKey::RSA.new(private_key || public_key)
  end

  def subscription(webhook_url)
    @subscription ||= OStatus2::Subscription.new(remote_url, secret: secret, webhook: webhook_url, hub: hub_url)
  end

  def save_with_optional_media!
    save!
  rescue ActiveRecord::RecordInvalid
    self.avatar              = nil
    self.header              = nil
    self[:avatar_remote_url] = ''
    self[:header_remote_url] = ''
    save!
  end

  def object_type
    :person
  end

  def to_param
    username
  end

  def excluded_from_timeline_account_ids
    Rails.cache.fetch("exclude_account_ids_for:#{id}") { blocking.pluck(:target_account_id) + blocked_by.pluck(:account_id) + muting.pluck(:target_account_id) }
  end

  def excluded_from_timeline_domains
    Rails.cache.fetch("exclude_domains_for:#{id}") { domain_blocks.pluck(:domain) }
  end

  class << self
    def domains
      reorder(nil).pluck('distinct accounts.domain')
    end

    def triadic_closures(account, limit: 5, offset: 0, exclude_ids: [], current_time: Time.current)
      sql = <<-SQL.squish
        WITH first_degree AS (
          SELECT target_account_id
          FROM follows
          WHERE account_id = :account_id
        )
        SELECT accounts.*
        FROM follows
        INNER JOIN accounts ON follows.target_account_id = accounts.id
        WHERE
          account_id IN (SELECT * FROM first_degree)
          AND suspended = 'f'
          AND silenced = 'f'
          AND target_account_id NOT IN (SELECT * FROM first_degree)
          AND target_account_id NOT IN (:excluded_account_ids)
          AND accounts.suspended = false
        GROUP BY target_account_id, accounts.id
        HAVING (
          SELECT created_at
          FROM statuses
          WHERE statuses.account_id = target_account_id
          ORDER BY statuses.id DESC LIMIT 1
        ) >= TIMESTAMP :current_timestamp - '3 days'::INTERVAL
        ORDER BY count(account_id) DESC
        OFFSET :offset
        LIMIT :limit
      SQL

      excluded_account_ids = account.excluded_from_timeline_account_ids + [account.id] + exclude_ids

      find_by_sql(
        [sql, { account_id: account.id, excluded_account_ids: excluded_account_ids, limit: limit, offset: offset, current_timestamp: current_time }]
      )
    end

    def search_for(terms, limit = 10)
      textsearch, query = generate_query_for_search(terms)

      sql = <<-SQL.squish
        SELECT
          accounts.*,
          ts_rank_cd(#{textsearch}, #{query}, 32) AS rank
        FROM accounts
        WHERE #{query} @@ #{textsearch}
          AND accounts.suspended = false
        ORDER BY rank DESC
        LIMIT ?
      SQL

      find_by_sql([sql, limit])
    end

    def advanced_search_for(terms, account, limit = 10)
      textsearch, query = generate_query_for_search(terms)

      sql = <<-SQL.squish
        SELECT
          accounts.*,
          (count(f.id) + 1) * ts_rank_cd(#{textsearch}, #{query}, 32) AS rank
        FROM accounts
        LEFT OUTER JOIN follows AS f ON (accounts.id = f.account_id AND f.target_account_id = ?) OR (accounts.id = f.target_account_id AND f.account_id = ?)
        WHERE #{query} @@ #{textsearch}
          AND accounts.suspended = false
        GROUP BY accounts.id
        ORDER BY rank DESC
        LIMIT ?
      SQL

      find_by_sql([sql, account.id, account.id, limit])
    end

    def filter_by_time(ids, time_begin = 3.days.ago)
      sql = <<-SQL.squish
        SELECT accounts.id
        FROM accounts
        WHERE accounts.id IN (:ids)
        AND accounts.suspended = false
        AND suspended = 'f'
        AND silenced = 'f'
        AND (SELECT created_at FROM statuses ORDER BY statuses.id DESC LIMIT 1) > :time_begin
      SQL

      find_by_sql([sql, {ids: ids, time_begin: time_begin}])
    end

    private

    def generate_query_for_search(terms)
      terms      = Arel.sql(connection.quote(terms.gsub(/['?\\:]/, ' ')))
      textsearch = "(setweight(to_tsvector('simple', accounts.display_name), 'A') || setweight(to_tsvector('simple', accounts.username), 'B') || setweight(to_tsvector('simple', coalesce(accounts.domain, '')), 'C'))"
      query      = "to_tsquery('simple', ''' ' || #{terms} || ' ''' || ':*')"

      [textsearch, query]
    end
  end

  before_create :generate_keys
  before_validation :normalize_domain

  private

  def generate_keys
    return unless local?

    keypair = OpenSSL::PKey::RSA.new(Rails.env.test? ? 1024 : 2048)
    self.private_key = keypair.to_pem
    self.public_key  = keypair.public_key.to_pem
  end

  def normalize_domain
    return if local?

    self.domain = TagManager.instance.normalize_domain(domain)
  end
end
