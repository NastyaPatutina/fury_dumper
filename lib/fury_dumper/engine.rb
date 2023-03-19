# frozen_string_literal: true

module FuryDumper
  class Engine < ::Rails::Engine
    isolate_namespace FuryDumper
  end
end
