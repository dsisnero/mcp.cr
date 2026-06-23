require "../spec_helper"

private def parse_sse_events(io)
  MCP::Shared.parse_sse_events(io)
end

describe MCP::Shared::SSEEvent do
  it "parses a simple event with data" do
    input = IO::Memory.new("data: hello\n\n")
    events = parse_sse_events(input)
    events.size.should eq(1)
    events[0].data.should eq("hello")
  end

  it "defaults to event type 'message' when no event field present" do
    input = IO::Memory.new("data: hello\n\n")
    events = parse_sse_events(input)
    events[0].event.should eq("message")
  end

  it "parses event with id, event, and data fields" do
    input = IO::Memory.new("id: 42\nevent: update\ndata: {\"key\": 1}\n\n")
    events = parse_sse_events(input)
    events.size.should eq(1)
    e = events[0]
    e.id.should eq("42")
    e.event.should eq("update")
    e.data.should eq("{\"key\": 1}")
  end

  it "concatenates multi-line data fields with newlines" do
    input = IO::Memory.new("data: line1\ndata: line2\ndata: line3\n\n")
    events = parse_sse_events(input)
    events.size.should eq(1)
    events[0].data.should eq("line1\nline2\nline3")
  end

  it "ignores comment lines (starting with colon)" do
    input = IO::Memory.new(": this is a comment\ndata: kept\n\n")
    events = parse_sse_events(input)
    events.size.should eq(1)
    events[0].data.should eq("kept")
  end

  it "parses multiple events from a stream" do
    input = IO::Memory.new("data: first\n\ndata: second\n\n")
    events = parse_sse_events(input)
    events.size.should eq(2)
    events[0].data.should eq("first")
    events[1].data.should eq("second")
  end

  it "handles event with only id (no data)" do
    input = IO::Memory.new("id: 1\n\n")
    events = parse_sse_events(input)
    events.size.should eq(1)
    events[0].id.should eq("1")
    events[0].data.should eq("")
  end

  it "parses retry field as integer" do
    input = IO::Memory.new("retry: 3000\n\ndata: x\n\n")
    events = parse_sse_events(input)
    events.size.should eq(2)
    events[0].retry.should eq(3000)
    events[1].retry.should be_nil
  end

  it "ignores trailing carriage return in field values" do
    input = IO::Memory.new("data: hello\r\n\n")
    events = parse_sse_events(input)
    events.size.should eq(1)
    events[0].data.should eq("hello")
  end

  it "ignores fields whose value starts with a space after the colon" do
    input = IO::Memory.new("data: one\ndata:  two\n\n")
    events = parse_sse_events(input)
    events.size.should eq(1)
    events[0].data.should eq("one\ntwo")
  end

  it "handles an empty stream" do
    input = IO::Memory.new("")
    events = parse_sse_events(input)
    events.should be_empty
  end
end
