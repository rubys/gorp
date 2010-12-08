module Gorp
  module VERSION #:nodoc:
    MAJOR = 0
    MINOR = 26
    TINY  = 1

    STRING = [MAJOR, MINOR, TINY].join('.')
  end
end unless defined?(Gorp::VERSION)
