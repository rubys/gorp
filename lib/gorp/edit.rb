class String
  def unindent(n)
    gsub Regexp.new("^#{' '*n}"), ''
  end
  def indent(n)
    gsub /^/, ' '*n
  end
end

module Gorp_string_editing_functions
  def highlight
    if self =~ /\n\z/
      self[/(.*)/m,1] = "#START_HIGHLIGHT\n#{self}#END_HIGHLIGHT\n"
    else
      self[/(.*)/m,1] = "#START_HIGHLIGHT\n#{self}\n#END_HIGHLIGHT"
    end
  end

  def mark name
    return unless name
    self[/(.*)/m,1] = "#START:#{name}\n#{self}#END:#{name}\n"
  end

  def edit(from, *options)
    STDERR.puts options.inspect
    STDERR.puts options.last.inspect
    STDERR.puts options.last.respond_to? :[]
    if from.instance_of? String
      from = Regexp.new('.*' + Regexp.escape(from) + '.*')
    end

    sub!(from) do |base|
      base.extend Gorp_string_editing_functions
      yield base if block_given?
      base.highlight if options.include? :highlight
      base.mark(options.last[:mark]) if options.last.respond_to? :key
      base
    end
  end

  def dcl(name, *options)
    self.sub!(/(\s*)(class|def|test)\s+"?#{name}"?.*?\n\1end\n/mo) do |lines|
      lines.extend Gorp_string_editing_functions
      yield lines
      lines.mark(options.last[:mark]) if options.last.respond_to? :[]
      lines
    end
  end

  def clear_highlights
    self.gsub! /^\s*(#|<!--)\s*(START|END)_HIGHLIGHT(\s*-->)?\n/, ''
    self.gsub! /^\s*(#|<!--)\s*(START|END)_HIGHLIGHT(\s*-->)?\n/, ''
  end

  def clear_all_marks
    self.gsub! /^ *#\s?(START|END)(_HIGHLIGHT|:\w+)\n/, ''
  end

  def msub pattern, replacement
    self[pattern, 1] = replacement
  end

  def all=replacement
    self[/(.*)/m,1]=replacement
  end
end

def edit filename, tag=nil
  $x.pre "edit #{filename}", :class=>'stdin'

  stale = File.mtime(filename) rescue Time.now-2
  data = open(filename) {|file| file.read} rescue ''
  before = data.split("\n")

  begin
    data.extend Gorp_string_editing_functions
    yield data

    now = Time.now
    usec = now.usec/1000000.0
    sleep 1-usec if now-usec <= stale
    open(filename,'w') {|file| file.write data}
    File.utime(stale+2, stale+2, filename) if File.mtime(filename) <= stale

  rescue Exception => e
    $x.pre :class => 'traceback' do
      STDERR.puts e.inspect
      $x.text! "#{e.inspect}\n"
      e.backtrace.each {|line| $x.text! "  #{line}\n"}
    end
    tag = nil

  ensure
    log :edit, filename

    include = tag.nil?
    hilight = false
    data.split("\n").each do |line|
      if line =~ /START:(\w+)/
        include = true if $1 == tag
      elsif line =~ /END:(\w+)/
        include = false if $1 == tag
      elsif line =~ /START_HIGHLIGHT/
        hilight = true
      elsif line =~ /END_HIGHLIGHT/
        hilight = false
      elsif include
        if hilight or ! before.include?(line)
          outclass='hilight'
        else
          outclass='stdout'
        end

        if line.empty?
          $x.pre ' ', :class=>outclass
        else
          $x.pre line, :class=>outclass
        end
      end
    end
  end
end

def read name
  open(File.join($DATA, name)) {|file| file.read}
end

