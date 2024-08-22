# frozen_string_literal: true

module Coverband
  module Adapters
    ###
    # ActiveSupportCacheStore store a merged coverage file to ActiveSupport::Cache
    ###
    class ActiveSupportCacheStore < Base
      ###
      # This key isn't related to the coverband version, but to the internal format
      # used to store data to ActiveSupport::Cache. It is changed only when breaking changes to our
      # ActiveSupport::Cache format are required.
      ###
      CACHE_STORAGE_FORMAT_VERSION = "coverband_active_support_cache_0_1"

      attr_reader :namespace

      def initialize(cache, opts = {})
        super()
        @cache = cache
        @ttl = opts[:ttl]
        @namespace = opts[:namespace]
        @format_version = CACHE_STORAGE_FORMAT_VERSION
        @keys = {}
        Coverband::TYPES.each do |type|
          @keys[type] = [@format_version, namespace, type].compact.join(".")
        end
      end

      def clear!
        Coverband::TYPES.each do |type|
          @cache.delete(type_base_key(type))
        end
      end

      def clear_file!(filename)
        Coverband::TYPES.each do |type|
          data = coverage(type)
          data.delete(filename)
          save_coverage(data, type)
        end
      end

      def size
        @cache.read(base_key) ? @cache.read(base_key).bytesize : "N/A"
      end

      def type=(type)
        super
        reset_base_key
      end

      def coverage(local_type = nil, opts = {})
        local_type ||= opts.key?(:override_type) ? opts[:override_type] : type
        data = @cache.read type_base_key(local_type)
        data = data ? JSON.parse(data) : {}
        data.delete_if { |file_path, file_data| file_hash(file_path) != file_data["file_hash"] } unless opts[:skip_hash_check]
        data
      end

      # Note: This could lead to slight race on the ActiveSupport::Cache::Store
      # where multiple processes pull the old coverage and add to it then push
      # the Coverband 2 had the same issue,
      # and the tradeoff has always been acceptable
      def save_report(report)
        data = report.dup
        data = merge_reports(data, coverage(nil, skip_hash_check: true))
        save_coverage(data)
      end

      def raw_store
        @cache
      end

      def file_count
        data = @cache.read type_base_key(Coverband::RUNTIME_TYPE)
        JSON.parse(data).keys.length
      end

      def cached_file_count
        @cached_file_count ||= file_count
      end

      private

      attr_reader :redis

      def reset_base_key
        @base_key = nil
      end

      def base_key
        @base_key ||= [@format_version, namespace, type].compact.join(".")
      end

      def type_base_key(local_type)
        @keys[local_type]
      end

      def save_coverage(data, local_type = nil)
        local_type ||= type
        @cache.write type_base_key(local_type), data.to_json, expires_in: @ttl
      end
    end
  end
end
