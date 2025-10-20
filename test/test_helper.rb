# frozen_string_literal: true

require 'minitest/autorun'
require 'state_machines-diagram'
require 'state_machines/test_helper'

# Ignore method conflicts for test classes
StateMachines::Machine.ignore_method_conflicts = true

# Require all model classes
require_relative 'models/character'
require_relative 'models/dragon'
require_relative 'models/mage'
require_relative 'models/troll'
require_relative 'models/regiment'
require_relative 'models/commander'
require_relative 'models/battle'

# Set deterministic seed for reproducible test runs - can be overridden with --seed
ENV['TESTOPTS'] ||= '--seed=12345'

class StateMachines::TestCase < Minitest::Test
  # Clean base test case for state machines diagram tests
end

class Minitest::Test
  include StateMachines::TestHelper
end
