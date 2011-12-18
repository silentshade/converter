HM = '/srv/www/converter/htdocs/converter'
require HM+'/lib/memq'
require 'json'
require 'yaml'
require 'net/http'
require 'uri'
$options = YAML.load_file('config/config.yml')
require HM+'/lib/helpers'
require HM+'/lib/converter'
require HM+'/lib/stages'

if !ARGV.empty?
    args = {}
    ARGV.each_with_index do |v,i| 
      if i.even?
        arg = ARGV[i..i+1]
        arg[0] = arg[0].gsub(/-*/,'')
        args[arg[0].to_sym] = arg[1]
      end
    end
    movies = [] 
    if args[:f] && File.directory?(args[:f])
      Log.add("Processing directory #{args[:f]}...")
      d = Dir.new(args[:f])
      #entries = d.entries.sort
      #entries = d.sort_by{|f| File.mtime(args[:f]+f)}.entries
      #p d
      Log.add("File count: #{d.count - 2}")
      if args[:time]
        Log.add("'Time' argument passed, searching for files starting at #{args[:time]} modify time")
        entries = d.collect{|f| f if File.ctime(args[:f]+f) >= DateTime.strptime(args[:time],"%Y-%m-%d %H:%M:%S").to_time}
      elsif args[:start]
        Log.add("'Start' argument passed, searching for file with name #{args[:start]}")
        s = d.sort
        i = s.index{|f| File.basename(f,'.*') == args[:start]}
        if i
          p i
          Log.add("File found, staring at #{args[:start]}")
          entries = s.entries.values_at(i..-1)
        end
      end
      entries = entries.compact
      p entries
      entries.each do |f|
        #if File.extname(f) == '.404.404' || File.extname(f) == '.failed.404'
         #%x[mv #{ARGV[0]}#{f} #{ARGV[0]}#{File.basename(f,'.404')}]
        #end 
        if File.directory?(args[:f]+f) || File.extname(f) == '.404' || File.extname(f) == '.failed'
          next
        end
        if !File.size?(args[:f]+f)
          Log.add("File #{f} is zero size, skipping")
          next
        end
        Log.add("Adding file file #{f} to convertation queue")
        movies << "{\"file\":\""+f+"\",\"action\":1,\"path\":\""+args[:f]+"\"}"
      end
    else
      movies << "{\"file\":\""+File.basename(args[:f])+"\",\"action\":1,\"path\":\""+File.dirname(args[:f])+"\/\"}"
    end
    $options['local'] = true
else 
    mem = MEMQ.new
    if mem.isEmpty? 'converter'
      Log.add 'Queue is empty, exiting'
      exit
    end

    movies = (mem.dequeue 'converter', (mem.total 'converter')).values
end
#p movies
movies.each do |movie|
    movieHash = JSON.parse movie
    if $options['local']
      #p File.basename(File.basename(movieHash["file"],'.failed'),'.*')
      uri = URI.parse('http://mdtube.ru')
      req = Net::HTTP::Get.new('/api/videos/exists?f='+File.basename(movieHash["file"],'.*'))
      http = Net::HTTP.new uri.host, uri.port                                                                                                                                                                                                                                                                  
      response = http.start do |http|
        http.request(req)
      end
      if response.code == "404"
        Log.add("File #{movieHash['file']} not in database. Moving to 404")                                                                                                                                                                                                                                                  
        %x[mv #{movieHash['path']}#{movieHash['file']} #{movieHash['path']}#{movieHash['file']}.404]
        next    
      end
      p response.body    
    end
    movieHash[:stage] = 0 if !movieHash[:stage]
    movieHash[:retry] = 0 if !movieHash[:retry]

    result = case movieHash[:stage]
      when 0 then Stages.stage0 movieHash
      when 1 then Stages.stage1 movieHash
      when 2 then Stages.stage2 movieHash
      when 3 then Stages.stage3 movieHash
    end
    #p result
end

