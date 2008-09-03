require 'acts_as_searchable/backends/hyper_estraier'

module ActsAsSearchable
  module Backends
    def connect(model_klass, config)
      backend = config['backends'] || "hyper_estraier"

      case backend
      when "hyper_estraier", nil # default
        host = config['host'] || 'localhost'
        port = config['port'] || 1978
        user = config['user'] || 'admin'
        password = config['password'] || 'admin'
        Backends::HyperEstraier.new(model_klass, host, port, user, password)
      else
        raise NotImplementedError.new("#{backend} backend is not supported")
      end
    end
    module_function :connect
  end
end
