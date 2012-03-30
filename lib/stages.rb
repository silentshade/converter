module Stages
    def self.retval(m,msg = 'Unknown error')
      Log.add "Stage #{m['stage']} result:"
      if !$options['local']
        if m['retry'] <= $options[:maxRetries]
          Log.add "#{msg}. Sending back to queue, retry count: #{m['retry']}."
          return m
        else
          Log.add "#{msg}. Maximum retry count #{$options[:maxRetries]} exceeded."
          Log.add "Moving #{o[:fname]} to '.failed' as no convertion succeded"
          %x[mv #{$options[:filepath]} #{$options[:filepath]}.failed]
          Log.add "Sending"
          postdata = {
            :id => m['id'],
            :filename => m[:opts][:fname],
          }.to_json
          request = Response.prepare m
          request.set_form_data(:success => 'false', :data => postdata)
          response = Response.send request
          Log.add "Frontend responded: #{response.code} #{response.message}"
          return nil
        end
      else
        Log.add "#{msg}. Local execution detected, skipping queue."
        return nil
      end
    end
    
    # Getting file
    def self.stage0(m)

      if m['path']
        $options[:filepath] = m['path']
      elsif m['action'].to_i == 2
        $options[:filepath] = $options[:origVideo]
      else
        $options[:filepath] = $options[:uploadPath]
      end
      $options[:filepath] += m['file']

      if !File.file?($options[:filepath])
        m['retry']+=1
        retval = self.retval m,"File not found: #{$options[:filepath]}"
        return retval
      end
      Log.add("Got new file to convert: #{$options[:filepath]}")
      m["stage"]+=1
      self.stage1 m
    end

    # Calculating options
    def self.stage1(m) 
      info = Converter.parse $options[:filepath]
      if !info || info[:general][:dur].to_s.empty? || info[:video][:bitrate].to_s.empty?
        m['retry']+=1
        retval = self.retval m,"Could not get movide information: #{$options[:filepath]}"
        return retval
      end
      o = {:res => {}}
      info[:audio][:bitrate] = info[:audio][:bitrate].to_i/1000
      dar = info[:video][:dar].to_f
      basicDar = info[:video][:basicDar] = dar < 1.778 ? '1.333' : '1.778'
      par = info[:video][:par].to_f
      w = info[:video][:width].to_i
      h = info[:video][:height].to_i

      $options[:conf][basicDar.to_sym].each do |k,v|

        if w.to_f >= v[:w].to_f || h.to_f >= v[:h].to_f
          key = (k.to_s.split('x')[1]+"p").to_sym

=begin
                width = (dar*v[:h].to_f).floor
                width = width.odd? ? width+1 : width

                if width <= v[:w]
                    targetRes = width.to_s+":"+v[:h].to_s
                else
                    height = (v[:w]/dar).floor
                    height = height.odd? ? height+1 : height
                    targetRes = v[:w].to_s+":"+height.to_s
                end
=end
          o[:res][key] = v.merge({
            :targetRes => "#{v[:w]}:#{v[:h]}",
            :bitrate => v[:vbitrate].to_i < info[:video][:bitrate].to_i ? "#{v[:vbitrate].to_i/1000}" : "#{info[:video][:bitrate].to_i/1000}",
	          :addopts =>  info[:video][:frmode] == "VFR" ? "-noskip" : "",
	          :fps => info[:video][:fps],
            :targetAudioSrate => info[:audio][:srate].to_i > v[:srate] ? v[:srate].to_s : info[:audio][:srate].to_s,
            :targetAudioBitrate => info[:audio][:bitrate] > v[:abitrate] ? v[:abitrate].to_s : info[:audio][:bitrate].to_s
          })

        end
      end

      o[:fname] = m['file'].split('.')[0]
      o[:tpath] = "#{$options[:tmpPath]}/#{o[:fname]}/"
      o[:info] = info
      Log.recursive_add o

      m[:opts] = o

      m["stage"]+=1
      self.stage2 m
    end

    # Making screenshots  
    def self.stage2(m)
      o = m[:opts]
      %x[/bin/mkdir #{o[:tpath]}]
      res = Converter.screenshots m,o
      %x[/bin/rm -rf #{o[:tpath]}]
      if res.any?
        m["stage"]+=1
      else
        m['retry']+=1
        retval = self.retval m,"Could not create screenshots for #{o[:fname]}"
        return retval        
      end
      self.stage3 m
    end

    # Converting video
    def self.stage3(m)
      o = m[:opts]
      %x[/bin/mkdir #{o[:tpath]}]
      m[:opts] = Converter.convert! m,o
      %x[/bin/rm -rf #{o[:tpath]}]
      if m[:opts][:res].map{|k,v| v[:success]}.all?
        m["stage"]+=1
      elsif m[:opts][:res].map{|k,v| v[:success]}.any?
        m['retry']+=1
        retval = self.retval m,"Could not convert #{o[:fname]} at least to one of target resolutions"
        return retval
      else
        m['retry']+=1
        retval = self.retval m,"Could not convert #{o[:fname]} to any of target resolutions"
        return retval
      end
      self.stage4 m
    end

  # Response    
    def self.stage4(m)
      cmd = 'mv '+$options[:filepath]+' '+$options[:outBasePath]+'video/orig/'+m['file']+' 2>&1'
      Log.add "Dummy move here.."
      #Converter.execute(cmd)
    end
    
end
