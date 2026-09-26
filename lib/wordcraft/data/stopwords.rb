# frozen_string_literal: true

require 'set'

module Wordcraft
  module Data
    # Embedded English stopword list.
    #
    # A stopword is a high-frequency, low-information word (articles,
    # pronouns, auxiliaries, common connectives) that is usually filtered out
    # before frequency analysis. The list is intentionally generous (~440
    # entries) and covers:
    #
    #   * determiners and pronouns
    #   * wh-words and indefinite pronouns
    #   * conjunctions and discourse connectives
    #   * prepositions and particles
    #   * be / have / do forms, modals and the most frequent full verbs
    #   * contracted forms ("don't", "it's", ...)
    #   * fillers, politeness formulas and quantity words
    #
    # Sentiment-bearing words ("love", "hate", "great", ...) are deliberately
    # NOT stopwords: the sentiment module consumes raw token streams and must
    # be able to see them.
    #
    # All entries are lowercase; lookups downcase their argument.
    STOPWORDS = %w[
      a
      an
      the
      this
      that
      these
      those
      each
      every
      either
      such
      own
      i
      me
      my
      mine
      myself
      we
      us
      our
      ours
      ourselves
      you
      your
      yours
      yourself
      yourselves
      he
      him
      his
      himself
      she
      her
      hers
      herself
      it
      its
      itself
      they
      them
      their
      theirs
      themselves
      who
      whom
      whose
      which
      what
      whatever
      whichever
      whoever
      whomever
      how
      why
      when
      where
      anyone
      anybody
      anything
      everyone
      everybody
      everything
      someone
      somebody
      something
      anywhere
      everywhere
      somewhere
      and
      or
      but
      so
      yet
      for
      if
      unless
      because
      while
      whereas
      although
      though
      whether
      once
      besides
      than
      then
      thus
      hence
      therefore
      however
      moreover
      furthermore
      nevertheless
      nonetheless
      otherwise
      instead
      of
      in
      on
      at
      by
      to
      from
      with
      without
      about
      against
      between
      among
      into
      onto
      upon
      through
      throughout
      during
      before
      after
      above
      below
      over
      under
      underneath
      behind
      beneath
      beside
      beyond
      across
      along
      around
      toward
      towards
      despite
      except
      inside
      outside
      near
      past
      per
      until
      till
      via
      within
      amid
      off
      up
      down
      out
      since
      as
      again
      further
      here
      there
      now
      always
      often
      sometimes
      usually
      rarely
      seldom
      soon
      later
      already
      still
      just
      only
      even
      ever
      almost
      nearly
      quite
      rather
      too
      also
      very
      well
      indeed
      perhaps
      maybe
      certainly
      definitely
      probably
      possibly
      actually
      really
      anyway
      together
      apart
      aside
      forward
      backward
      be
      is
      am
      are
      was
      were
      been
      being
      do
      does
      did
      doing
      done
      have
      has
      had
      having
      will
      would
      shall
      should
      can
      could
      must
      may
      might
      ought
      need
      needs
      dare
      used
      let
      lets
      get
      gets
      got
      getting
      go
      goes
      going
      gone
      went
      come
      comes
      coming
      came
      become
      becomes
      became
      seem
      seems
      seemed
      appear
      appears
      appeared
      remain
      remains
      remained
      stay
      stays
      stayed
      keep
      keeps
      kept
      make
      makes
      made
      say
      says
      said
      tell
      told
      know
      knows
      known
      think
      thinks
      thought
      see
      sees
      seen
      saw
      want
      wants
      wanted
      use
      find
      finds
      found
      give
      gives
      gave
      given
      take
      takes
      took
      taken
      put
      puts
      look
      looks
      looked
      looking
      feel
      feels
      felt
      work
      works
      worked
      call
      calls
      called
      try
      tries
      tried
      ask
      asks
      asked
      leave
      leaves
      left
      mean
      means
      meant
      turn
      turns
      turned
      start
      starts
      started
      show
      shows
      showed
      shown
      hear
      hears
      heard
      play
      plays
      played
      move
      moves
      moved
      live
      lives
      lived
      hold
      holds
      held
      bring
      brings
      brought
      happen
      happens
      happened
      can't
      cannot
      couldn't
      didn't
      doesn't
      don't
      hadn't
      hasn't
      haven't
      isn't
      aren't
      wasn't
      weren't
      won't
      wouldn't
      shouldn't
      mustn't
      needn't
      mightn't
      shan't
      ain't
      i'm
      i've
      i'd
      i'll
      it's
      that's
      there's
      here's
      what's
      who's
      let's
      he's
      he'd
      he'll
      she's
      she'd
      she'll
      we're
      we've
      we'd
      we'll
      they're
      they've
      they'd
      they'll
      you're
      you've
      you'd
      you'll
      yes
      ok
      okay
      oh
      uh
      um
      er
      ah
      please
      thanks
      thank
      welcome
      sorry
      hello
      hi
      bye
      thing
      things
      stuff
      way
      ways
      lot
      lots
      kind
      sort
      part
      parts
      type
      much
      many
      more
      most
      less
      least
      few
      several
      enough
      some
      any
      all
      both
      other
      others
      another
      same
      different
      first
      second
      next
      last
      two
      three
      four
      five
      six
      seven
      eight
      nine
      ten
      hundred
    ].freeze

    # Hash-set view of {STOPWORDS} for O(1) membership tests.
    STOPWORD_SET = Set.new(STOPWORDS).freeze

    module_function

    # @param word [String] any word
    # @return [Boolean] true when +word+ (case-insensitive) is a stopword
    def stopword?(word)
      STOPWORD_SET.include?(word.to_s.downcase)
    end

    # Filters an array of tokens, keeping non-stopwords only.
    #
    # @param tokens [Array<String>] token stream
    # @return [Array<String>] tokens that are not stopwords
    def filter(tokens)
      tokens.reject { |token| stopword?(token) }
    end

    # @return [Integer] number of embedded stopwords
    def size
      STOPWORDS.size
    end

    # Loads a custom stopword list from disk (one word per line, "#"
    # comments allowed) and returns it as a frozen Set.
    #
    # @param path [String] file path
    # @return [Set<String>] lowercase stopword set
    # @raise [Wordcraft::FileNotFoundError] when the file is missing
    # @raise [Wordcraft::ParseError] when the file contains no usable words
    def load_stopwords(path)
      raise FileNotFoundError, "stopwords file not found: #{path}" unless File.file?(path)

      words = []
      File.foreach(path) do |line|
        word = line.strip.split(/\s+/).first.to_s
        next if word.empty? || word.start_with?('#')

        words << word.downcase
      end
      raise ParseError, "stopwords file #{path} contains no words" if words.empty?

      Set.new(words).freeze
    end
  end
end
