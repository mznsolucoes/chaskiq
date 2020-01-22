# frozen_string_literal: true
require 'pp'
require 'oauth2'

module MessageApis
  class Slack
    BASE_URL = 'https://slack.com'
    HEADERS = {"content-type" => "application/json"} #Suggested set? Any?

    attr_accessor :key, :secret, :access_token

    attr_accessor :keys,
                  :client,
                  :base_url #Default: 'https://api.twitter.com/'
  

    #include MessageApis::OauthUtils             

    def initialize(config: {})
      @access_token = access_token
      @conn = Faraday.new request: {
        params_encoder: Faraday::FlatParamsEncoder
      }

      @keys = {}
      @keys['channel'] = 'chaskiq_channel'
      @keys['consumer_key'] = config["api_key"]
      @keys['consumer_secret'] =  config["api_secret"]
      @keys['access_token'] =  config["access_token"]
      @keys['access_token_secret'] =  config["access_token_secret"]
      @keys['user_token'] = config["user_token"]
    end

    def get_api_access
      @base_url = BASE_URL

      {
        "access_token": @keys['access_token'],
        "access_token_secret": @keys['access_token_secret']
      }.with_indifferent_access
    end

    def self.tester
      api = MessageApis::Slack.new
      a = AppPackageIntegration.first
      a.message_api_klass.post_message
    end

    def authorize!
      get_api_access
      @conn.authorization :Bearer, @keys["access_token_secret"]
    end

    def oauth_client
      @oauth_client ||= OAuth2::Client.new(
        @keys['consumer_key'], 
        @keys['consumer_secret'], 
        site: 'https://slack.com',
        authorize_url: '/oauth/authorize',
        token_url: '/api/oauth.access'
      )
    end

    def user_client

    end

    def url(url)
      "#{BASE_URL}#{url}"
    end

    def post_message
      authorize!

      data = {
        "channel": @keys['channel'] || 'chaskiq_channel',
        "text": 'hola oeoeo',
        "blocks": [
            {
              "type": "section",
              "text": {
                "type": "mrkdwn",
                "text": "Hello, a conversation initiated by *Michael Scott*"
              }
            },
            {
              "type": "section",
              "text": {
                "type": "plain_text",
                "text": "This is a plain text section block.",
                "emoji": true
              }
            },
            {
              "type": "divider"
            },
            {
              "type": "actions",
              "elements": [
                {
                  "type": "button",
                  "text": {
                    "type": "plain_text",
                    "text": "Close",
                    "emoji": true
                  },
                  "value": "click_me_123"
                },
                {
                  "type": "button",
                  "text": {
                    "type": "plain_text",
                    "text": "Reply in channel",
                    "emoji": true
                  },
                  "value": "click_me_123"
                }
              ]
            }
          ]
      }

      url = url('/api/chat.postMessage')

      response = @conn.post do |req|
        req.url url
        req.headers['Content-Type'] = 'application/json; charset=utf-8'
        req.body = data.to_json
      end

      puts response.body
      puts response.status
    end

    def create_channel(name='chaskiq_channel')
      authorize!

      data = {
        "name": name,
        "user_ids": "UR2A93SRK"
      }

      url = url('/api/conversations.create')

      response = @conn.post do |req|
        req.url url
        req.headers['Content-Type'] = 'application/json; charset=utf-8'
        req.body = data.to_json
      end

      #puts response.body
      JSON.parse(response.body)
    end

    def join_channel(id)
      authorize!

      data = {
        "channel": id
      }

      url = url('/api/channels.join')

      @conn.authorization :Bearer, @keys["access_token"]

      #url = "https://a77c6f48.ngrok.io"

      response = @conn.post do |req|
        req.url url
        req.headers['Content-Type'] = 'application/json; charset=utf-8'
        #req.headers['X-Slack-User'] = 'UR2A93SRK'
        req.body = data.to_json
      end

      JSON.parse(response.body)
    end

    def trigger(event)
      conversation = event.eventable
      action = event.action

      case action
      #when "conversations.added" then notify_added(conversation)
      when "conversations.started" then notify_added(conversation)
      else
      end
    end

    def notify_added(conversation)

      authorize!

      blocks = conversation.messages.map{|o| 
        JSON.parse(o.messageable.serialized_content)["blocks"]  
      }.flatten

      text_blocks = blocks.map{|o| o['text']}

      data = {
        "channel": @keys['channel'] || 'chaskiq_channel',
        "text": 'New conversation from Chaskiq',
        "blocks": [
            {
              "type": "section",
              "text": {
                "type": "mrkdwn",
                "text": "Conversation initiated by *#{conversation.main_participant.display_name}*"
              }
            },
            {
              "type": "section",
              "text": {
                "type": "plain_text",
                "text": text_blocks.first,
                "emoji": true
              }
            },
            {
              "type": "divider"
            },
            {
              "type": "actions",
              "elements": [
                {
                  "type": "button",
                  "text": {
                    "type": "plain_text",
                    "text": "Reply in channel",
                    "emoji": true
                  },
                  "value": "conversation-#{conversation.id}"
                }
              ]
            }
          ]
      }

      url = url('/api/chat.postMessage')

      response = @conn.post do |req|
        req.url url
        req.headers['Content-Type'] = 'application/json; charset=utf-8'
        req.body = data.to_json
      end

      puts response.body
      puts response.status
      
    end

    def enqueue_process_event(params, package)
      return handle_challenge(params) if is_challenge?(params) 
      #process_event(params, package)
      HookMessageReceiverJob.perform_now(
        id: package.id, 
        params: params.permit!.to_h
      )
    end

    def process_event(params, package)
      payload = JSON.parse(params["payload"])
      response_url = payload["response_url"]

      data = {
        "channel": @keys['channel'] || 'chaskiq_channel',
        "text": payload["message"]["text"],
        "blocks": [{
          "type": "context",
          "elements": [
            {
              "type": "mrkdwn",
              "text": "channel created! "
            }
          ]
        }]
      }

      ##pp payload

      create_channel_response = create_channel("chaskiq-#{Time.now.to_i}")

      if create_channel_response["error"].blank?
        join_channel_response = join_channel(
          create_channel_response["channel"]["id"]
        )
      end

      blocks = payload["message"]["blocks"].reject{|o| 
        o["type"] == "actions"
      } + data[:blocks]

      data.merge!(
        {
          blocks: blocks
        }
      )

      response = @conn.post do |req|
        req.url response_url
        req.headers['Content-Type'] = 'application/json; charset=utf-8'
        req.body = data.to_json
      end

      response.body
    end

    def handle_challenge(params)
      params[:challenge]
    end

    def is_challenge?(params)
      params.keys.include?("challenge")
    end

    def data2
      [
        {
          "type": "section",
          "text": {
            "type": "mrkdwn",
            "text": "Hello, a conversation initiated by *Michael Scott*"
          }
        },
        {
          "type": "divider"
        },
        {
          "type": "section",
          "text": {
            "type": "mrkdwn",
            "text": "*Farmhouse Thai Cuisine*\n:star::star::star::star: 1528 reviews\n They do have some vegan options, like the roti and curry, plus they have a ton of salad stuff and noodles can be ordered without meat!! They have something for everyone here"
          },
          "accessory": {
            "type": "image",
            "image_url": "https://s3-media3.fl.yelpcdn.com/bphoto/c7ed05m9lC2EmA3Aruue7A/o.jpg",
            "alt_text": "alt text for image"
          }
        },
        {
          "type": "divider"
        },
        {
          "type": "actions",
          #"callback_id": "button_feedback",
          "elements": [
            {
              "type": "button",
              "text": {
                "type": "plain_text",
                "text": "Close",
                "emoji": true
              },
              "value": "click_me_123"
            },
            {
              "type": "button",
              "text": {
                "type": "plain_text",
                "text": "Reply in channel",
                "emoji": true
              },
              "value": "click_me_123"
            }
          ]
        },
      ]
    end

    def oauth_authorize(app, package)
      oauth_client.auth_code.authorize_url(
        scope: 'channels:write',
        redirect_uri: package.oauth_url
      )
    end

    def receive_oauth_code(params, package)
      code = params[:code]

      headers = {
        :accept => 'application/json',
        :content_type => 'application/json'
      }

      token = oauth_client.auth_code.get_token(
        code, 
        :redirect_uri => package.oauth_url, 
        :token_method => :post,
        #:params => { 
        #  code: code
        #}.to_json
      )

      package.update(user_token: token.token)

      puts "EL TOKEN #{token.token}"
      
      #response = token.get('/api/oauth.access', :params => { 
      #  'code' => code,
      #  'query_foo' => 'bar' 
      #})
      
      token.token
    end

  end
end

## PLAN

=begin
 
+ usuario crea conversacion
  + se manda mensaje por canal chaskiq
    + con opcoin de responder en canal
  + recibe hook
    + se crea canal de conversacion
  + proximos mensajes se envian y reciben por ese canal

=end
