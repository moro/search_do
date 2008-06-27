module ActiveRecord::Acts
  module Searchable
    module DirtyTracking
      module Bridge

        def need_update_index?(attr_name = nil)
          return false unless changed?
          cs = changed_attributes.keys
          if attr_name
            cs.include?(attr_name)
          else
            self.class.fulltext_index_observing_fields.any?{|t| cs.include?(t) }
          end
        end

        private
        def clear_changed_attributes
          changed_attributes.clear
        end
      end
    end
  end
end

