# Created by Thomas Balthazar, Copyright 2009
# This script is provided as is, and is released under the MIT license : http://www.opensource.org/licenses/mit-license.php
# more information here : http://suitmymind.com/2009/04/18/move-your-tickets-from-lighthouse-to-github/

require 'rubygems'
require 'lighthouse-api'
require 'yaml'
require 'uri'

# just pass the cmd string to curl, but run it silently and print the
# response if there was an error
def curl(cmd)
  begin
    gh_ret = `curl -s #{cmd}`
  rescue Exception
    warn "Request failed:\n"
    warn gh_return_value
    raise
  end
  return gh_ret
end

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
GITHUB_API_TOKEN  = "YOUR_API_TOKEN"
GITHUB_PROJECT    = "YOUR_GITHUB_PROJECT_NAME"


# do not modify
GITHUB_NEW_ISSUE_API_URL    = "https://github.com/api/v2/yaml/issues/open/#{GITHUB_LOGIN}/#{GITHUB_PROJECT}"
GITHUB_ADD_LABEL_API_URL    = "https://github.com/api/v2/yaml/issues/label/add/#{GITHUB_LOGIN}/#{GITHUB_PROJECT}"
GITHUB_ADD_COMMENT_API_URL  = "https://github.com/api/v2/yaml/issues/comment/#{GITHUB_LOGIN}/#{GITHUB_PROJECT}"


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
  
  # get the ticket versions/history
  versions = ticket.versions  
  
  # this is the assigned user name of the corresponding LH ticket  
  assignee = versions.last.assigned_user_name unless versions.last.attributes["assigned_user_name"].nil?  

  # why gsub? -> curl -F 'title=@xxx' -> 'title= @xxx' cause =@xxx means xxx is a file to upload http://curl.haxx.se/docs/manpage.html#-F--form
  puts "migrating issue \##{ticket.id} '#{ticket.title}'\n";

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
    
  # create the GH issue and get its newly created id
  gh_return_value = curl("-F 'login=#{GITHUB_LOGIN}' -F 'token=#{GITHUB_API_TOKEN}' -F 'title=#{title}' -F 'body=#{body}' #{GITHUB_NEW_ISSUE_API_URL}")
  gh_issue_id = YAML::load(gh_return_value)["issue"]["number"]

  # add comments to the newly created GH issue
  versions.each { |version|
    # add the LH comment title to the comment
    comment = "**#{version.title.gsub(/^@/," @").gsub(/'/,"&rsquo;")}**\n\n"
    comment+=version.body.gsub(/^@/," @").gsub(/'/,"&rsquo;") unless version.body.nil?
    comment+="\n\n by " + version.user_name.gsub(/^@/," @").gsub(/'/,"&rsquo;") unless version.user_name.nil?
    curl("-F 'login=#{GITHUB_LOGIN}' -F 'token=#{GITHUB_API_TOKEN}' -F 'comment=#{comment}' #{GITHUB_ADD_COMMENT_API_URL}/#{gh_issue_id}")
  }  
  
  # here you can specify the labels you want to be applied to your newly created GH issue
  # preapare the labels for the GH issue
  gh_labels = []
  lh_tags = ticket.tags
  # only migrate LIGHTHOUSE_TAGS_TO_KEEP tags if specified
  lh_tags.delete_if { |tag| !LIGHTHOUSE_TAGS_TO_KEEP.include?(tag) } unless LIGHTHOUSE_TAGS_TO_KEEP.nil?
  # these are the tags of the corresponding LH ticket, replace @ by # because @ will be used to tag assignees in GH
  gh_labels += lh_tags.map { |tag| tag.gsub(/^@/,"#") }  
  gh_labels << "|M| " + ticket.milestone_title unless ticket.attributes["milestone_title"].nil? # this is the milestone title of the corresponding LH ticket
  gh_labels << "@" + assignee unless assignee.nil?
  gh_labels << "|S| " + ticket.state # this is the state of the corresponding LH ticket
  gh_labels << "from-lighthouse" # this is a label that specify that this GH issue has been created from a LH ticket
  
  # tag the issue
  gh_labels.each { |label|
    # labels containing . do not work ... -> replace . by •
    label.gsub!(/\./,"•")
    curl("-F 'login=#{GITHUB_LOGIN}' -F 'token=#{GITHUB_API_TOKEN}' #{GITHUB_ADD_LABEL_API_URL}/#{URI.escape(label)}/#{gh_issue_id}")
  }
}
