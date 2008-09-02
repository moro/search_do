#!/usr/bin/env ruby
# vim:set fileencoding=utf-8 filetype=ruby
# $KCODE = 'u'
require 'acts_as_searchable/utils'

module ActsAsSearchable
  module Backends
    class HyperEstraier
      attr_reader :connection

      # FIXME use URI
      def initialize(node, host, port, user, password)
        @connection = EstraierPure::Node.new

        @connection.set_url("http://#{host}:#{port}/node/#{node}")
        @connection.set_auth(user, password)
      end

      def index
        cond = EstraierPure::Condition::new
        cond.add_attr("db_id NUMGT 0")
        result = raw_search(cond, 1)
        get_docs_from(result)
      end

      def search_one_by_model(model)
        cond = EstraierPure::Condition::new
        cond.set_options(EstraierPure::Condition::SIMPLE | EstraierPure::Condition::USUAL)
        cond.add_attr("db_id NUMEQ #{model.id}")

        search_one(cond, 1)
      end

      def search_one(cond, num=1)
        result = raw_search(cond, num)
        return nil if result.nil? || result.doc_num.zero?
        get_docs_from(result).first
      end

      def get_docs_from(result) #:nodoc:
        (0...result.doc_num).inject([]){|r, i| r << result.get_doc(i) }
      end

      def raw_matches(query, options = {})
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

      def raw_search(cond, num)
        @connection.search(cond, num)
      end

      def add_to_index(document)
        @connection.put_doc(document)
      end

      def delete_from_index(document)
        @connection.out_doc(document.attr('@id'))
      end

      def remove_from_index(model)
        return unless doc = search_one_by_model(model)
        seconds = Benchmark.realtime { delete_from_index(doc) }
        # logger.debug "#{model.class.to_s} [##{model.id}] Removing from index (#{sprintf("%f", seconds)})"
      end

      def clear_index!
        index.each { |d| delete_from_index(d) }
      end
    end
  end
end

