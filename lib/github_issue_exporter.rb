require 'stringio'
require 'csv'

class GithubIssueExporter
  class ValidationError < ::StandardError; end

  HEADERS = %w(
    id
    Title
    Description
    Created
    Labels
    Status
    Reporter
  )

  def initialize(client, repo, options = {})
    @client, @repo = client, repo
    @io = options[:io] || StringIO.new
    @period = options[:period] || 'year'
    @state = options[:state] || 'all'
  end

  def execute
    csv << HEADERS

    issues.each do |issue|
      next if issue.pull_request

      csv << [
        issue.number,
        issue.title,
        issue.body,
        issue.created_at,
        issue.labels.map(&:name).join(', '),
        issue.state,
        issue.user.login
      ]
    end

    @io.rewind
    @io
  end

  private
    def csv
      @csv ||= CSV.new(@io)
    end

    def repo
      @extracted_repo ||= begin
        match = @repo.match(%r(^(https?://github.com/)?(?<repo>\w+/\w+)))
        match && match[:repo] || raise(ValidationError, 'Invalid repository')
      end
    end

    def start_date
      @start_date ||= case @period
      when 'year'
        Date.new(Date.today.year - 1, Date.today.month, Date.today.day)
      when 'month'
        Date.today - 30
      when 'week'
        Date.today - 7
      else
        raise ValidationError, 'invalid period'
      end
    end

    def issues
      @issues ||= begin
        @client.auto_paginate = true
        @client.issues(repo, since: start_date, state: @state)
      rescue Octokit::Error
        raise ValidationError, 'Failed to receive the issues list. Please check your access to the repository'
      end
    end
end