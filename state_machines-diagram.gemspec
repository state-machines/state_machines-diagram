# frozen_string_literal: true

require_relative 'lib/state_machines/diagram/version'

Gem::Specification.new do |spec|
  spec.name          = 'state_machines-diagram'
  spec.version       = StateMachines::Diagram::VERSION
  spec.authors       = ['Abdelkader Boudih']
  spec.email         = ['terminale@gmail.com']
  spec.summary       = 'Diagram building for state machines'
  spec.description   = 'Diagram module for state machines. Builds diagram representations of state machines that can be rendered in various formats'
  spec.homepage      = 'https://github.com/state-machines/state_machines-diagram'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.3.0'

  spec.files         = Dir['{lib}/**/*', 'LICENSE.txt', 'README.md']
  spec.require_paths = ['lib']

  spec.add_dependency 'diagram', '~> 0.3.4'
  spec.add_dependency 'state_machines', '~> 0.100', '>= 0.100.4'

  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'minitest', '= 5.27.0'
  spec.add_development_dependency 'rake'
  spec.metadata['rubygems_mfa_required'] = 'true'
end
