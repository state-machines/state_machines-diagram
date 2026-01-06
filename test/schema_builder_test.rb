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
    assert wake_up_event[:transitions].any?
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
    assert schema.key?(:superstates)
    assert schema.key?(:async_mode)

    # States should be array of strings
    assert schema[:states].all? { |s| s.is_a?(String) }

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
    assert suppressed_transition[:sources].length > 1, 'Should group multiple source states'
  end

  def test_loopback_transitions
    schema = StateMachines::Diagram::SchemaBuilder.new(@dragon.class.state_machine(:mood)).build

    # find_treasure has hoarding -> hoarding (same state)
    find_treasure = schema[:events].find { |e| e[:name] == 'find_treasure' }
    loopback = find_treasure[:transitions].find { |t| t[:sources].include?('hoarding') && t[:target] == 'hoarding' }

    assert loopback, 'Should include loopback transition'
  end
end
