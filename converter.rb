HM = '/srv/www/converter/htdocs/converter'
require 'yaml'
require './lib/core_ext'
o = YAML.load_file('./config/config.yml')
if %x[hostname].chomp == "dl1.mdtube.ru" 
  $options = o[:production]
  $options[:mode] = :production
else
  $options = o[:development]
  $options[:mode] = :development
end
$options[:conf] = o[:conf]
$options[:token] = rand(36**8).to_s(36)
require './lib/memq'
require 'json'
require 'net/http'
require 'uri'
require './lib/helpers'
require './lib/converter'
require './lib/stages'
Log.add "=== Start #{$options[:token]} ==="
Log.add("Running in #{$options[:mode]} mode")

if !ARGV.empty?
    $args = {}
    ARGV.each_with_index do |v,i| 
      if i.even?
        arg = ARGV[i..i+1]
        arg[0] = arg[0].gsub(/-*/,'')
        $args[arg[0].to_sym] = arg[1]
      end
    end
    movies = [] 
    if $args[:f] && File.directory?($args[:f])
      Log.add("Processing directory #{$args[:f]}...")
      d = Dir.new($args[:f])
      #entries = d.entries.sort
      #entries = d.sort_by{|f| File.mtime(args[:f]+f)}.entries
      #p d
      Log.add("File count: #{d.count - 2}")
      if $args[:time]
        Log.add("'Time' argument passed, searching for files starting at #{$args[:time]} modify time")
        entries = d.collect{|f| f if File.ctime($args[:f]+f) >= DateTime.strptime($args[:time],"%Y-%m-%d %H:%M:%S").to_time}
      elsif $args[:start]
        Log.add("'Start' argument passed, searching for file with name #{$args[:start]}")
        s = d.sort
        i = s.index{|f| File.basename(f,'.*') == $args[:start]}
        if i
          p i
          Log.add("File found, staring at #{$args[:start]}")
          entries = s.entries.values_at(i..-1)
        end
      end
      entries = entries.compact
      p entries
      entries.each do |f|
        #if File.extname(f) == '.404.404' || File.extname(f) == '.failed.404'
         #%x[mv #{ARGV[0]}#{f} #{ARGV[0]}#{File.basename(f,'.404')}]
        #end 
        if File.directory?($args[:f]+f) || File.extname(f) == '.404' || File.extname(f) == '.failed'
          next
        end
        if !File.size?($args[:f]+f)
          Log.add("File #{f} is zero size, skipping")
          next
        end
        Log.add("Adding file file #{f} to convertation queue")
        movies << "{\"file\":\""+f+"\",\"action\":1,\"path\":\""+$args[:f]+"\"}"
      end
    else
      movies << "{\"file\":\""+File.basename($args[:f])+"\",\"action\":1,\"path\":\""+File.dirname($args[:f])+"\/\"}"
    end
    $options['local'] = true
else 
    mem = MEMQ.new
    q = $options[:queueName]
    if mem.isEmpty? q
      Log.add 'Queue is empty, exiting'
      exit
    end

    movies = (mem.dequeue q, (mem.total q)).values
end
#p movies
movies.each do |movieString|
    movie = JSON.parse movieString
    if $options['local']
      p movie
      #p File.basename(File.basename(movieHash["file"],'.failed'),'.*')
      
      # Set the response uri
      uri = movie['domain'].blank? ? ($options[:mode] == :development ? URI.parse('http://api.mdtube.lan:3000') : URI.parse('http://api.mdtube.ru')) : "http://#{movie['domain']}"
      
      # Because of local mode, ensure that video still exists
      req = Net::HTTP::Get.new('/videos/exists?f='+File.basename(movie["file"],'.*'))
      http = Net::HTTP.new uri.host, uri.port                                                                                                                                                                                                                                                                  
      response = http.start do |http|
        http.request(req)
      end
      if response.code == "404"
        Log.add("File #{movie['file']} not in database. Moving to 404")                                                                                                                                                                                                                                                  
        %x[mv #{movie['path']}#{movie['file']} #{movie['path']}#{movie['file']}.404]
        next    
      end
      p response.body    
    end
    movie[:stage] = 0 if !movie[:stage]
    movie[:retry] = 0 if !movie[:retry]

    result = case movie[:stage]
      when 0 then Stages.stage0 movie
      when 1 then Stages.stage1 movie
      when 2 then Stages.stage2 movie
      when 3 then Stages.stage3 movie
      when 4 then Stages.stage3 movie
    end
    if !result.nil? && !$options['local']
      mem.enqueue q, result
    end
    #p result
end

