module MCP::Shared
  class ReadBuffer
    @buffer : IO::Memory = IO::Memory.new(1024)

    def append(chunk : String)
      append(chunk.to_slice)
    end

    def append(chunk : Bytes)
      current_pos = @buffer.pos
      @buffer.seek(0, IO::Seek::End)
      @buffer.write(chunk)
      @buffer.seek(current_pos)
    end

    # Attempts to read a complete JSON-RPC message.
    #
    # Searches only the *unread* suffix of the backing buffer for a newline,
    # so that consumed newlines from prior successful reads do not trigger
    # premature parsing of a fragmented message.
    def read_message : JSONRPCMessage?
      return nil if @buffer.empty?
      slice = @buffer.to_slice
      pos = @buffer.pos

      # Search only from the current read position forward
      unread = slice[pos, slice.size - pos]
      index = unread.index('\n'.ord.to_u8)
      return nil if index.nil?

      message = @buffer.gets

      return nil if message.nil? || message.blank?

      # Compact consumed bytes so the buffer doesn't grow without bound
      compact!

      JSONRPCMessage.from_json(message)
    end

    def clear
      @buffer.clear
    end

    # Discard already-consumed bytes from the front of the buffer, keeping
    # the read position relative to unread data.
    private def compact!
      pos = @buffer.pos
      return if pos == 0

      slice = @buffer.to_slice
      remaining = slice[pos, slice.size - pos]

      @buffer.clear
      @buffer.write(remaining)
      @buffer.rewind
    end
  end
end
