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

  class Oddity
    attr_accessor :state, :gate, :alarm

    state_machine :gate, initial: :closed do
      state :open
    end

    state_machine :alarm, initial: :off do
      state :on
    end

    state_machine :state, initial: :idle do
      state nil, :nil_state, :"*", :" ", :"%2a", :"a[b"

      event :go do
        transition idle: :"*"
      end

      event :" " do
        transition :"*" => :" "
      end

      event :"" do
        transition :" " => nil
      end

      event :reset do
        transition [nil, :nil_state, :"%2a", :"a[b"] => :idle
      end

      event :check do
        transition idle: :idle, if_any_state: { gate: :open, alarm: :on }, unless_all_states: { gate: :closed, alarm: :off }
      end
    end
  end

  class Alone
    state_machine initial: :alone
  end

  class Empty
    state_machine initial: :"" do
      event :go do
        transition "": :done
      end
    end
  end

  # The core finds nil and :"" as the same state
  class NilAndEmpty
    state_machine initial: :idle do
      state nil

      event :clear do
        transition idle: :""
      end
    end
  end

  def test_every_legal_state_name_gets_its_own_diagram_id
    builder = StateMachines::Diagram::Builder.new(Oddity.state_machines[:state])
    diagram = builder.build

    ids = diagram.states.map(&:id)
    assert_equal ids.uniq, ids
    assert_equal ['idle', 'nil_state', '%6e696c5f7374617465', '%2a', '%20', '%253261', 'a[b'].sort, ids.sort
    names = ids.map { |id| builder.state_metadata.fetch(id)[:name] }
    assert_equal ['idle', nil, 'nil_state', '*', ' ', '%2a', 'a[b'].sort_by(&:to_s), names.sort_by(&:to_s)
  end

  def test_the_nil_state_reads_as_the_core_shows_it
    builder = StateMachines::Diagram::Builder.new(Oddity.state_machines[:state])
    builder.build

    assert_nil builder.state_metadata.fetch('nil_state')[:name]
    assert_equal 'nil', builder.state_metadata.fetch('nil_state')[:label]
    assert_equal 'nil_state', builder.state_metadata.fetch('%6e696c5f7374617465')[:label]
  end

  class Nameless
    attr_accessor :state

    state_machine :state, initial: :idle do
      state :idle, human_name: ->(*) {}

      event :go, human_name: ->(*) {} do
        transition idle: :done
      end
    end
  end

  def test_a_nil_human_name_falls_back_to_the_name
    builder = StateMachines::Diagram::Builder.new(Nameless.state_machines[:state], human_names: true)
    diagram = builder.build

    assert_equal 'idle', builder.state_metadata.fetch('idle')[:label]
    assert_equal 'idle', diagram.states.first.label
    assert_equal ['go'], builder.transition_metadata.map { it[:label] }
    assert_equal ['go'], diagram.transitions.map(&:label)
  end

  def test_an_empty_state_name_is_escaped
    builder = StateMachines::Diagram::Builder.new(Empty.state_machines[:state])
    diagram = builder.build

    assert_equal %w[% done], diagram.states.map(&:id)
    assert_equal '', builder.state_metadata.fetch('%')[:name]
    assert_equal [%w[% done]], diagram.transitions.map { [it.source_state_id, it.target_state_id] }
  end

  def test_a_state_the_core_finds_under_two_names_is_drawn_once
    diagram = StateMachines::Diagram::Builder.new(NilAndEmpty.state_machines[:state]).build

    assert_equal %w[idle nil_state], diagram.states.map(&:id)
    assert_equal [%w[idle nil_state]], diagram.transitions.map { [it.source_state_id, it.target_state_id] }
  end

  def test_blank_names_stay_in_the_metadata_not_the_diagram
    builder = StateMachines::Diagram::Builder.new(Oddity.state_machines[:state])
    diagram = builder.build

    assert_nil diagram.states.find { |state| state.id == '%20' }.label
    assert_equal ' ', builder.state_metadata.fetch('%20')[:label]
    assert_equal [' ', ''], builder.transition_metadata.filter_map { |data| data[:label] if data[:label].strip.empty? }
    assert(diagram.transitions.none? { |transition| transition.label&.strip&.empty? })
  end

  def test_state_guards_keep_their_group_and_kind
    builder = StateMachines::Diagram::Builder.new(Oddity.state_machines[:state])
    guard = builder.build.transitions.find { |transition| transition.label == 'check' }.guard

    assert_equal 'unless_all_states (gate=closed, alarm=off) && if_any_state (gate=open, alarm=on)', guard
  end

  def test_a_state_both_initial_and_final_keeps_both
    builder = StateMachines::Diagram::Builder.new(Alone.state_machines[:state])
    builder.build

    assert_equal true, builder.state_metadata.fetch('alone')[:initial]
    assert_equal true, builder.state_metadata.fetch('alone')[:final]
  end

  private

  def drawn_pairs(klass)
    StateMachines::Diagram::Builder.new(klass.state_machines[:state]).build.transitions.map do |transition|
      [transition.source_state_id, transition.target_state_id]
    end.uniq.sort
  end
end
