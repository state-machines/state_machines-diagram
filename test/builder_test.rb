# frozen_string_literal: true

require 'test_helper'

class BuilderTest < StateMachines::TestCase
  class Golem
    state_machine initial: :guarding do
      state :dormant

      event :hold_position do
        transition %i[guarding dormant] => same
      end
    end
  end

  def test_loopback_over_several_states_draws_only_the_transitions_the_machine_performs
    machine = Golem.state_machines[:state]

    performed = machine.states.map(&:name).map do |state|
      golem = Golem.new
      golem.state = state.to_s
      golem.hold_position
      [state.to_s, golem.state]
    end

    drawn = StateMachines::Diagram::Builder.new(machine).build.transitions.map do |transition|
      [transition.source_state_id, transition.target_state_id]
    end

    assert_equal performed.sort, drawn.sort
  end
end
