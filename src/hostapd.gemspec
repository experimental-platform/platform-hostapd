# coding: utf-8
$LOAD_PATH.push File.expand_path("../lib", __FILE__)
require 'hostapd/version'

Gem::Specification.new do |spec|
  spec.name          = "hostapd"
  spec.version       = Hostapd::VERSION
  spec.authors       = ["Hinnerk Haardt"]
  spec.email         = ["haardt@information-control.de"]

  spec.summary       = %q{Hostapd configuration tool.}
  spec.description   = %q{This build a hostapd configuration file from globally avaliable system information and system configuration.}
  spec.homepage      = "https://github.com/experimental-platform/platform-hostapd"
  spec.license       = "Apache 2.0"

  # Prevent pushing this gem to RubyGems.org by setting 'allowed_push_host', or
  # delete this section to allow pushing this gem to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = "TODO: Set to 'http://mygemserver.com'"
  else
    raise "RubyGems 2.0 or newer is required to protect against public gem pushes."
  end

  spec.files         = Dir['**/*'].reject { |f| f.match(%r{^(test|spec|features|coverage)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.11"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "minitest-reporters"
  spec.add_development_dependency "simplecov"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "guard"
  spec.add_development_dependency "guard-minitest"
end
