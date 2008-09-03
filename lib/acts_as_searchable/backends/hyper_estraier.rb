#!/usr/bin/env ruby
# vim:set fileencoding=utf-8 filetype=ruby
# $KCODE = 'u'
require 'acts_as_searchable/utils'

module ActsAsSearchable
  module Backends
    class HyperEstraier
      SYSTEM_ATTRIBUTES = %w( uri digest cdate mdate adate title author type lang genre size weight misc )

      attr_reader :connection
      attr_accessor :node_name

      DEFAULT_CONFIG = {
        'host' => 'localhost',
        'port' => 1978,
        'user' => 'admin',
        'password' => 'admin',
      }.freeze

      # FIXME use URI
      def initialize(ar_class, config = {})
        @ar_class = ar_class
        config = DEFAULT_CONFIG.merge(config)
        self.node_name = calculate_node_name(config)

        @connection = EstraierPure::Node.new
        @connection.set_url("http://#{config['host']}:#{config['port']}/node/#{self.node_name}")
        @connection.set_auth(config['user'], config['password'])
      end

      def index
        cond = EstraierPure::Condition::new
        cond.add_attr("db_id NUMGT 0")
        result = raw_search(cond, 1)
        get_docs_from(result)
      end

      def search_by_db_id(id)
        cond = EstraierPure::Condition::new
        cond.set_options(EstraierPure::Condition::SIMPLE | EstraierPure::Condition::USUAL)
        cond.add_attr("db_id NUMEQ #{id}")

        result = raw_search(cond, 1)
        return nil if result.nil? || result.doc_num.zero?
        get_docs_from(result).first
      end

      def serch_all(query, options = {})
        cond = build_fulltext_condition(query, options)

        matches = nil

        seconds = Benchmark.realtime do
          result = raw_search(cond, 1);
          return (result.doc_num rescue 0) if options[:count]
          return [] unless result
          matches = get_docs_from(result)
        end

        # FIXME use logger
=begin
        logger.debug do
          connection.send(:format_log_entry,
            "#{self.to_s} seach for '#{query}' (#{sprintf("%f", seconds)})",
            "Condition: #{cond.to_s}")
        end
=end
        return matches
      end

      def add_to_index(texts, attrs)
        doc = EstraierPure::Document::new
        texts.each{|t| doc.add_text(t) }
        attrs.each{|k,v| doc.add_attr(attribute_name(k), v) }

        log = "#{@ar_class.name} [##{attrs["db_id"]}] Adding to index"
        benchmark(log){ @connection.put_doc(doc) }
      end

      def remove_from_index(db_id)
        return unless doc = search_by_db_id(db_id)
        log = "#{@ar_class.name} [##{db_id}] Removing from index"
        benchmark(log){ delete_from_index(doc) }
      end

      def clear_index!
        benchmark("Deleting all index"){ index.each { |d| delete_from_index(d) } }
      end

      private
      def raw_search(cond, num)
        @connection.search(cond, num)
      end

      def get_docs_from(result) #:nodoc:
        (0...result.doc_num).inject([]){|r, i| r << result.get_doc(i) }
      end

      def build_fulltext_condition(query, options = {})
        options = {:limit => 100, :offset => 0}.merge(options)
        # options.assert_valid_keys(VALID_FULLTEXT_OPTIONS)

        cond = EstraierPure::Condition::new
        cond.set_options(EstraierPure::Condition::SIMPLE | EstraierPure::Condition::USUAL)

        cond.set_phrase Utils.tokenize_query(query)

        [options[:attributes]].flatten.reject { |a| a.blank? }.each do |attr|
          cond.add_attr attr
        end
        cond.set_max   options[:limit]
        cond.set_skip  options[:offset]
        cond.set_order options[:order] if options[:order]
        return cond
      end

      def delete_from_index(document)
        @connection.out_doc(document.attr('@id'))
      end

      def benchmark(log, &block)
        @ar_class.benchmark(log, &block)
      end

      def calculate_node_name(config)
        node_prefix = config['node_prefix'] || config['node'] || RAILS_ENV
        "#{node_prefix}_#{@ar_class.table_name}"
      end

      def attribute_name(attribute)
        SYSTEM_ATTRIBUTES.include?(attribute.to_s) ? "@#{attribute}" : "#{attribute}"
      end
    end
  end
end

