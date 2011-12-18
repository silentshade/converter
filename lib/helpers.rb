class MediaFormatException < StandardError
end

module Log 
    def self.add(s)
      p s
      File.open('converter.log','a'){|f| f.write Time.now.to_s+" "+s.to_s+"\n"}
    end
end
