class MediaFormatException < StandardError
end

module Log
    require 'yaml'

    def self.add(s)
      p s
      File.open('converter.log','a'){|f| f.write "#{Time.now} #{$options[:token]} #{s}\n"}
    end

    def self.recursive_add(obj, level = 0)
      tabs = ""
      if level > 0
        level.times {|i| tabs << " "}
      end

      obj.each do |k,v|
        if v.is_a?(Hash)
          self.add "#{tabs}#{k}:"
          self.recursive_add v, level += 1
        elsif v.is_a?(Array)
          self.add "#{tabs}#{k}: #{v.join(', ')}"
        else
          self.add "#{tabs}#{k}: #{v}"
        end
      end
    end

end
