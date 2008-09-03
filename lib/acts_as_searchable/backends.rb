require 'acts_as_searchable/backends/hyper_estraier'

module ActsAsSearchable
  module Backends
    def connect(model_klass, config)
      backend = config['backends'] || "hyper_estraier"

      case backend
      when "hyper_estraier", nil # default
        Backends::HyperEstraier.new(model_klass, config)
      else
        raise NotImplementedError.new("#{backend} backend is not supported")
      end
    end
    module_function :connect
  end
end
