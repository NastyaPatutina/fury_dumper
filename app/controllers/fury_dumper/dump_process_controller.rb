module FuryDumper
  class DumpProcessController < ApplicationController
    def dump
      data = JSON.parse(request.body.read)
      FuryDumper.dump(password:     Encrypter.decrypt(data['password']),
                      host:         data['host'],
                      port:         data['port'],
                      user:         data['user'],
                      database:     data['database'],
                      model_name:   data['model_name'],
                      field_values: data['field_values'],
                      field_name:   data['field_name'],
                      debug_mode:   :none,
                      ask:          false)

      render json: {message: :ok}
    end

    def health
      render json: { message: :ok }
    end
  end
end
