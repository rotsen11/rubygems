# frozen_string_literal: true

module Spec
  module Checksums
    class ChecksumsBuilder
      def initialize
        @checksums = {}
      end

      def repo_gem(gem_repo, gem_name, gem_version, platform = nil, empty: false)
        gem_file = if platform
          "#{gem_repo}/gems/#{gem_name}-#{gem_version}-#{platform}.gem"
        else
          "#{gem_repo}/gems/#{gem_name}-#{gem_version}.gem"
        end

        checksum = Bundler::Checksum.new("sha256", sha256_checksum(gem_file), 'ChecksumsBuilder') unless empty
        @checksums[GemHelpers.lock_name(spec.name, spec.version, spec.platform)] = checksum
      end

      def to_lock
        @checksums.map { |gem, checksum|
          out = "  #{gem} "
          out << Bundler::Checksum.to_lock([checksum]) if checksum
          out << "\n"
        }.sort.join.strip
      end

      private

      def sha256_checksum(file)
        File.open(file) do |f|
          digest = Bundler::SharedHelpers.digest(:SHA256).new
          digest << f.read(16_384) until f.eof?

          digest.hexdigest!
        end
      end
    end

    def construct_checksum_section
      checksums = ChecksumsBuilder.new

      yield checksums

      checksums.to_lock
    end

    def checksum_for_repo_gem(*args, **kwargs)
      construct_checksum_section do |c|
        c.repo_gem(*args, **kwargs)
      end
    end
  end
end
