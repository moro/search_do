require File.expand_path("../spec_helper", File.dirname(__FILE__))

describe SearchDo::Backends::HyperEstraier do
  before do
    @backend = SearchDo::Backends::HyperEstraier.new(Story, ActiveRecord::Base.configurations["test"]["estraier"])
  end

  describe "#index // there is no index" do
    before do
      @backend.connection.should_receive(:search).and_return(nil)
    end

    it "should == []" do
      @backend.index.should == []
    end
  end

  describe "#add_to_index(['foo',nil]) // include nil to indexed text" do
    it "should not raise error" do
      lambda{ 
        @backend.add_to_index(['foo', nil], {})
      }.should_not raise_error
    end
  end

  describe "#add_to_index([Time.local(2008,9,17)]) // include nil to indexed text" do
    before do
      @time = Time.local(2008,9,17)
      @backend.add_to_index([@time], 'db_id' => "1", '@uri' => "/Story/1")
    end

    it "should searchable with '2008-09-17T00:00:00'" do
      @backend.count(@time.iso8601).should > 0
    end
  end
end

