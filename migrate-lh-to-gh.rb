# Created by Thomas Balthazar, Copyright 2009
# This script is provided as is, and is released under the MIT license : http://www.opensource.org/licenses/mit-license.php
# more information here : http://suitmymind.com/2009/04/18/move-your-tickets-from-lighthouse-to-github/

require 'rubygems'
require 'lighthouse-api'
require 'yaml'
require 'uri'

# -----------------------------------------------------------------------------------------------
# --- Lighthouse configuration
LIGHTHOUSE_ACCOUNT      = 'YOUR_ACCOUNT_NAME'
LIGHTHOUSE_API_TOKEN    = 'YOUR_API_TOKEN'
LIGHTHOUSE_PROJECT_ID   = YOUR_PROJECT_ID
LIGHTHOUSE_TICKET_QUERY = "state:open"


# -----------------------------------------------------------------------------------------------
# --- Github configuration
GITHUB_LOGIN      = "YOUR_ACCOUNT_NAME"
GITHUB_API_TOKEN  = "YOUR_API_TOKEN"
GITHUB_PROJECT    = "YOUR_GITHUB_PROJECT_NAME"

# do not modify
GITHUB_NEW_ISSUE_API_URL    = "https://github.com/api/v2/yaml/issues/open/#{GITHUB_LOGIN}/#{GITHUB_PROJECT}"
GITHUB_ADD_LABEL_API_URL    = "https://github.com/api/v2/yaml/issues/label/add/#{GITHUB_LOGIN}/#{GITHUB_PROJECT}"


# -----------------------------------------------------------------------------------------------
# --- setup LH
Lighthouse.account  = LIGHTHOUSE_ACCOUNT
Lighthouse.token    = LIGHTHOUSE_API_TOKEN
project             = Lighthouse::Project.find(LIGHTHOUSE_PROJECT_ID)


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
  
  title = ticket.title
  body  = ""

  # get the ticket versions/history
  ticket.versions.each { |version|
    # create a title for each new ticket history/version
    unless version.title==ticket.versions.first.title && version.body==ticket.versions.first.body
      body+="\n\n**#{version.title}**\n" 
      version.title.length.times do |i|
        body+="-"
      end
      body+="\n"
    end
    # gsub : curl -F 'body=@xxx' -> 'body= @xxx' cause =@xxx means xxx is a file to upload http://curl.haxx.se/docs/manpage.html#-F--form
    body+=version.body.gsub(/^@/," @") unless version.body.nil? 
  }
  
  # add the original LH ticket URL at the end of the body
  body+="\n\n[original LH ticket](#{ticket.url})"
  
  # escape single quote
  title.gsub!(/'/,"&rsquo;").gsub!(/^@/," @")
  body.gsub!(/'/,"&rsquo;")
  
  # create the GH issue and get its newly created id
  gh_return_value = `curl -F 'login=#{GITHUB_LOGIN}' -F 'token=#{GITHUB_API_TOKEN}' -F 'title=#{title}' -F 'body=#{body}' #{GITHUB_NEW_ISSUE_API_URL}`
  gh_issue_id = YAML::load(gh_return_value)["issue"]["number"]
  
  # here you can specify the labels you want to be applied to your newly created GH issue
  # preapare the labels for the GH issue
  gh_labels = []
  # these are the tags of the corresponding LH ticket, replace @ by # because @ will be used to tag assignees in GH
  gh_labels += ticket.tags.map { |tag| tag.gsub("@","#") }  
  gh_labels << ticket.milestone_title if ticket.responds_to?(:milestone_title) # this is the milestone title of the corresponding LH ticket
  gh_labels << "@" + ticket.versions.last.assigned_user_name unless ticket.versions.last.attributes["assigned_user_name"].nil?  # this is the assigned user name of the corresponding LH ticket
  gh_labels << ticket.state # this is the state of the corresponding LH ticket
  gh_labels << "from-lighthouse" # this is a label that specify that this GH issue has been created from a LH ticket
    
  # tag the issue
  gh_labels.each { |label|
    `curl -F 'login=#{GITHUB_LOGIN}' -F 'token=#{GITHUB_API_TOKEN}' #{GITHUB_ADD_LABEL_API_URL}/#{URI.escape(label)}/#{gh_issue_id}`
  }
}