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

    # Attempts to read a complete JSON-RPC message
    def read_message : JSONRPCMessage?
      unread = unread_slice
      return nil if unread.empty?
      index = unread.index('\n'.ord.to_u8)
      return nil if index.nil?

      message = @buffer.gets
      compact_consumed_bytes

      return nil if message.nil? || message.blank?

      JSONRPCMessage.from_json(message)
    end

    def clear
      @buffer.clear
    end

    private def unread_slice : Bytes
      slice = @buffer.to_slice
      pos = @buffer.pos
      return Bytes.empty if pos >= slice.size
      slice[pos, slice.size - pos]
    end

    private def compact_consumed_bytes
      slice = @buffer.to_slice
      pos = @buffer.pos
      return if pos <= 0

      if pos >= slice.size
        @buffer.clear
        return
      end

      remaining = slice[pos, slice.size - pos]
      @buffer.clear
      @buffer.write(remaining)
      @buffer.rewind
    end
  end
end
