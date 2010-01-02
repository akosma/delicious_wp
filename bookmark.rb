class Bookmark
  attr_accessor :href
  attr_accessor :hash
  attr_accessor :tag
  attr_accessor :time
  attr_accessor :extended
  attr_accessor :description
  
  def tags
    template = "<a href=\"http://delicious.com/%s/%s\" target=\"_blank\">%s</a>"
    username = CONFIG['delicious']['username']
    tag.split.collect do |tag| 
      template % [username, tag, tag] 
    end.join(", ")
  end
  
  def date
    self.time.strftime("%A %d %B %Y")
  end
  
  def to_s
    "<a href=\"%s\" target=\"_blank\">%s</a> (%s)\n" % [href, description, self.tags]
  end
end
