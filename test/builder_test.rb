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

  class Hatch
    state_machine initial: :sealed do
      state :ajar
      state :open

      event :release do
        transition sealed: all - :ajar
      end
    end
  end

  def test_loopback_over_several_states_draws_only_the_transitions_the_machine_performs
    assert_equal performed_pairs(Golem), drawn_pairs(Golem)
  end

  def test_excluded_target_is_never_drawn_as_the_destination
    assert_equal performed_pairs(Hatch), drawn_pairs(Hatch)
  end

  private

  def drawn_pairs(klass)
    StateMachines::Diagram::Builder.new(klass.state_machines[:state]).build.transitions.map do |transition|
      [transition.source_state_id, transition.target_state_id]
    end.uniq.sort
  end
end
