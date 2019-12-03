module FuryDumper
  class Api
    HEALTH_URL = "fury_dumper/health".freeze

    # @param ms_name[String] - name of microservice for request
    def initialize(ms_name)
      @ms_name      = ms_name
      @http_client  = init_http_client(ms_name)
      @ms_config    = FuryDumper::Config.get_service_config(@ms_name)
    end

    # Send dumping request to microservice
    #
    # @param ms_model[String] - name of table to start dumping
    # @param ms_field_name[String] - field in table for find records for dump
    # @param field_values[Array] - values of access_way for dumping
    #
    # @example FuryDumper::Dumper.dump("users", "id", [1,2,3])
    def send_request(ms_model, ms_field_name, field_values)
      # Check gem is included to microservice(ms)
      return unless check_ms_health

      message = {
          model_name:   ms_model,
          field_name:   ms_field_name,
          field_values: field_values,
          password:     Encrypter.encrypt(@ms_config['password']),
          host:         @ms_config['host'],
          port:         @ms_config['port'],
          user:         @ms_config['user'],
          database:     @ms_config['database'],
      }.to_json

      response = @http_client.post("fury_dumper/dump", message)

      is_ok_responce?(response)
    rescue StandardError => error
      notify_error(error)
      return nil
    end

    def check_ms_health
      response = @http_client.get("fury_dumper/health")

      is_ok_responce?(response)
    rescue StandardError => error
      notify_error(error)
      return false
    end

    def notify_error(error)
      context = { error: error }
      BugTracker.notify error_message: "Не смогли получить данные из #{@ms_name}", context: context
    end

    def init_http_client(ms_name)
      base_url = Rails.application.class.parent_name.constantize.config.deep_symbolize_keys[ms_name.to_sym][:endpoint]
      HTTPClient.new(base_url: base_url, default_header: default_header)
    rescue StandardError => error
      notify_error(error)
      return nil
    end

    def default_header
      {
          'Content-Type' => 'application/x-www-form-urlencoded, charset=utf-8',
          'Authorization' => 'Bearer 40637702df32be88886c7083c4fdb075',
          'Accept' => 'application/x-protobuf,application/json'
      }
    end

    def is_ok_responce?(response)
      if response.status == 200
        true
      else
        raise "[#{@ms_name}] invalid response status => #{response.status}/#{response.body.inspect}"
      end
    end
  end
end
