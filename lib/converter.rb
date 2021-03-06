module Converter
    def self.parse(file)
      movieInfo = {:general => {},:video => {}, :audio => {}}
      movieInfo[:general][:dur],
      movieInfo[:general][:durs],
      movieInfo[:general][:container] = (%x[ mediainfo --Inform="file://g.txt" #{file} ]).strip.split('|')

      movieInfo[:video][:bitrate],
      movieInfo[:video][:fps],
      movieInfo[:video][:fpsmin],
      movieInfo[:video][:fpsmax],
      movieInfo[:video][:frmode],
      movieInfo[:video][:framecount],
      movieInfo[:video][:scantype],
      movieInfo[:video][:format],
      movieInfo[:video][:formatp],
      movieInfo[:video][:width],
      movieInfo[:video][:height],
      movieInfo[:video][:dar],
      movieInfo[:video][:par],
      movieInfo[:video][:standard] = (%x[ mediainfo --Inform="file://v.txt" #{file} ]).strip.split('|')

      movieInfo[:audio][:bitrate],
      movieInfo[:audio][:srate],
      movieInfo[:audio][:format],
      movieInfo[:audio][:formatp] = (%x[ mediainfo --Inform="file://a.txt" #{file} ]).strip.split('|')
      return movieInfo
    end

    def self.execute(c)
      Log.add "Executing command: #{c}"
      begin
        %x[#{c}]
        raise MediaFormatException if $?.exitstatus != 0
        return true
      rescue MediaFormatException
        Log.add "Command unsuccessfull: #{c}, with exitstatus #{$?.exitstatus}"
        return false
      end
    end

    def self.convert!(m,o)
      request = Response.prepare m
      o[:res].each do |k,v|
        resDir = "#{o[:tpath]}#{k}/"
        outfile = $options[:outBasePath]+'video/'+k.to_s+'/'+o[:fname]+'.mp4'
        result = []
        %x[mkdir #{resDir}]
        cmds = [
          'mencoder -af volnorm=2 -oac faac -faacopts br='+v[:targetAudioBitrate]+ \
          ':mpeg=4:object=2 -channels 2 -srate '+v[:srate].to_s+' -ovc x264 -x264encopts bitrate='+v[:bitrate]+':'+v[:x264encopts]+ \
          ' -ofps '+v[:fps]+' '+v[:addopts]+' -vf pp=hb/vb/lb,dsize='+v[:targetRes]+':0,scale=-8:-8,harddup '+m[:filepath]+' -o '+resDir+'tmp.avi',

          #'mencoder -of rawvideo -nosound -ovc x264 -x264encopts bitrate='+v[:bitrate]+':'+v[:x264encopts]+ \
          #' -ofps '+v[:fps]+' -vf pp=hb/vb/lb,dsize='+v[:targetRes]+':0,scale=-8:-8,harddup '+m[:filepath]+' -o '+resDir+'tmp.h264',
          
          'mencoder '+resDir+'tmp.avi -ovc copy -oac copy -of rawvideo -o '+resDir+'tmp.h264 -nosound 2>&1',
          'mencoder '+resDir+'tmp.avi -ovc copy -oac copy -of rawaudio -o '+resDir+'tmp.aac 2>&1',
          #'mplayer '+m[:filepath]+' -vc dummy -ao pcm:fast:file='+resDir+'tmp.wav',
          #'neroAacEnc -cbr '+(v[:targetAudioBitrate].to_i*1000).to_s+' -if '+resDir+'tmp.wav -of '+resDir+'tmp.m4a',
          'MP4Box -add '+resDir+'tmp.h264 -fps '+o[:info][:video][:fps]+' -add '+resDir+'tmp.aac '+resDir+'tmp.mp4 2>&1',
          'mv '+resDir+'tmp.mp4 '+outfile+' 2>&1'
        ]
        cmds.each do |cmd| 
          #p cmd 
          result.push self.execute(cmd)
        end
        Log.add "#{k} command summary: #{result.join(', ')}"

        if result.all?
          info = Converter.parse outfile
          o[:res][k][:success] = true
          postdata = {
            :id => m[:id],
            :filename => o[:fname],
            :duration => info[:general][:dur],
            :formats => {
              k => {
                :path => v[:httpPath],
                :video => {
                  :bitrate => info[:video][:bitrate],
                  :fps => info[:video][:fps],
                  :dar => info[:video][:dar],
                  :par => info[:video][:par],
                  :profile => v[:x264p],
                  :opts => v[:x264encopts],
                  :resoltution => info[:video][:width].to_s+'x'+info[:video][:height].to_s,
                  :wasinterlaced => o[:info][:video][:scantype] == 'Progressive' ? false : true
                },
                :audio => {
                  :bitrate => info[:audio][:bitrate],
                  :samplerate => info[:audio][:srate],            
                }
              }
            }
          }.to_json
          p postdata
          #if (!$options['local'])
            #uri = URI.parse('http://'+m[:domain]+m[:respond_to])
            request.set_form_data(:success => 'true', :data => postdata)
            response = Response.send request
            #if response.code == "404"
            #  Log.add("File #{o[:fname]} not in database. Moving to 404")
            #  %x[mv #{m[:filepath]} #{m[:filepath]}.404]
            #end
            p response.code
            p response.message
          #end
          #p response.body
        else
          Log.add("File #{o[:fname]} convertion to #{k} failed.")
          o[:res][k][:success] = false          
        end
      end
      if !o[:res].map{|k,v| v[:success]}.any?
        #Log.add "Moving #{o[:fname]} to '.failed' as no convertion succeded"
        #%x[mv #{m[:filepath]} #{m[:filepath]}.failed]
      end
      return o
    end
    
    def self.screenshots(m,o)
      highestRes = o[:res].keys.last
      %x[/bin/mkdir #{o[:tpath]+'scr/'}]
      seconds = (o[:info][:general][:dur].to_i/1000).floor
      position = ((seconds/$options[:scrNum])/2).floor
      step = position
      
      result = []
      cmds = []
      (1..$options[:scrNum]).each do |pass|
        #position = seconds-5 if position >= seconds-5
        scale = o[:info][:video][:basicDar] == '1.333'? '93:70' : '125:70'

        cmds << 'mplayer -vf scale='+scale+',crop=92:70 -frames 1 -vo jpeg:quality=70:outdir='+o[:tpath]+'scr/ -nosound -ss '+position.to_s+' '+m[:filepath]
        cmds << 'mv '+o[:tpath]+'scr/00000001.jpg '+$options[:outBasePath]+'scr/small/'+o[:fname]+'_'+pass.to_s+'.jpg'

        scale = o[:info][:video][:basicDar] == '1.333'? '198:149' : '264:149'

        cmds << 'mplayer -vf scale='+scale+',crop=200:149 -frames 1 -vo jpeg:quality=70:outdir='+o[:tpath]+'scr/ -nosound -ss '+position.to_s+' '+m[:filepath]
        cmds << 'mv '+o[:tpath]+'scr/00000001.jpg '+$options[:outBasePath]+'scr/large/'+o[:fname]+'_'+pass.to_s+'.jpg'
        

        cmds << 'mplayer -frames 1 -vo jpeg:quality=70:outdir='+o[:tpath]+'scr/ -nosound -ss '+position.to_s+' '+m[:filepath]
        cmds << 'mv '+o[:tpath]+'scr/00000001.jpg '+$options[:outBasePath]+'scr/orig/'+o[:fname]+'_'+pass.to_s+'.jpg'

        position += step
      end
      cmds.each do |cmd|
        result.push self.execute(cmd)
      end
      Log.add "Screenshots command summary: #{result.join(', ')}"
      return result
    end
end
