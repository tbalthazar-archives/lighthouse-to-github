# Created by Thomas Balthazar, Copyright 2009
# Updated for GitHub Issues API v3 by Chris Peplin, Copyright 2011
# This script is provided as is, and is released under the MIT license : http://www.opensource.org/licenses/mit-license.php
# more information here : http://suitmymind.com/2009/04/18/move-your-tickets-from-lighthouse-to-github/

require 'rubygems'
require 'lighthouse-api'
require 'yaml'
require 'uri'
require 'net/http'

# -----------------------------------------------------------------------------------------------
# --- Lighthouse configuration
LIGHTHOUSE_ACCOUNT      = 'YOUR_ACCOUNT_NAME'
LIGHTHOUSE_API_TOKEN    = 'YOUR_API_TOKEN'
LIGHTHOUSE_PROJECT_ID   = YOUR_PROJECT_ID
LIGHTHOUSE_TICKET_QUERY = "state:open"
# Specify an array of tags here, and only those tags will be migrated. If nil is specified, all the tags will be migrated
LIGHTHOUSE_TAGS_TO_KEEP = nil


# -----------------------------------------------------------------------------------------------
# --- Github configuration
GITHUB_LOGIN      = "YOUR_ACCOUNT_NAME"
GITHUB_PASSWORD   = "YOUR_ACCOUNT_PASSWORD"
GITHUB_PROJECT    = "YOUR_GITHUB_PROJECT_NAME"


# do not modify
GITHUB_API_URL = "api.github.com"
GITHUB_NEW_ISSUE_API_URL    = "/repos/#{GITHUB_LOGIN}/#{GITHUB_PROJECT}/issues"
GITHUB_MILESTONE_API_URL    = "/repos/#{GITHUB_LOGIN}/#{GITHUB_PROJECT}/milestones"
GITHUB_LABEL_API_URL    = "/repos/#{GITHUB_LOGIN}/#{GITHUB_PROJECT}/labels"
GITHUB_COMMENTS_API_URL    = "/repos/#{GITHUB_LOGIN}/#{GITHUB_PROJECT}/issues/%s/comments"


# -----------------------------------------------------------------------------------------------
# --- setup LH
Lighthouse.account  = LIGHTHOUSE_ACCOUNT
Lighthouse.token    = LIGHTHOUSE_API_TOKEN
project             = Lighthouse::Project.find(LIGHTHOUSE_PROJECT_ID)


GH_MILESTONES = {}

def get_or_create_milestone(project, milestone_id)
  return if milestone_id.nil?
  lh_milestone = Lighthouse::Milestone.find(milestone_id,
      :params => {:project_id => project.id})
  payload = {"title" => lh_milestone.title, "due_on" => lh_milestone.due_on}

  begin
    milestone = make_request(GITHUB_MILESTONE_API_URL, payload)
    GH_MILESTONES[milestone_id] = milestone
    milestone
  rescue
    GH_MILESTONES[milestone_id]
  end
end

def create_issue(title, body, state, milestone, labels)
  labels.each do |label|
    begin
      make_request(GITHUB_LABEL_API_URL, {"name" => label})
    rescue
    end
  end
  payload = {"title" => title, "body" => body, "labels" => labels}
  payload["milestone"] = milestone[:id] if milestone and milestone[:id]

  new_issue = make_request(GITHUB_NEW_ISSUE_API_URL, payload)
end

def add_comment(issue, comment)
  payload = {"body" => comment}

  new_comment = make_request(GITHUB_COMMENTS_API_URL % issue["number"], payload)
end

def make_request(url, payload)
  request = Net::HTTP::Post.new(url,
      initheader = {'Content-Type' => 'application/json'})
  request.basic_auth GITHUB_LOGIN, GITHUB_PASSWORD
  request.body = payload.to_json

  http = Net::HTTP.new(GITHUB_API_URL, 443)
  http.use_ssl = true
  # Insecure, but required to get around a bug in Ruby 1.9.2's OpenSSL
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE
  response = http.request(request)
  if response.code != "200" and response.code != "201"
    raise
  end
  JSON.parse(response.body)
end

# -----------------------------------------------------------------------------------------------
# --- get all the LH tickts, page per page (the LH API returns 30 tickets at a time)
page        = 1
tickets     = []
tmp_tickets = project.tickets(:q => LIGHTHOUSE_TICKET_QUERY, :page => page)
while tmp_tickets.length > 0
  tickets += tmp_tickets
  page+=1
  tmp_tickets = project.tickets(:q => LIGHTHOUSE_TICKET_QUERY, :page => page)
end
puts "#{tickets.length} will be migrated from Lighthouse to Github.\n\n"


# -----------------------------------------------------------------------------------------------
# --- for each LH ticket, create a GH issue, and tag it
tickets.each { |ticket|
  # fetch the ticket individually to have the different 'versions'
  ticket = Lighthouse::Ticket.find(ticket.id, :params => { :project_id => LIGHTHOUSE_PROJECT_ID})

  # get the ticket versions/history
  versions = ticket.versions

  # this is the assigned user name of the corresponding LH ticket
  assignee = versions.last.assigned_user_name unless versions.last.attributes["assigned_user_name"].nil?

  # why gsub? -> curl -F 'title=@xxx' -> 'title= @xxx' cause =@xxx means xxx is a file to upload http://curl.haxx.se/docs/manpage.html#-F--form
  title = ticket.title.gsub(/^@/," @")
  body  = versions.first.body.gsub(/^@/," @") unless versions.first.body.nil?
  body||=""

  # add the original LH ticket URL at the end of the body
  body+="\n\n[original LH ticket](#{ticket.url})"

  # add the number of attachments
  body+="\n\n This ticket has #{ticket.attachments_count} attachment(s)." unless ticket.attributes["attachments_count"].nil?

  # escape single quote
  title.gsub!(/'/,"&rsquo;")
  body.gsub!(/'/,"&rsquo;")

  # the first version contains the initial ticket body
  versions.delete_at(0)

  # here you can specify the labels you want to be applied to your newly created GH issue
  # preapare the labels for the GH issue
  gh_labels = []
  lh_tags = ticket.tags
  # only migrate LIGHTHOUSE_TAGS_TO_KEEP tags if specified
  lh_tags.delete_if { |tag| !LIGHTHOUSE_TAGS_TO_KEEP.include?(tag) } unless LIGHTHOUSE_TAGS_TO_KEEP.nil?
  # these are the tags of the corresponding LH ticket, replace @ by # because @ will be used to tag assignees in GH
  gh_labels += lh_tags.map { |tag| tag.gsub(/^@/,"#") }
  gh_labels << "@" + assignee unless assignee.nil?
  gh_labels << "|S| " + ticket.state # this is the state of the corresponding LH ticket
  gh_labels << "from-lighthouse" # this is a label that specify that this GH issue has been created from a LH ticket

  # create the GH issue and get its newly created id
  milestone = get_or_create_milestone(project, ticket.milestone_id)
  issue = create_issue(title, body, ticket.state, milestone, gh_labels)

  # add comments to the newly created GH issue
  versions.each { |version|
    # add the LH comment title to the comment
    comment = "**#{version.title.gsub(/^@/," @").gsub(/'/,"&rsquo;")}**\n\n"
    comment+=version.body.gsub(/^@/," @").gsub(/'/,"&rsquo;") unless version.body.nil?
    comment+="\n\n by " + version.user_name.gsub(/^@/," @").gsub(/'/,"&rsquo;") unless version.user_name.nil?
    add_comment(issue, comment)
  }
}
