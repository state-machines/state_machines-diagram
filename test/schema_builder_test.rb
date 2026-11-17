# frozen_string_literal: true

require 'test_helper'
require 'json'

class SchemaBuilderTest < StateMachines::TestCase
  def setup
    @dragon = Dragon.new
    @troll = Troll.new
  end

  def test_builds_valid_schema_hash
    schema = StateMachines::Diagram::SchemaBuilder.new(@dragon.class.state_machine(:mood)).build

    assert_kind_of Hash, schema
    assert schema[:name]
    assert schema[:initial]
    assert schema[:states]
    assert schema[:events]
  end

  def test_schema_has_correct_name
    schema = StateMachines::Diagram::SchemaBuilder.new(@dragon.class.state_machine(:mood)).build

    assert_equal 'Dragon#mood', schema[:name]
  end

  def test_schema_has_correct_initial_state
    schema = StateMachines::Diagram::SchemaBuilder.new(@dragon.class.state_machine(:mood)).build

    assert_equal 'sleeping', schema[:initial]
  end

  def test_schema_includes_all_states
    schema = StateMachines::Diagram::SchemaBuilder.new(@dragon.class.state_machine(:mood)).build

    assert_includes schema[:states], 'sleeping'
    assert_includes schema[:states], 'hunting'
    assert_includes schema[:states], 'hoarding'
    assert_includes schema[:states], 'rampaging'
  end

  def test_schema_includes_events
    schema = StateMachines::Diagram::SchemaBuilder.new(@dragon.class.state_machine(:mood)).build

    event_names = schema[:events].map { |e| e[:name] }

    assert_includes event_names, 'wake_up'
    assert_includes event_names, 'find_treasure'
    assert_includes event_names, 'enrage'
    assert_includes event_names, 'exhaust'
  end

  def test_event_has_transitions
    schema = StateMachines::Diagram::SchemaBuilder.new(@dragon.class.state_machine(:mood)).build

    wake_up_event = schema[:events].find { |e| e[:name] == 'wake_up' }

    assert wake_up_event
    assert wake_up_event[:transitions]
    assert_predicate wake_up_event[:transitions], :any?
  end

  def test_transition_has_sources_and_target
    schema = StateMachines::Diagram::SchemaBuilder.new(@dragon.class.state_machine(:mood)).build

    wake_up_event = schema[:events].find { |e| e[:name] == 'wake_up' }
    transition = wake_up_event[:transitions].first

    assert transition[:sources]
    assert transition[:target]
    assert_kind_of Array, transition[:sources]
  end

  def test_transition_includes_guards
    schema = StateMachines::Diagram::SchemaBuilder.new(@dragon.class.state_machine(:mood)).build

    wake_up_event = schema[:events].find { |e| e[:name] == 'wake_up' }
    # Find transition with guard
    transition_with_guard = wake_up_event[:transitions].find { |t| t[:guards] }

    # wake_up has if: :hungry? guard
    assert transition_with_guard, 'Should have at least one transition with guards'
    assert_includes transition_with_guard[:guards], 'hungry?'
  end

  def test_schema_serializes_to_json
    builder = StateMachines::Diagram::SchemaBuilder.new(@dragon.class.state_machine(:mood))
    json = builder.to_json

    assert json.start_with?('{')
    assert json.end_with?('}')

    # Should be valid JSON
    parsed = JSON.parse(json)

    assert_equal 'Dragon#mood', parsed['name']
  end

  def test_schema_is_cli_compatible
    schema = StateMachines::Diagram::SchemaBuilder.new(@troll.class.state_machine(:regeneration)).build

    # Verify structure matches MachineSchema from state-machines-rs
    assert schema.key?(:name)
    assert schema.key?(:initial)
    assert schema.key?(:states)
    assert schema.key?(:events)
    # MachineSchema's superstates default to empty; the core has none
    refute schema.key?(:superstates)
    # MachineSchema's async_mode defaults to false; the core has no async mode
    refute schema.key?(:async_mode)

    # States should be array of strings
    assert(schema[:states].all?(String))

    # Events should have name and transitions
    schema[:events].each do |event|
      assert event[:name]
      assert event[:transitions]
      event[:transitions].each do |t|
        assert t[:sources]
        assert t[:target]
      end
    end
  end

  def test_renderer_outputs_machine_schema_format
    io = StringIO.new
    StateMachines::Diagram::Renderer.draw_machine(
      @dragon.class.state_machine(:flight),
      io: io,
      format: :machine_schema
    )

    output = io.string

    assert output.start_with?('{')

    parsed = JSON.parse(output)

    assert_equal 'Dragon#flight', parsed['name']
    assert_equal 'grounded', parsed['initial']
  end

  def test_renderer_machine_schema_method
    schema = StateMachines::Diagram::Renderer.machine_schema(@troll.class.state_machine(:regeneration))

    assert_kind_of Hash, schema
    assert_equal 'Troll#regeneration', schema[:name]
  end

  def test_multiple_source_states_grouped
    schema = StateMachines::Diagram::SchemaBuilder.new(@troll.class.state_machine(:regeneration)).build

    # take_fire_damage transitions from multiple states to suppressed
    fire_event = schema[:events].find { |e| e[:name] == 'take_fire_damage' }

    assert fire_event

    # Should have transition(s) with multiple sources
    suppressed_transition = fire_event[:transitions].find { |t| t[:target] == 'suppressed' }

    assert suppressed_transition
    assert_operator suppressed_transition[:sources].length, :>, 1, 'Should group multiple source states'
  end

  class Gatehouse
    attr_accessor :state, :gate, :alarm

    state_machine :gate, initial: :closed do
      state :open
    end

    state_machine :alarm, initial: :off do
      state :on
    end

    state_machine :state, initial: nil do
      state :idle, :sealed

      event :check do
        transition nil => :idle, if: %i[armed staffed], unless: %i[storm], if_any_state: { gate: :open, alarm: :on }
        transition idle: all - :sealed, unless_state: { gate: :closed }
      end
    end
  end

  def test_state_guards_and_array_conditions_reach_the_transition
    schema = StateMachines::Diagram::SchemaBuilder.new(Gatehouse.state_machines[:state]).build
    check = schema[:events].first

    refute check.key?(:guards), 'the core has no event-level guards'
    assert_equal({ sources: ['nil_state'], target: 'idle',
                   guards: ['armed', 'staffed', 'if_any_state (gate=open, alarm=on)'],
                   unless: ['storm'] }, check[:transitions].first)
  end

  def test_targets_are_those_the_core_reaches
    schema = StateMachines::Diagram::SchemaBuilder.new(Gatehouse.state_machines[:state]).build

    # The core moves to the first state the blacklist allows, the source first
    assert_equal [{ sources: ['idle'], target: 'idle', guards: ['unless_state gate=closed'] }],
                 schema[:events].first[:transitions].drop(1)
  end

  def test_the_nil_state_can_be_initial
    schema = StateMachines::Diagram::SchemaBuilder.new(Gatehouse.state_machines[:state]).build

    # Named by its diagram id, apart from a state named :nil
    assert_equal 'nil_state', schema[:initial]
  end

  def test_a_dynamic_initial_state_is_refused_not_evaluated
    klass = Class.new do
      attr_accessor :state

      state_machine initial: lambda(&:pick) do
        state :a, :b
      end
    end

    error = assert_raises(ArgumentError) { StateMachines::Diagram::SchemaBuilder.new(klass.state_machines[:state]).build }
    assert_match(/needs a static initial state/, error.message)
  end

  class Relay
    attr_accessor :state

    state_machine :state, initial: :a do
      state :b, :c, :d
      before_transition from: :a, do: :from_a
      around_transition to: :c, do: :wrap_c
      after_transition on: :go, do: :after_go

      event :go do
        transition a: :b, if: :p
        transition %i[a b] => :c
        transition a: :d, if: :q
      end

      event :twice do
        transition a: :b
        transition a: :c
        transition b: :d, unless: :r
      end

      event :first do
        transition :a => :b, [:a] => :c
      end

      event :never
    end
  end

  def relay_events
    StateMachines::Diagram::SchemaBuilder.new(Relay.state_machines[:state]).build[:events].to_h { [it[:name], it] }
  end

  def test_branches_from_one_source_are_ordered_branching_with_a_fallback
    assert_equal({ name: 'go', branching: true, transitions: [
                   { sources: ['a'], target: 'b', guards: ['p'], before: ['from_a'], after: ['after_go'] },
                   { sources: ['a'], target: 'c', before: ['from_a'], around: ['wrap_c'], after: ['after_go'],
                     fallback: true },
                   { sources: ['b'], target: 'c', around: ['wrap_c'], after: ['after_go'], fallback: true }
                 ] }, relay_events['go'])
  end

  def test_a_source_an_unguarded_branch_takes_reaches_no_later_branch
    assert_equal([[['a'], 'b'], [['b'], 'd']], relay_events['twice'][:transitions].map { [it[:sources], it[:target]] })
    refute relay_events['twice'].key?(:branching)
  end

  def test_only_the_first_requirement_from_a_source_counts
    assert_equal([[['a'], 'b']], relay_events['first'][:transitions].map { [it[:sources], it[:target]] })
  end

  def test_final_states_are_those_the_core_calls_final
    schema = StateMachines::Diagram::SchemaBuilder.new(Relay.state_machines[:state]).build

    assert_equal %w[c d], schema[:final_states]
  end

  def schema_of(&)
    klass = Class.new do
      attr_accessor :state

      class_eval(&)
    end
    StateMachines::Diagram::SchemaBuilder.new(klass.state_machines[:state]).build
  end

  def test_a_state_left_only_by_loopbacks_is_not_final
    schema = schema_of do
      state_machine :state, initial: :idle do
        state :done
        event(:wait) { transition all - :done => same }
        event(:finish) { transition idle: :done }
      end
    end
    loop_only = schema_of { state_machine(:state, initial: :idle) { event(:wait) { transition all => same } } }

    assert_equal %w[done], schema[:final_states]
    refute loop_only.key?(:final_states)
  end

  def test_required_fields_stay_when_empty
    schema = schema_of { state_machine(:state, initial: :idle) { event(:never) } }

    assert_equal({ name: '#state', initial: 'idle', states: %w[idle], events: [], final_states: %w[idle] }, schema)
  end

  def test_nil_and_a_state_named_nil_get_distinct_names
    schema = schema_of do
      state_machine :state, initial: nil do
        state :nil
        event(:go) { transition nil => :nil }
      end
    end

    assert_equal %w[nil_state nil], schema[:states]
    assert_equal [{ sources: %w[nil_state], target: 'nil' }], schema[:events].first[:transitions]
  end

  def test_a_false_or_empty_condition_is_no_condition
    schema = schema_of do
      state_machine :state, initial: :idle do
        event(:go) do
          transition idle: :a, if: false, unless: []
          transition idle: :b
        end
      end
    end

    assert_equal({ name: 'go', transitions: [{ sources: %w[idle], target: 'a' }] }, schema[:events].first)
  end

  def test_a_branch_whose_code_condition_never_passes_is_neither_taken_nor_a_fallback
    schema = schema_of do
      state_machine :state, initial: :idle do
        event(:go) do
          transition idle: :a, if: ''
          transition idle: :b, unless: ''
          transition idle: :c
        end
      end
    end

    assert_equal({ name: 'go', transitions: [{ sources: %w[idle], target: 'b' }] }, schema[:events].first)
  end

  def test_a_conditional_callback_is_refused
    error = assert_raises(ArgumentError) do
      schema_of do
        state_machine :state, initial: :idle do
          before_transition on: :go, if: :enabled?, do: :audit
          event(:go) { transition idle: :a }
        end
      end
    end
    assert_equal 'MachineSchema cannot express the conditional callback audit (if enabled?) on go', error.message
  end

  def test_an_event_without_transitions_is_left_out
    refute relay_events.key?('never')
  end

  # What state-machines-rs MachineSchema#validate requires of an event's candidates
  def test_every_fixture_schema_keeps_the_rs_branching_rules
    owners = [Dragon, Mage, Troll, Regiment, Battle, Character, Commander, Relay]
    machines = owners.flat_map { it.state_machines.values }
    machines.each do |machine|
      StateMachines::Diagram::SchemaBuilder.new(machine).build[:events].each { assert_rs_candidates(it) }
    end
  end

  def assert_rs_candidates(event)
    transitions = event[:transitions]
    sources = transitions.flat_map { it[:sources] }

    refute_empty transitions
    assert_equal sources.uniq.size < sources.size, event.key?(:branching), event[:name]
    return unless event[:branching]

    transitions.each_with_index do |transition, index|
      guarded = transition.key?(:guards) || transition.key?(:unless)

      assert_equal !guarded, transition.fetch(:fallback, false), "#{event[:name]}: #{transition}"
      later = transitions.drop(index + 1).flat_map { it[:sources] }

      assert_empty transition[:sources] & later, "fallback must be last: #{event[:name]}" if transition[:fallback]
    end
  end

  def test_loopback_transitions
    schema = StateMachines::Diagram::SchemaBuilder.new(@dragon.class.state_machine(:mood)).build

    # find_treasure has hoarding -> hoarding (same state)
    find_treasure = schema[:events].find { |e| e[:name] == 'find_treasure' }
    loopback = find_treasure[:transitions].find { |t| t[:sources].include?('hoarding') && t[:target] == 'hoarding' }

    assert loopback, 'Should include loopback transition'
  end
end
