#!/usr/bin/ruby

require 'optparse'
require 'net/http'
require 'rexml/document'


# Array to hold status messages
messages = Array.new

# Set status to OK initally
$exit_status = 0

#
# parse_options:
#
# 	params:
# 		args :   ARGV
# 	returns:
# 		hash containing options
#
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
      exit 3
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
    exit 3
  end
end

def exit_status(status)
  $exit_status = status > $exit_status ? status : $exit_status
end

def get_status(options)
  begin
    #
    # Create HTTP Connection
    #
    http = Net::HTTP.start(options[:hostname], options[:port])
    req = Net::HTTP::Get.new("/_status?format=xml")

    #'if options[:user]
     # req.basic_auth(options[:user], options[:password])
    #end

    response = http.request(req)

    if response.code != "200"
      puts "Got #{response.code} Error"
      exit 3
    else
      return response.body
    end

  rescue SocketError
    puts "Socket Error"
    status = 3
    exit status

  rescue Net::HTTPServerException => e
    puts e
    status = 3
    exit status
  end
end

def get_services(xml)
  begin
    #
    # Create XML Object from response
    #
    doc = REXML::Document.new xml

    #
    # Go through each instance and check it's status
    #
    count = 0

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
    messages << "XML Parse Error"
    status = 3
  end
end

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

p services 

# Return what's left
services.each do |service,info|

  if info["monitor"] != 1 
    messages << "#{service} not monitored"
    exit_status(3)
  end

  if info["status"] != 0
    messages << "#{service} down"
    exit_status(2)
  end
end


if messages.length == 0
  puts "OK"
else
  messages.each { |msg| puts msg }
end
exit $exit_status
