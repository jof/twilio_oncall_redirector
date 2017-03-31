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
require 'aws-sdk'

CONFIG = YAML.load_file('config.yaml')

def pd_api_call(method, params = {})
  args={}
  args[:content_type] = :json
  args[:authorization] = "Token token=#{CONFIG['pagerduty_api_token']}"
  args[:params] = params
  args[:accept] = "application/vnd.pagerduty+json;version=2"
  return JSON.load(RestClient.get(CONFIG['pagerduty_api_base_url']+method, args))
end

def primary_phone_number_for(user_id)
  contact_methods = pd_api_call("/users/#{user_id}/contact_methods")["contact_methods"]
  phone_numbers = contact_methods.select{|cm| cm["type"] == "phone_contact_method"}
  if phone_numbers.empty?
    raise Exception.new("No phone numbers for user #{user_id}!")
  end
  primary_phone_number = phone_numbers.first
  country_code = primary_phone_number["country_code"]
  subscriber_number = primary_phone_number["address"]
  e164_number = "+#{country_code}#{subscriber_number}"
  return e164_number
end

def users_oncall_for(escalation_policy_id)
  resp = pd_api_call("/oncalls?escalation_policy_ids[]=#{escalation_policy_id}")
  oncalls = resp["oncalls"]
  oncalls = oncalls.sort {|oncall| oncall["escalation_level"]}
  user_ids = oncalls.map{|oncall| oncall["user"]["id"]}
  return user_ids
end

def publish_call_redirection_for(escalation_policy_id)
  puts "Publishing for escalation policy #{escalation_policy_id}.."
  users = users_oncall_for(escalation_policy_id)
  sorted_escalation_numbers = users.map {|user_id| primary_phone_number_for(user_id)}

  # Template a Twilio TwiML document to redirect the call.
  twiml = <<-EOF
<?xml version="1.0" encoding="UTF-8"?>
<!-- #{DateTime.now.iso8601} -->
<Response>
  EOF
  sorted_escalation_numbers.each do |e164_number|
    twiml += "  <Dial "
    twiml += "timeout=\"#{CONFIG['redirection_dialing_timeout']}\" "
    twiml += "ringTone=\"#{CONFIG['dialing_ringtone']}\" "
    twiml += ">"
    twiml += e164_number
    twiml += "</Dial>"
    twiml += "\n"
  end
  twiml += "</Response>"
  puts "TwiML doc:"
  puts twiml

  # Upload the file to S3.
  credentials = Aws::Credentials.new(CONFIG['aws_access_key_id'],
                                     CONFIG['aws_secret_access_key'])
  s3 = Aws::S3::Client.new(region: "us-gov-west-1", credentials: credentials)
  bucket_key = "rotation/#{escalation_policy_id}.xml"
  s3.put_object(
      bucket: CONFIG['s3_bucket'],
      key: bucket_key,
      body: twiml,
      content_type: "text/xml",
      acl: "public-read"
  )
  puts "Successfully wrote #{bucket_key} to S3."
end

CONFIG['pagerduty_escalation_policies'].each do |pagerduty_escalation_policy_id|
  publish_call_redirection_for pagerduty_escalation_policy_id
end
