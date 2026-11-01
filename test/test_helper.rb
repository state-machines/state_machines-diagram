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

# The (source, target) pairs a machine performs, found by firing every event from every state
module PerformedTransitions
  def performed_pairs(klass, machine_name = :state)
    machine = klass.state_machines[machine_name]
    attribute = machine.attribute

    machine.states.map(&:name).compact.flat_map do |state|
      machine.events.filter_map do |event|
        object = klass.new
        object.public_send(:"#{attribute}=", state.to_s)
        next unless object.public_send(event.name)

        [state.to_s, object.public_send(attribute).to_s]
      end
    end.uniq.sort
  end
end

class Minitest::Test
  include StateMachines::TestHelper
  include PerformedTransitions
end
