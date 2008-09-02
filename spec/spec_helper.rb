$KCODE = 'u'
require 'rubygems'
#gem 'activerecord', '2.0.2'
if ENV["AR"]
  gem 'activerecord', ENV["AR"]
  $stderr.puts("Using ActiveRecord #{ENV["AR"]}")
end
require 'active_record'

$: << File.expand_path("../lib", File.dirname(__FILE__))
require File.expand_path("../init", File.dirname(__FILE__))

RAILS_ENV = "test"
ActiveRecord::Base.configurations = {"test" => {
  :adapter => "sqlite3",
  :database => ":memory:",
  :estraier => {:host=> "localhost", :node=>"aas_e_test", :user=>"admin", :password=>"admin"}
}.with_indifferent_access}

ActiveRecord::Base.establish_connection(:test)

load File.expand_path("setup_test_model.rb", File.dirname(__FILE__))

Spec::Example::ExampleGroupMethods.module_eval do
  def fixtures(*tables)
    dir = File.expand_path("fixtures", File.dirname(__FILE__))
    tables.each{|table| Fixtures.create_fixtures(dir, table.to_s) }
  end
end

