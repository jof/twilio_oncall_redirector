Twilio On-Call Redirector
======

This utility is intended to enable the creation of a Twilio phone number that
redirects incoming calls to whomever is on-call at the time.

Setup
=====
* Create a read-only Pagerduty API token for your instance.
* Create an S3 bucket for static file hosting (e.g. twiliooncallredirector.ops.example.com)
* Create a matching Amazon AWS IAM user with PutObject permissions on this new bucket.

Usage
=====
* Clone this utility repo into a container, VM, or host somewhere with Internet access.
* Run "bundle install --standalone"
* Edit the config.yaml to include your:
    * Pagerduty API token
    * Pagerduty API endpoint
    * Pagerduty schedule IDs to generate TwiML for
    * AWS account keys
    * S3 bucket name
* Call "bundle exec ./oncall.rb" from cron periodically.
* Setup inbound phone numbers in Twilio and point them at the new TwiML files in the S3 bucket.
