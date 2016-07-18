require 'rubygems'
require 'sinatra'
require 'erb'
require 'cgi'

require 'bunny'
require 'json'

enable :sessions
set :show_exceptions, true

def amqp_url
  if not ENV['VCAP_SERVICES']
    return {
      :host => "localhost",
      :port => 5672,
      :username => "guest",
      :password => "guest",
      :vhost => "/",
    }
  end

  services = JSON.parse(ENV['VCAP_SERVICES'], :symbolize_names => true)
  url = services.values.map do |srvs|
    srvs.map do |srv|
      if srv[:label] =~ /^rabbitmq-/
        srv[:credentials]
        srv[:credentials][:heartbeat] = 20
        return srv[:credentials]
      else
        []
      end
    end
  end.flatten!.first
end

def client
  unless $client
    u = amqp_url
    conn = Bunny.new(u)
    conn.start
    $client = conn.create_channel
    $client.prefetch(1)
  end
  $client
end

def nameless_exchange
  $nameless_exchange ||= client.default_exchange
end

def messages_queue
  $messages_queue ||= client.queue("messages", :durable => true, :auto_delete => false)
end

def take_session key
  res = session[key]
  session[key] = nil
  res
end

get '/' do
  @published = take_session(:published)
  @got = take_session(:got)
  erb :index
end

post '/publish' do
  nameless_exchange.publish params[:message], :routing_key => messages_queue.name
  session[:published] = true
  redirect to('/')
end

post '/get' do
  session[:got] = :queue_empty
  s = String.new("")
  for i in 0...messages_queue.message_count
    _, _, payload = messages_queue.pop
    s = s + payload + "\n"
  end
  session[:got] = s
  redirect to('/')
end
