module ActiveRecord::Acts
  module Searchable
    module DirtyTracking
      module Bridge

        def need_update_index?(attr_name = nil)
          return false unless changed?
          if attr_name
            changed_attributes.keys.include?(attr_name)
          else
            true
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

