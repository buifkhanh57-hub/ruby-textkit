# frozen_string_literal: true

module Wordcraft
  # Base class for every error raised intentionally by Wordcraft.
  #
  # Each concrete subclass maps to a conventional BSD `sysexits(3)`-style exit
  # code so that shell pipelines can distinguish failure modes:
  #
  #   0  success
  #   1  generic runtime failure           (Error)
  #   2  bad command line usage            (UsageError)
  #  66  input file missing / unreadable   (FileNotFoundError)
  #
  # Library users should rescue {Wordcraft::Error} rather than the subclasses
  # when they only care that "something went wrong".
  class Error < StandardError
    # Exit status the CLI should use when this error reaches the top level.
    #
    # @return [Integer] the process exit code
    def exit_code
      1
    end
  end

  # Raised when an input file cannot be located, is a directory, or cannot be
  # opened because of missing permissions.
  #
  # @example
  #   raise Wordcraft::FileNotFoundError, "input file not found: notes.txt"
  class FileNotFoundError < Error
    # @return [Integer] EX_NOINPUT (66)
    def exit_code
      66
    end
  end

  # Raised when a file (or stream) exists but its contents cannot be
  # interpreted: undecodable bytes, a malformed stopwords list, a dictionary
  # file that is not plain text, and so on.
  class ParseError < Error; end

  # Raised when a subcommand receives an invalid combination of options, an
  # unknown value for an enumerated flag, or a missing required argument.
  class UsageError < Error
    # @return [Integer] EX_USAGE (2)
    def exit_code
      2
    end
  end

  # Raised when +--format+ / +--mode+ receives a value outside the supported
  # set. A thin semantic wrapper around {UsageError} kept separate so callers
  # can match on the *cause* of a usage failure.
  class UnsupportedFormatError < UsageError; end

  # Raised when an operation needs more text than it was given -- for example
  # computing readability over a text that contains no sentence terminator.
  class InsufficientDataError < Error; end

  # Raised when a {Wordcraft::Puzzles.word_ladder} request is structurally
  # impossible (empty words, mismatched lengths).
  class LadderError < UsageError; end

  # Small helpers for normalising foreign exceptions into the Wordcraft
  # hierarchy so the CLI has exactly one rescue path at the top level.
  module Errors
    # Exit code returned for an unknown / unmatched error.
    GENERIC_EXIT = 1

    module_function

    # Wraps any exception into a {Wordcraft::Error} instance.
    #
    # Wordcraft errors are returned untouched; anything else (NoMethodError,
    # TypeError, ...) is re-wrapped with its class name prefixed so the
    # message stays informative without leaking a raw backtrace to users.
    #
    # @param exception [Exception] the raised error
    # @return [Wordcraft::Error] a normalised error object
    def normalize(exception)
      return exception if exception.is_a?(Wordcraft::Error)

      Error.new("#{exception.class}: #{exception.message}")
    end

    # @param exception [Exception] any exception
    # @return [Integer] the exit code that should be used for it
    def exit_code_for(exception)
      err = normalize(exception)
      err.respond_to?(:exit_code) ? err.exit_code : GENERIC_EXIT
    end

    # Renders an error the way the CLI prints it, without colour codes.
    #
    # @param exception [Exception] any exception
    # @return [String] e.g. "wordcraft: input file not found: x.txt"
    def format(exception)
      "wordcraft: #{normalize(exception).message}"
    end
  end
end
