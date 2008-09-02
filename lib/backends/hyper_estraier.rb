#!/usr/bin/env ruby
# vim:set fileencoding=utf-8 filetype=ruby
# $KCODE = 'u'

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
        result = search(cond, 1)
        get_docs_from(result)
      end

      def get_docs_from(result) #:nodoc:
        docs = []
        for i in 0...result.doc_num
          docs << result.get_doc(i)
        end
        docs
      end

      def get_doc_from(result) #:nodoc:
        self.class.get_docs_from(result).first
      end

      def search_one(cond, num=1)
        result = @connection.search(cond, num)
        if result.nil? || result.doc_num > 0
          return nil
        end
        get_docs_from(result).first
      end

      def search(cond, num)
        @connection.search(cond, num)
      end

      def add_to_index(document)
        @connection.put_doc(document)
      end

      def delete_from_index(document)
        @connection.out_doc(document.attr('@id'))
      end
    end
  end
end

