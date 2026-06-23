require "../spec_helper"

struct TestExtension
  include JSON::Serializable
  property value : Int32

  def initialize(@value : Int32)
  end
end

describe MCP::Shared::RequestHandlerExtra do
  it "stores and retrieves a typed extension value" do
    extra = MCP::Shared::RequestHandlerExtra.new
    extra.set_extension("key1", TestExtension.new(42))
    val = extra.get_extension("key1", TestExtension)
    val.should be_a(TestExtension)
    val.not_nil!.value.should eq(42)
  end

  it "returns nil for a missing key" do
    extra = MCP::Shared::RequestHandlerExtra.new
    extra.get_extension("nope", TestExtension).should be_nil
  end

  it "returns nil when the stored value is not the expected type" do
    extra = MCP::Shared::RequestHandlerExtra.new
    extra.extensions["key1"] = JSON::Any.new("string_not_object")
    extra.get_extension("key1", TestExtension).should be_nil
  end
end
