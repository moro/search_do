require 'acts_as_searchable/dirty_tracking/self_made'
require 'acts_as_searchable/dirty_tracking/bridge'

module ActsAsSearchable
  module DirtyTracking
    def self.included(base)
      mod = if defined?(ActiveRecord::Dirty) && base.included_modules.include?(ActiveRecord::Dirty)
              DirtyTracking::Bridge
            else
              DirtyTracking::SelfMade
            end
      base.send(:include, mod)
    end
  end
end
