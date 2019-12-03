FuryDumper::Engine.routes.draw do
  get '/health', to: 'dump_process#health'
  post '/dump', to: 'dump_process#dump'
end
