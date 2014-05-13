require 'rubygems'
require 'bundler/setup'
Bundler.require(:default)
require 'uri'
require 'securerandom'
require './lib/github_issue_exporter'
require './lib/github_exporter_helpers'

class AuthenticationError < StandardError; end

class GithubExporterApp < Sinatra::Application
  use Rack::Flash
  helpers GithubExporterHelpers

  set :show_exceptions, :after_handler

  def self.load_config(env)
    file = File.open(File.join(File.dirname('__FILE__'), 'config.yml'))
    YAML.load(file)[env.to_s]
  end

  %i(development production).each do |env|
    configure env do
      config = load_config(env)
      set :client_id, config['client_id']
      set :client_secret, config['client_secret']
    end
  end

  enable :sessions

  get '/' do
    redirect to('/export') if logged_in?
    erb :index
  end

  get '/login' do
    session[:state] = SecureRandom.hex

    uri = URI('https://github.com/login/oauth/authorize')
    uri.query = {
      client_id: settings.client_id,
      redirect_uri: url('/oauth/callback'),
      state: session[:state],
      scope: 'repo'
    }.map { |key, value| "#{key}=#{value}" }.join('&')

    redirect uri.to_s
  end

  get '/oauth/callback' do
    raise AuthenticationError unless params[:state] == session[:state]

    response = HTTParty.post('https://github.com/login/oauth/access_token',
      body: {
        client_id: settings.client_id,
        client_secret: settings.client_secret,
        code: params[:code]
      },
      headers: { 'Accept' => 'application/json' }
    )

    raise AuthenticationError unless response.code == 200

    session[:access_token] = response.parsed_response['access_token']
    redirect to('/export')
  end

  before('/export') do
    authenticate!
    @user = client.user
  end

  get '/export' do
    erb :export
  end

  post '/export' do
    io = GithubIssueExporter.new(client, params[:repo], period: params[:period], state: params[:state]).execute

    content_type 'application/csv'
    attachment 'issues.csv'
    stream do |output|
      io.each do |line|
        output << line
      end
    end
  end

  error GithubIssueExporter::ValidationError do
    flash.now[:error] = env['sinatra.error'].message
    erb :export
  end

  error AuthenticationError do
    flash[:alert] = 'Authentication required'
    redirect to('/')
  end

  def authenticate!
    raise AuthenticationError unless logged_in?
  end

  def logged_in?
    client.token_authenticated?
  end

  def client
    @client ||= Octokit::Client.new(access_token: session[:access_token])
  end

end