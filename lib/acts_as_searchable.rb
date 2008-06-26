# Copyright (c) 2006 Patrick Lenz
# 
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
# 
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#
# Thanks: Rick Olson (technoweenie) for his numerous plugins that served
# as an example

require 'dirty_tracking/self_made'
require 'dirty_tracking/bridge'
require 'vendor/estraierpure'

module ActiveRecord #:nodoc:
  module Acts #:nodoc:
    # Specify this act if you want to provide fulltext search capabilities to your model via Hyper Estraier. This
    # assumes a setup and running Hyper Estraier node accessible through the HTTP API provided by the EstraierPure
    # Ruby module (which is bundled with this plugin).
    #
    # The act supplies appropriate hooks to insert, update and remove documents from the index when you update your
    # model data, create new objects or remove them from your database. For the initial indexing a convenience
    # class method <tt>reindex!</tt> is provided.
    #
    # Example:
    #
    #   class Article < ActiveRecord::Base
    #     acts_as_searchable
    #   end
    #
    #   Article.reindex!
    #
    # As soon as your model data has been indexed you can make use of the <tt>fulltext_search</tt> class method
    # to search the index and get back instantiated matches.
    #
    #   results = Article.fulltext_search('rails')
    #   results.size        # => 3
    #
    #   results.first.class # => Article
    #   results.first.body  # => "Ruby on Rails is an open-source web framework"
    #
    # Connectivity configuration can be either inherited from conventions or setup globally in the Rails
    # database configuration file <tt>config/database.yml</tt>.
    #
    # Example:
    #
    #   development:
    #     adapter: mysql
    #     database: rails_development
    #     host: localhost
    #     user: root
    #     password:
    #     estraier:
    #       host: localhost
    #       user: admin
    #       password: admin
    #       port: 1978
    #       node: development
    #
    # That way you can configure separate connections for each environment. The values shown above represent the
    # defaults. If you don't need to change any of these it is safe to not specify the <tt>estraier</tt> hash
    # at all.
    #
    # See ActiveRecord::Acts::Searchable::ClassMethods#acts_as_searchable for per-model configuration options
    #
    module Searchable
      MULTIBYTE_SPACE = [0x3000].pack("U")
      PRESERVED_QUERY_WORDS_RE = /(AND|OR|ANDNOT)/

      def self.included(base) #:nodoc:
        base.extend ClassMethods        
      end
      
      module ClassMethods
        VALID_FULLTEXT_OPTIONS = [:limit, :offset, :order, :attributes, :raw_matches, :find, :count]

        # == Configuration options
        #
        # * <tt>searchable_fields</tt> - Fields to provide searching and indexing for (default: 'body')
        # * <tt>attributes</tt> - Additional attributes to store in Hyper Estraier with the appropriate method supplying the value
        # * <tt>if_changed</tt> - Extra list of attributes to add to the list of attributes that trigger an index update when changed
        #
        # Examples:
        #
        #   acts_as_searchable :attributes => { :title => nil, :blog => :blog_title }, :searchable_fields => [ :title, :body ]
        #
        # This would store the return value of the <tt>title</tt> method in the <tt>title</tt> attribute and the return value of the
        # <tt>blog_title</tt> method in the <tt>blog</tt> attribute. The contents of the <tt>title</tt> and <tt>body</tt> columns
        # would end up being indexed for searching.
        #
        # == Attribute naming
        #
        # Attributes that match the reserved names of the Hyper Estraier system attributes are mapped automatically. This is something
        # to keep in mind for custom ordering options or additional query constraints in <tt>fulltext_search</tt>
        # For a list of these attributes see <tt>EstraierPure::SYSTEM_ATTRIBUTES</tt> or visit:
        # 
        #   http://hyperestraier.sourceforge.net/uguide-en.html#attributes
        #
        # From the example above:
        #
        #   Model.fulltext_search('query', :order => '@title STRA')               # Returns results ordered by title in ascending order
        #   Model.fulltext_search('query', :attributes => 'blog STREQ poocs.net') # Returns results with a blog attribute of 'poocs.net'
        #
        def acts_as_searchable(options = {})
          return if self.included_modules.include?(ActiveRecord::Acts::Searchable::ActMethods)

          send :include, ActiveRecord::Acts::Searchable::ActMethods
          
          cattr_accessor :searchable_fields, :attributes_to_store, :if_changed, :estraier_connection, :estraier_node,
            :estraier_host, :estraier_port, :estraier_user, :estraier_password

          node_prefix = estraier_config['node'] || RAILS_ENV

          self.estraier_node        = node_prefix + '_' + self.table_name
          self.estraier_host        = estraier_config['host'] || 'localhost'
          self.estraier_port        = estraier_config['port'] || 1978
          self.estraier_user        = estraier_config['user'] || 'admin'
          self.estraier_password    = estraier_config['password'] || 'admin'
          self.searchable_fields    = options[:searchable_fields] || [ :body ]
          self.attributes_to_store  = options[:attributes] || {}
          self.if_changed           = options[:if_changed] || []

          unless options[:ignore_timestamp] && self.record_timestamps
            timestamp_attr = {
              "cdate" => %w(created_at created_on).detect{|col| self.column_names.include?(col) },
              "mdate" => %w(updated_at updated_on).detect{|col| self.column_names.include?(col) },
            }

            self.attributes_to_store = timestamp_attr.merge(self.attributes_to_store)
          end
          
          if defined?(ActiveRecord::Dirty) && self.included_modules.include?(ActiveRecord::Dirty)
            include ActiveRecord::Acts::Searchable::DirtyTracking::Bridge
          else
            include ActiveRecord::Acts::Searchable::DirtyTracking::SelfMade
          end

          after_update  :update_index
          after_create  :add_to_index
          after_destroy :remove_from_index
          after_save    :clear_changed_attributes

          connect_estraier
        end

        # Perform a fulltext search against the Hyper Estraier index.
        #
        # Options taken:
        # * <tt>limit</tt>       - Maximum number of records to retrieve (default: <tt>100</tt>)
        # * <tt>offset</tt>      - Number of records to skip (default: <tt>0</tt>)
        # * <tt>order</tt>       - Hyper Estraier expression to sort the results (example: <tt>@title STRA</tt>, default: ordering by score)
        # * <tt>attributes</tt>  - String to append to Hyper Estraier search query
        # * <tt>raw_matches</tt> - Returns raw Hyper Estraier documents instead of instantiated AR objects
        # * <tt>find</tt>        - Options to pass on to the <tt>ActiveRecord::Base#find</tt> call
        # * <tt>count</tt>       - Set this to <tt>true</tt> if you're using <tt>fulltext_search</tt> in conjunction with <tt>ActionController::Pagination</tt> to return the number of matches only
        #
        # Examples:
        # 
        #   Article.fulltext_search("biscuits AND gravy")
        #   Article.fulltext_search("biscuits AND gravy", :limit => 15, :offset => 14)
        #   Article.fulltext_search("biscuits AND gravy", :attributes => "tag STRINC food")
        #   Article.fulltext_search("biscuits AND gravy", :attributes => ["tag STRINC food", "@title STRBW Biscuit"])
        #   Article.fulltext_search("biscuits AND gravy", :order => "@title STRA")
        #   Article.fulltext_search("biscuits AND gravy", :raw_matches => true)
        #   Article.fulltext_search("biscuits AND gravy", :find => { :order => :title, :include => :comments })
        #
        # Consult the Hyper Estraier documentation on proper query syntax:
        # 
        #   http://hyperestraier.sourceforge.net/uguide-en.html#searchcond
        #
        def fulltext_search(query = "", options = {})
          ids = nil

          find_options = options[:find] || {}
          [ :limit, :offset ].each { |k| find_options.delete(k) } unless find_options.blank?

          ids = matched_ids(query, options)
          find_by_ids_scope(ids, find_options)
        end

        # this methods is NOT compat with original AAS
        def find_fulltext(query, options={}, with_mdate_desc_order=true)
          fulltext_option = {}
          if with_mdate_desc_order
            fulltext_option[:order] = "@mdate NUMD"
          end
          ids = matched_ids(query, fulltext_option)
          find_by_ids_scope(ids, options)
        end

        def matched_ids(query = "", options = {})
          matches = raw_matches(query, options)
          return matches.map{|doc| Integer(doc.attr("db_id")) }
        end

        def raw_matches(query = "", options = {})

          cond = build_fulltext_condition(query, options)

          matches = nil
          seconds = Benchmark.realtime do
            result = estraier_connection.search(cond, 1);
            return (result.doc_num rescue 0) if options[:count]
            return [] unless result
            matches = get_docs_from(result)
          end

          logger.debug do
            connection.send(:format_log_entry, 
              "#{self.to_s} seach for '#{query}' (#{sprintf("%f", seconds)})",
              "Condition: #{cond.to_s}")
          end

          return matches
        end

        def build_fulltext_condition(query, options = {})
          options = {:limit => 100, :offset => 0}.merge(options)
          options.assert_valid_keys(VALID_FULLTEXT_OPTIONS)

          cond = new_estraier_condition
          cond.set_phrase tokenize_query(query)
          [options[:attributes]].flatten.reject { |a| a.blank? }.each do |attr|
            cond.add_attr attr
          end
          cond.set_max   options[:limit]
          cond.set_skip  options[:offset]
          cond.set_order options[:order] if options[:order]
          return cond
        end

        # Clear all entries from index
        def clear_index!
          estraier_index.each { |d| estraier_connection.out_doc(d.attr('@id')) unless d.nil? }
        end
        
        # Peform a full re-index of the model data for this model
        def reindex!
          find(:all).each { |r| r.update_index(true) }
        end
        
        def estraier_index #:nodoc:
          cond = EstraierPure::Condition::new
          cond.add_attr("db_id NUMGT 0")
          result = estraier_connection.search(cond, 1)
          docs = get_docs_from(result)
          docs
        end
        
        def get_docs_from(result) #:nodoc:
          docs = []
          for i in 0...result.doc_num
            docs << result.get_doc(i)
          end
          docs
        end

        def new_estraier_condition #:nodoc
          cond = EstraierPure::Condition::new
          cond.set_options(EstraierPure::Condition::SIMPLE | EstraierPure::Condition::USUAL)
          cond
        end

        def tokenize_query(query)
          tokens = query.scan(/'([^']*)'|"([^"]*)"|([^\s#{MULTIBYTE_SPACE}]*)/).flatten.reject(&:blank?)
          tokens.map do |token|
            token.gsub!(PRESERVED_QUERY_WORDS_RE, $1.downcase) if token =~ PRESERVED_QUERY_WORDS_RE 
            token.gsub!(/\A['"]|['"]\z/, '') # strip quatos
            token
          end.join(" AND ")
        end

        protected
        
        def connect_estraier #:nodoc:
          self.estraier_connection = EstraierPure::Node::new
          self.estraier_connection.set_url("http://#{self.estraier_host}:#{self.estraier_port}/node/#{self.estraier_node}")
          self.estraier_connection.set_auth(self.estraier_user, self.estraier_password)
        end
        
        def estraier_config #:nodoc:
          configurations[RAILS_ENV]['estraier'] or {}
        end

        private
        def find_by_ids_scope(ids, options={})
          return [] if ids.blank?
          with_scope(:find=>{:conditions=>["#{table_name}.id IN (?)", ids]}) do
            return find(:all, options)
          end
        end

      end
      
      module ActMethods
        def self.included(base) #:nodoc:
          base.extend ClassMethods
        end
        
        # Update index for current instance
        def update_index(force = false)
          return unless need_update_index? or force
          remove_from_index
          add_to_index
        end
        
        # Retrieve index record for current model object
        def estraier_doc
          cond = self.class.new_estraier_condition
          cond.add_attr("db_id STREQ #{self.id}")
          result = self.estraier_connection.search(cond, 1)
          return unless result and result.doc_num > 0
          get_doc_from(result)
        end
        
        protected
        
        def add_to_index #:nodoc:
          seconds = Benchmark.realtime { estraier_connection.put_doc(document_object) }
          logger.debug "#{self.class.to_s} [##{id}] Adding to index (#{sprintf("%f", seconds)})"
        end
        
        def remove_from_index #:nodoc:
          return unless doc = estraier_doc
          seconds = Benchmark.realtime { self.estraier_connection.out_doc(doc.attr('@id')) }
          logger.debug "#{self.class.to_s} [##{id}] Removing from index (#{sprintf("%f", seconds)})"
        end
        
        def get_doc_from(result) #:nodoc:
          self.class.get_docs_from(result).first
        end

        def document_object #:nodoc:
          doc = EstraierPure::Document::new
          doc.add_attr('db_id', "#{id}")
          # Use type instead of self.class.subclasses as the latter is a protected method
          unless self.class.base_class == self.class and not attribute_names.include?("type")
            doc.add_attr("type_base", "#{ self.class.base_class.to_s }")
          end
          doc.add_attr('@uri', "/#{self.class.to_s}/#{id}")
          
          unless attributes_to_store.blank?
            attributes_to_store.each do |attribute, method|
              value = send(method || attribute)
              value = value.xmlschema if value.is_a?(Time)
              doc.add_attr(attribute_name(attribute), value.to_s)
            end
          end

          searchable_fields.each do |f|
            doc.add_text send(f)
          end

          doc          
        end
        
        def attribute_name(attribute)
          EstraierPure::SYSTEM_ATTRIBUTES.include?(attribute.to_s) ? "@#{attribute}" : "#{attribute}"
        end
      end
    end
  end
end

ActiveRecord::Base.send :include, ActiveRecord::Acts::Searchable

module EstraierPure
  unless defined?(SYSTEM_ATTRIBUTES)
    SYSTEM_ATTRIBUTES = %w( uri digest cdate mdate adate title author type lang genre size weight misc )
  end
  
  class Node
    def list
      return false unless @url
      turl = @url + "/list"
      reqheads = [ "Content-Type: application/x-www-form-urlencoded" ]
      reqheads.push("Authorization: Basic " + Utility::base_encode(@auth)) if @auth
      reqbody = ""
      resbody = StringIO::new
      rv = Utility::shuttle_url(turl, @pxhost, @pxport, @timeout, reqheads, reqbody, nil, resbody)
      @status = rv
      return nil if rv != 200
      lines = resbody.string.split(/\n/)
      lines.collect { |l| val = l.split(/\t/) and { :id => val[0], :uri => val[1], :digest => val[2] } }
    end
  end
  
  class Condition
    def to_s
      "phrase: %s, attrs: %s, max: %s, options: %s, order: %s, skip: %s" % [ phrase, attrs * ', ', max, options, order, skip ]
    end
  end
end
