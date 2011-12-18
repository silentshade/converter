require 'memcached'
class MEMQ
    
    def initialize
	@mem = Memcached.new("localhost:11211")
    end
    
    def getInstance
	self.new if !@mem
	return @mem
    end
    
    def isEmpty?(q)
	if !self.exists? q
	    self.rst q
	    return true
	elsif @head.zero? && @tail.zero? || (@head == @tail)
	    return true
	end
	return false
    end

    def exists?(q)
	mem = @mem || self.getInstance
	begin
	    @head = mem.get q+"_head"
	    @tail = mem.get q+"_tail"
	rescue Exception => e
	    return false
	end
	if @head.class != Fixnum || @tail.class != Fixnum || @head > @tail
	    return false
	end
	return true
    end    

    def rst(q)
	mem = @mem || self.getInstance
	mem.set q+"_head", 0 
	mem.set q+"_tail", 0
	@head = @tail = 0 
	return true
    end
    
    def dequeue(q,r = 1)
	mem = @mem || self.getInstance
	return nil if self.isEmpty? q
	if r.class == Fixnum
	    if (@tail+1) - (r + @head) > 0
		keys = (@head...(@head+r)).to_a
		mem.set q+"_head", @head+=r
	    else
		keys = (@head...@tail).to_a
		self.rst q
	    end
	    res = mem.get keys.map{|e| q+"_"+e.to_s}
	else
	    raise "Incorrect keynum" 
	end
    end
    
    def enqueue(q,v)
	mem = @mem || self.getInstance
	self.rst q if !self.exists? q
	mem.set q+"_tail", @tail+1
	mem.set q+"_"+@tail.to_s, v
    end
    
    def total(q)
	mem = @mem || self.getInstance
	if !self.exists? q
	    self.rst q 
	    return 0
	end
	@head = mem.get q+"_head"
	@tail = mem.get q+"_tail"
	(@tail-@head)
    end
end
