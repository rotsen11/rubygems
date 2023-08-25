# frozen_string_literal: true

module Bundler
  class Checksum
    class << self
      def digests_from_file_source(file_source, digest_algorithms: %w[sha256])
        raise ArgumentError, "not a valid file source: #{file_source}" unless file_source.respond_to?(:with_read_io)

        digests = digest_algorithms.map do |digest_algorithm|
          [digest_algorithm.to_s, Bundler::SharedHelpers.digest(digest_algorithm.upcase).new]
        end.to_h

        file_source.with_read_io do |io|
          until io.eof?
            block = io.read(16_384)
            digests.each_value {|digest| digest << block }
          end

          io.rewind
        end

        digests
      end

      def from_lock(checksums, source)
        checksums.split(",").map do |c|
          algo, digest = c.split("-", 2)
          new(algo, digest, source)
        end
      end

      def to_lock(checksums)
        checksums.map(&:to_lock).sort.join(",")
      end

      def match_digests?(checksums, digests)
        return true if checksums.empty? && digests.empty?

        common_algos = checksums.keys & digests.keys
        return true if common_algos.empty?

        common_algos.all? do |algo|
          checksums[algo].digest == digests[algo]
        end
      end
    end

    attr_reader :algo, :digest, :sources
    def initialize(algo, digest, source)
      @algo = algo
      @digest = digest
      @sources = Set.new
      @sources << source
    end

    def ==(other)
      other.is_a?(self.class) && other.digest == digest && other.algo == algo && sources == other.sources
    end

    def hash
      digest.hash
    end

    alias_method :eql?, :==

    def to_s
      "#{algo}-#{digest} (from #{sources.first}#{", ..." if sources.size > 1})"
    end

    def to_lock
      "#{algo}-#{digest}"
    end

    def merge!(other)
      raise ArgumentError, "cannot merge checksums of different algorithms" unless algo == other.algo
      unless digest == other.digest
        raise SecurityError, <<~MESSAGE
          #{other}
          #{self} from:
          * #{sources.join("\n* ")}
        MESSAGE
      end
      @sources.merge!(other.sources)
      self
    end

    class Store
      attr_reader :store
      protected :store

      def initialize
        @store = Hash.new { |h, k| h[k] = {} }
      end

      def initialize_copy(o)
        @store = {}
        o.store.each do |k, v|
          @store[k] = v.dup
        end
      end

      def [](full_name)
        @store[full_name]
      end

      def delete(full_name)
        @store.delete(full_name)
      end

      def []=(full_name, checksums)
        delete(full_name)
        register(full_name, checksums)
      end

      def register(full_name, checksums)
        Array(checksums).each do |checksum|
          @store[full_name][checksum.algo]&.merge!(checksum)
          @store[full_name][checksum.algo] ||= checksum
        end
      rescue SecurityError => e
        raise e.exception(<<~MESSAGE)
          Bundler found multiple different checksums for #{full_name}.
          This means that there are multiple different `#{full_name}.gem` files.
          This is a potential security issue, since Bundler could be attempting \
          to install a different gem than what you expect.

          #{e.message}
          To resolve this issue:
          1. delete any downloaded gems referenced above
          2. run `bundle install`

          If you are sure that the new checksum is correct, you can \
          remove the `#{full_name}` entry under the lockfile `CHECKSUMS` \
          section and rerun `bundle install`.

          If you wish to continue installing the downloaded gem, and are certain it does not pose a \
          security issue despite the mismatching checksum, do the following:
          1. run `bundle config set --local disable_checksum_validation true` to turn off checksum verification
          2. run `bundle install`
        MESSAGE
      end

      def merge(other)
        other.store.each do |k, v|
          register k, v.values
        end
      end
    end
  end
end
