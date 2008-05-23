namespace :search do
  desc "Clears HE Index"
  task :clear => :environment do
    raise "Pass a searchable model with MODEL=" unless ENV['MODEL']
    ENV['MODEL'].constantize.clear_index!
  end

  desc "Reindexes all model attributes"
  task :reindex => :environment do
    raise "Pass a searchable model with MODEL=" unless ENV['MODEL']
    model_class = ENV['MODEL'].constantize
    reindex = lambda { model_class.reindex! }
    if ENV['INCLUDE']
      model_class.with_scope :find => { :include => ENV['INCLUDE'].split(',').collect { |i| i.strip.to_sym } } do
        reindex.call
      end
    else
      reindex.call
    end
  end
end