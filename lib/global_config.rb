class GlobalConfig
  VERSION = 'V1'.freeze
  KEY_PREFIX = 'GLOBAL_CONFIG'.freeze
  DEFAULT_EXPIRY = 1.day

  class << self
    def get(*args)
      config = load_many_from_cache(args)

      typecast_config(config)
      config.with_indifferent_access
    end

    def get_value(arg)
      load_from_cache(arg)
    end

    def clear_cache
      cached_keys = $alfred.with { |conn| conn.keys("#{VERSION}:#{KEY_PREFIX}:*") }
      (cached_keys || []).each do |cached_key|
        $alfred.with { |conn| conn.expire(cached_key, 0) }
      end
    end

    private

    def typecast_config(config)
      config.each do |config_key, config_value|
        config_type = general_configs.find { |c| c['name'] == config_key }&.dig('type')
        config[config_key] = ActiveRecord::Type::Boolean.new.cast(config_value) if config_type == 'boolean'
      end
    end

    # ConfigLoader memoizes per instance, so building a new one here re-read and
    # re-parsed installation_config.yml on every lookup (~8ms). The file ships with
    # the app and never changes at runtime, so parse it once per process instead.
    def general_configs
      @general_configs ||= ConfigLoader.new.general_configs
    end

    def cache_key(config_key)
      "#{VERSION}:#{KEY_PREFIX}:#{config_key}"
    end

    # One MGET rather than a GET per key. The dashboard reads 23 keys per page render,
    # which cost ~30ms of sequential round trips against ~2ms batched.
    def load_many_from_cache(config_keys)
      cached_values = $alfred.with { |conn| conn.mget(*config_keys.map { |config_key| cache_key(config_key) }) }

      config_keys.zip(cached_values).to_h do |config_key, cached_value|
        [config_key, cached_value.blank? ? backfill_cache(config_key) : JSON.parse(cached_value)['value']]
      end
    end

    def load_from_cache(config_key)
      cached_value = $alfred.with { |conn| conn.get(cache_key(config_key)) }
      return backfill_cache(config_key) if cached_value.blank?

      JSON.parse(cached_value)['value']
    end

    def backfill_cache(config_key)
      cached_value = { value: db_fallback(config_key) }.to_json
      $alfred.with { |conn| conn.set(cache_key(config_key), cached_value, { ex: DEFAULT_EXPIRY }) }
      JSON.parse(cached_value)['value']
    end

    def db_fallback(config_key)
      InstallationConfig.find_by(name: config_key)&.value
    end
  end
end
