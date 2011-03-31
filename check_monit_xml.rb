#!/usr/bin/ruby

require 'optparse'
require 'net/http'
require 'rexml/document'


# Nagios exit status
UNDEF    = -1
OK       = 0
WARNING  = 1
CRITICAL = 2
UNKNOWN  = 3

$exit_status = UNDEF

def parse_options(args)

  # Hash to hold options
  options = Hash.new

  parser = OptionParser.new do |opts|

    opts.on('-H hostname', '--hostname hostname', 'Hostname') do |v|
      options[:hostname] = v
    end

    opts.on('-P port', '--port port', 'Port') do |v|
      options[:port] = v
    end

    opts.on('-u user', '--user user', 'Username') do |v|
      options[:user] = v
    end

    opts.on('-p password', '--password password', 'Password') do |v|
      options[:password] = v
    end

    opts.on('-s service', '--service service', 'Monit Service to Monitor') do |v|
      options[:service] = v
    end

    opts.on('-g group', '--group group', 'Monit Group to Monitor') do |v|
      options[:group] = v
    end

    opts.on_tail('-h', '--help', 'Displays usage information') do 
      puts opts
      exit UNKNOWN
    end

  end

  # Parse Parameters
  begin
    parser.parse!(args)
  rescue OptionParser::ParseError => e
    puts "Parse Error: " + e
    puts parser.to_a
  end

  # Check for required params
  if (options.has_key?(:hostname) && options.has_key?(:port))
      #
      # Return Options
      options
  else
    puts parser.to_a
    exit UNKNOWN
  end
end

def set_exit_status(status)
  $exit_status = status > $exit_status ? status : $exit_status
end

def get_status(options)
  begin
    #
    # Create HTTP Connection
    #
    http = Net::HTTP.start(options[:hostname], options[:port])
    req = Net::HTTP::Get.new("/_status?format=xml")

    if options[:user]
      req.basic_auth(options[:user], options[:password])
    end

    response = http.request(req)

    if response.code != "200"
      puts "Got #{response.code} Error"
      exit UNKNOWN
    else
      return response.body
    end

  rescue SocketError
    puts "Socket Error"
    exit UNKNOWN

  rescue Net::HTTPServerException => e
    puts e
    exit UNKNOWN
  end
end

def get_services(xml)
  begin
    doc = REXML::Document.new xml

    services = Hash.new

    doc.elements.each("monit/service") do |service|

      name = service.elements['name'].get_text
      services[name] = Hash.new
      services[name]['status']  = service.elements['status'].get_text
      services[name]['monitor'] = service.elements['monitor'].get_text
      services[name]['group']   = service.elements['group'].get_text
    end

    return services

  rescue REXML::ParseException
    puts "XML Parse Error"
    exit UNKNOWN
  end
end

# Messages for Nagios
messages = Array.new

options = parse_options(ARGV)

xml = get_status(options)

services = get_services(xml)

# Revove everything we are not interested in
services.each do |service,info|
  if options[:group] && (not info['group'] == options[:group])
    services.delete(service)
  end

  if options[:service] && (not service == options[:service])
    services.delete service
  end
end

# Return what's left
services.each do |service,info|
  if info["monitor"] == 1 
    set_exit_status(OK)
  else
    messages << "#{service} not monitored"
    set_exit_status(CRITICAL)
  end

  if info["status"] == 0
    set_exit_status(OK)
  else 
    messages << "#{service} down"
    set_exit_status(CRITICAL)
  end
end

# See if we got here without updating exit status
if $exit_status == UNDEF 
  messages << "Plugin Error!"
  set_exit_status(UNKNOWN)
end

if messages.length == 0
  puts "OK"
else
  puts messages.join(', ')
end

exit $exit_status
