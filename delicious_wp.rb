#!/usr/bin/env ruby

# Copyright (c) 2009, akosma software / Adrian Kosmaczewski
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. All advertising materials mentioning features or use of this software
#    must display the following acknowledgement:
#    This product includes software developed by the akosma software.
# 4. Neither the name of the akosma software nor the
#    names of its contributors may be used to endorse or promote products
#    derived from this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY ADRIAN KOSMACZEWSKI ''AS IS'' AND ANY
# EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL ADRIAN KOSMACZEWSKI BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

require 'yaml'
require 'net/https'
require 'net/http'
require 'uri'
require 'xml'
require 'time'
require "xmlrpc/client"
$KCODE = 'u'

WEEK_SECONDS = 7 * 24 * 60 * 60

DELICIOUS_SERVER = 'api.del.icio.us'
DELICIOUS_PORT = 443
DELICIOUS_DATES_PATH = '/v1/posts/dates'
DELICIOUS_RECENT_PATH = '/v1/posts/recent?count=%d'
DELICIOUS_USER_AGENT = 'delicious_wp by akosma 1.1'

class Bookmark
  attr_accessor :href
  attr_accessor :hash
  attr_accessor :tag
  attr_accessor :time
  attr_accessor :extended
  attr_accessor :description
  
  def tags
    tag.split.collect do |tag| 
      "<a href=\"http://delicious.com/%s/%s\">%s</a>" % [CONFIG['delicious']['username'], tag, tag] 
    end.join(", ")
  end
  
  def date
    self.time.strftime("%A %d %B %Y")
  end
  
  def to_s
    "<a href=\"#{href}\">#{description}</a> (#{self.tags})\n"
  end
end

def get_delicious_bookmarks
  # Connect to delicious and get updates
  http = Net::HTTP.new(DELICIOUS_SERVER, DELICIOUS_PORT)
  http.use_ssl = true
  req = Net::HTTP::Get.new(DELICIOUS_DATES_PATH)
  req.add_field("User-Agent", DELICIOUS_USER_AGENT)
  req.basic_auth CONFIG['delicious']['username'], CONFIG['delicious']['password']
  response = http.request(req)
  results = response.body
  
  reader = XML::Reader.string(results)
  count = 0
  bookmarks = []
  now = Time.new
  
  while reader.read
    if reader.node_type == XML::Reader::TYPE_ELEMENT && reader.name == "date"
      reader.move_to_attribute "date"
      date = Time.parse(reader.value)
      
      if date > (now - WEEK_SECONDS)
        reader.move_to_attribute "count"
        count += reader.value.to_i
      end
    end
  end
  
  if count > 0
    # Limit the query, following the del.icio.us API docs
    count = 100 if count > 100

    # Recommended by the del.icio.us API docs
    sleep(1)

    # Now retrieve the N new entries
    req = Net::HTTP::Get.new(DELICIOUS_RECENT_PATH % count)
    req.basic_auth CONFIG['delicious']['username'], CONFIG['delicious']['password']
    req.add_field("User-Agent", DELICIOUS_USER_AGENT)
    response = http.request(req)
    results = response.body
  
    # Parse the XML
    reader = XML::Reader.string(results)

    while reader.read
      if reader.node_type == XML::Reader::TYPE_ELEMENT && reader.name == "post"
        bookmark = Bookmark.new
        reader.move_to_attribute "href"
        bookmark.href = reader.value
        reader.move_to_attribute "hash"
        bookmark.hash = reader.value
        reader.move_to_attribute "tag"
        bookmark.tag = reader.value
        reader.move_to_attribute "time"
        bookmark.time = Time.parse(reader.value)
        reader.move_to_attribute "extended"
        bookmark.extended = reader.value
        reader.move_to_attribute "description"
        bookmark.description = reader.value
        bookmarks << bookmark
      end
    end
  
    # Sort the bookmarks in place by descending time 
    bookmarks.sort! {|x, y| y.time <=> x.time }
  end
  
  bookmarks
end

def create_html(bookmarks)
  groups = []
  old_date = nil
  i = -1
  
  bookmarks.each do |bookmark|
    if bookmark.date != old_date
      old_date = bookmark.date
      groups << []
      i += 1
    end
    groups[i] << bookmark
  end

  lines = []
  groups.each do |array|
    lines << "<p>%s:</p>" % array[0].date
    lines << "<ul>"
    array.each do |bookmark|
      lines << "<li>%s</li>" % bookmark
    end
    lines << "</ul>"
  end

  lines << "<p>Generated by <a href=\"http://github.com/akosma/delicious_wp\" target=\"_blank\">delicious_wp by akosma</a></p>"
  lines.join
end

def post_to_wordpress(title, text)
  entry = {
    :title => title,
    :description => text
  }

  # Connect to Wordpress using the XML-RPC interface
  blog = XMLRPC::Client.new(CONFIG['wordpress']['server'], CONFIG['wordpress']['path'], CONFIG['wordpress']['port'])
  blog.call("metaWeblog.newPost", CONFIG['wordpress']['blogid'], 
             CONFIG['wordpress']['username'], CONFIG['wordpress']['password'], entry, true)
end

if File.exists?('config.yaml')
  CONFIG = YAML.load_file('config.yaml')
  bookmarks = get_delicious_bookmarks
  if bookmarks.length > 0
    entry = create_html(bookmarks)
    puts post_to_wordpress(CONFIG['wordpress']['post_title'], entry)
  else
    puts "No new bookmarks"
  end
else
  puts "You must create a config.yaml file"
end
