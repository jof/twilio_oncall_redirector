#!/usr/bin/env ruby
require 'time'
require 'rubygems'
require 'sinatra/base'
require 'rest-client'
require 'json'
require 'yaml'
require 'active_support/core_ext/numeric/time'
require 'active_support/core_ext/time/calculations'
require 'active_support/core_ext/date/calculations'
require 'active_support/core_ext/time/acts_like'
require 's3'

CONFIG = YAML.load_file('config.yaml')

def pd_api_call(method, params = {})
  args={}
  args[:content_type] = :json
  args[:authorization] = "Token token=#{CONFIG['pagerduty_api_token']}"
  args[:params] = params
  return JSON.load(RestClient.get(CONFIG['pagerduty_api_base_url']+method, args))
end

def publish_call_redirection_for(schedule_id)
  # Search for users on-call in the next 5 minutes, to handle an incoming call.
  _since = DateTime.now.iso8601
  _until = 5.minutes.from_now.iso8601
  schedule = pd_api_call("/schedules/#{schedule_id}/users", {:since => _since, :until => _until})
  raise Exception.new("There are no users on-call in schedule #{schedule_id}!") unless (schedule["users"] and schedule["users"].length > 0)

  # Get that on-call users' PagerDuty user ID and find their first listed phone
  # number.
  on_call_user_id = schedule["users"].first["id"]
  on_call_user_contact_methods = pd_api_call("/users/#{on_call_user_id}/contact_methods")["contact_methods"]
  phone_numbers = on_call_user_contact_methods.select { |method| method["type"] == "phone" }
  raise Exception.new("There are no phone numbers for user #{on_call_user_id} while searching schedule #{schedule_id}!") unless (phone_numbers.length > 0)
  first_listed_phone_number = phone_numbers.first
  country_code = first_listed_phone_number["country_code"]
  phone_number = first_listed_phone_number["phone_number"]

  # Template a Twilio TwiML document to redirect the call.
  twiml = <<-EOF
<?xml version="1.0" encoding="UTF-8"?>
<!-- #{DateTime.now.iso8601} -->
<Response>
  <Dial timeout="#{CONFIG['redirection_dialing_timeout']}">+#{country_code}#{phone_number}</Dial>
</Response>
  EOF

  puts twiml
  return

  # Upload the file to S3.
  service = S3::Service.new(:access_key_id => CONFIG['aws_access_key_id'], :secret_access_key => CONFIG['aws_secret_access_key'])
  bucket = service.buckets.find(CONFIG['s3_bucket'])
  raise Exception.new("S3 bucket #{CONFIG['s3_bucket']} not found!") unless bucket
  object = bucket.objects.build("rotation/#{schedule_id}.xml")
  object.content = twiml
  object.save
end

CONFIG['pagerduty_schedules'].each do |pagerduty_schedule_id|
  publish_call_redirection_for pagerduty_schedule_id
end
