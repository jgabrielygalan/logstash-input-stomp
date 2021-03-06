# encoding: utf-8
require "logstash/inputs/base"
require "logstash/namespace"
require 'pp'

# This plugin connects to a Stomp endpoint and consumes all messages.
# It generates an event for each message received. The _message_ field of the event will carry the body of the Stomp
# message. You can also specify a set of headers to be copied from the Stomp message to the event as separate fields.

# ## Example
# With this configuration:
# input {
#   stomp {
#     debug => true
#     host => "localhost"
#     port => 5445
#     user => "guest"
#     password => "guest"
#     destination => "test"
#     headers => ["message-id", "type"]
#   }
# }
#
# output {
#   stdout { codec => json}
# }

# The plugin will connect to _stomp://localhost:5445_, with _guest:guest_ as user:password, and connect to the _test_ destination.
# The output of the message could be something like:
# {"message":"hello world","@version":"1","@timestamp":"2015-01-27T17:51:48.872Z","message-id":"136","type":"messageType1"}
#
#
class LogStash::Inputs::Stomp < LogStash::Inputs::Base
  config_name "stomp"
  milestone 3

  default :codec, "plain"

  # The address of the STOMP server.
  config :host, :validate => :string, :default => "localhost", :required => true

  # The port to connet to on your STOMP server.
  config :port, :validate => :number, :default => 61613

  # The username to authenticate with.
  config :user, :validate => :string, :default => ""

  # The password to authenticate with.
  config :password, :validate => :password, :default => ""

  # The destination to read events from.
  #
  # Example: "/topic/logstash"
  config :destination, :validate => :string, :required => true

  # The vhost to use
  config :vhost, :validate => :string, :default => nil

  # Enable debugging output?
  config :debug, :validate => :boolean, :default => false

  # Add headers as event fields, as a comma separated list of header names.
  #
  # Example: headers => ["message-id", "type"]
  config :headers, :validate => :array, :default => []

  private
  def connect
    begin
      @client.connect
      @logger.debug("Connected to stomp server") if @client.connected?
    rescue => e
      @logger.debug("Failed to connect to stomp server, will retry", :exception => e, :backtrace => e.backtrace)
      sleep 2
      retry
    end
  end

  public
  def register
    require "onstomp"
    @client = OnStomp::Client.new("stomp://#{@host}:#{@port}", :login => @user, :passcode => @password.value)
    @client.host = @vhost if @vhost
    @stomp_url = "stomp://#{@user}:#{@password}@#{@host}:#{@port}/#{@destination}"

    # Handle disconnects 
    @client.on_connection_closed {
      connect
      subscription_handler # is required for re-subscribing to the destination
    }
    connect
  end # def register

  private
  def add_headers event, msg
    p msg
    @headers.each do |header|
      puts "Checking for header #{header}"
      event[header] = msg[header] if(msg[header])
    end    
  end


  def subscription_handler
    @client.subscribe(@destination) do |msg|
      @codec.decode(msg.body) do |event|
        decorate(event)
        add_headers(event, msg)
        @output_queue << event
      end
    end
    #In the event that there is only Stomp input plugin instances
    #the process ends prematurely. The above code runs, and return
    #the flow control to the 'run' method below. After that, the
    #method "run_input" from agent.rb marks 'done' as 'true' and calls
    #'finish' over the Stomp plugin instance.
    #'Sleeping' the plugin leves the instance alive.
    sleep
  end

  public
  def run(output_queue)
    @output_queue = output_queue 
    subscription_handler
  end # def run
end # class LogStash::Inputs::Stomp
