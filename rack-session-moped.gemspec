# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "rack-session-moped/version"

Gem::Specification.new do |s|
  s.name        = "rack-session-moped"
  s.version     = Rack::Session::Moped::VERSION
  s.authors     = ["Eric Freeman", "Kouhei Aoyagi", "Masato Igarashi"]
  s.email       = []
  s.homepage    = "https://github.com/Chillibear/rack-session-moped"
  s.summary     = %q{Rack session store for MongoDB using Moped driver}
  s.description = %q{Rack session store for MongoDB using Moped driver}

  #s.rubyforge_project = "rack-session-mongo"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  # specify any dependencies here; for example:
  s.add_development_dependency "bacon"
  s.add_runtime_dependency "rack"
  s.add_runtime_dependency "moped"
end
