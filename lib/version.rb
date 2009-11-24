module Gorp
  module VERSION #:nodoc:
    MAJOR = 0
    MINOR = 8
    TINY  = 0

    STRING = [MAJOR, MINOR, TINY].join('.')
  end
end unless defined?(Gorp::VERSION)
