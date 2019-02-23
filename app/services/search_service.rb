# frozen_string_literal: true

class SearchService < BaseService
  attr_accessor :query, :account, :limit, :resolve

  def call(query, limit, resolve = false, account = nil)
    @query   = query.strip
    @account = account
    @limit   = limit
    @resolve = resolve

    default_results.tap do |results|
      if url_query?
        results.merge!(url_resource_results) unless url_resource.nil?
      elsif query.present?
        results[:accounts] = perform_accounts_search! if account_searchable?
        results[:statuses] = perform_statuses_search!
        results[:statuses].concat(perform_mediadescription_search!)
        results[:statuses] = results[:statuses].uniq.sort_by{|v| v['updated_at']}.reverse.first(limit)
	results[:hashtags] = perform_hashtags_search! if hashtag_searchable?
      end
    end
  end

  private

  def perform_accounts_search!
    AccountSearchService.new.call(query, limit, account, resolve: resolve)
  end

  def perform_statuses_search!
    statuses = Status.joins(:account)
      .where('accounts.domain IS NULL')
      .where('statuses.local=true')
      .limit(limit)
    query.split(/[\s　]+/).each do |keyword|
      if (matches = keyword.match(/^-(.*)/))
        keyword = matches[1]
        statuses = statuses.where('statuses.text !~ ?', keyword)
      else
        statuses = statuses.where('statuses.text ~ ?', keyword)
      end
    end
    statuses.reject { |status| StatusFilter.new(status, account).filtered? }
  rescue Faraday::ConnectionFailed
    []
  end

  def perform_mediadescription_search!
    medias = Status
      .joins(:account)
      .joins(:media_attachments)
      .where('accounts.domain IS NULL')
      .where('statuses.local=true')
      .limit(limit)
    query.split(/[\s　]+/).each do |keyword|
      if (matches = keyword.match(/^-(.*)/))
        keyword = matches[1]
        medias = medias.where('media_attachments.description !~ ?', keyword)
      else
        medias = medias.where('media_attachments.description ~ ?', keyword)
      end
    end
    medias.reject { |status| StatusFilter.new(status, account).filtered? }
  rescue Faraday::ConnectionFailed
    []
  end

  def perform_hashtags_search!
    Tag.search_for(query.gsub(/\A#/, ''), limit)
  end

  def default_results
    { accounts: [], hashtags: [], statuses: [] }
  end

  def url_query?
    query =~ /\Ahttps?:\/\//
  end

  def url_resource_results
    { url_resource_symbol => [url_resource] }
  end

  def url_resource
    @_url_resource ||= ResolveURLService.new.call(query, on_behalf_of: @account)
  end

  def url_resource_symbol
    url_resource.class.name.downcase.pluralize.to_sym
  end

  def full_text_searchable?
    return false unless Chewy.enabled?
    !account.nil? && !((query.start_with?('#') || query.include?('@')) && !query.include?(' '))
  end

  def account_searchable?
    !(query.include?('@') && query.include?(' '))
  end

  def hashtag_searchable?
    !query.include?('@')
  end
end
