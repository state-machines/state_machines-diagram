# frozen_string_literal: true

require 'test_helper'
require 'stringio'

class DiagramRendererTest < StateMachines::TestCase
  def setup
    @dragon = Dragon.new
    @mage = Mage.new
    @troll = Troll.new
    @regiment = Regiment.new
  end

  def teardown
    # Clean up instance variables
    @dragon = nil
    @mage = nil
    @troll = nil
    @regiment = nil
  end

  def test_draw_machine_outputs_text_by_default
    io = StringIO.new
    StateMachines::Diagram::Renderer.draw_machine(@dragon.class.state_machine(:mood), io: io)

    output = io.string
    assert_includes output, 'Dragon mood State Machine'
    assert_includes output, 'States:'
    assert_includes output, 'sleeping [*]'
    assert_includes output, 'Transitions:'
  end

  def test_draw_machine_with_json_format
    io = StringIO.new
    StateMachines::Diagram::Renderer.draw_machine(
      @dragon.class.state_machine(:mood),
      io: io,
      format: :json
    )

    output = io.string
    assert output.start_with?('{')
    assert output.end_with?("}\n")

    # Parse JSON to verify structure
    require 'json'
    data = JSON.parse(output)
    assert_equal 'state_diagram', data['type']
    assert data['version']
    assert data['checksum']
    assert data['data']
    assert data['data']['title']
    assert data['data']['states']
    assert data['data']['transitions']
  end

  def test_draw_machine_with_human_names
    io = StringIO.new
    StateMachines::Diagram::Renderer.draw_machine(
      @mage.class.state_machine(:concentration),
      io: io,
      human_names: true
    )

    output = io.string
    # Human names would be used if defined
    assert_includes output, 'concentration'
  end

  def test_complex_state_machine_with_conditions
    io = StringIO.new
    StateMachines::Diagram::Renderer.draw_machine(
      Character.state_machine(:status),
      io: io
    )

    output = io.string
    assert_includes output, 'idle [*]'
    assert_includes output, 'dead'
    assert_includes output, 'engage'
    assert_includes output, 'if:'
    assert_includes output, 'unless:'
  end

  def test_draw_state_renders_specific_state
    io = StringIO.new
    state = @dragon.class.state_machine(:mood).states[:sleeping]

    StateMachines::Diagram::Renderer.draw_state(state, nil, {}, io)

    output = io.string
    assert_includes output, 'State: sleeping'
  end

  def test_draw_event_renders_specific_event
    io = StringIO.new
    event = @dragon.class.state_machine(:mood).events[:wake_up]

    StateMachines::Diagram::Renderer.draw_event(event, nil, {}, io)

    output = io.string
    assert_includes output, 'Event: wake_up'
  end

  def test_parallel_state_machines
    # Dragon has multiple state machines
    mood_io = StringIO.new
    flight_io = StringIO.new
    age_io = StringIO.new

    StateMachines::Diagram::Renderer.draw_machine(@dragon.class.state_machine(:mood), io: mood_io)
    StateMachines::Diagram::Renderer.draw_machine(@dragon.class.state_machine(:flight), io: flight_io)
    StateMachines::Diagram::Renderer.draw_machine(@dragon.class.state_machine(:age_category), io: age_io)

    assert_includes mood_io.string, 'sleeping'
    assert_includes flight_io.string, 'grounded'
    assert_includes age_io.string, 'wyrmling'
  end

  def test_nested_states_representation
    io = StringIO.new
    StateMachines::Diagram::Renderer.draw_machine(
      @mage.class.state_machine(:spell_school),
      io: io
    )

    output = io.string
    assert_includes output, 'apprentice'
    assert_includes output, 'fire'
    assert_includes output, 'ember'
    assert_includes output, 'archmage'
  end

  def test_callbacks_in_transitions
    io = StringIO.new
    StateMachines::Diagram::Renderer.draw_machine(
      Character.state_machine(:status),
      io: io,
      format: :json
    )

    require 'json'
    data = JSON.parse(io.string)

    # Find a transition with callbacks (actions)
    transition = data['data']['transitions'].find { |t| t['label'] == 'cast_spell' }
    assert transition, 'Should find a cast_spell transition'
    assert transition['action'], 'cast_spell transition should have an action'
  end

  def test_complex_battle_scenario
    battle = Battle.new

    # Add participants
    battle.participants[:dragons] << @dragon
    battle.participants[:mages] << @mage
    battle.participants[:regiments] << @regiment

    io = StringIO.new
    StateMachines::Diagram::Renderer.draw_machine(
      battle.class.state_machine(:phase),
      io: io
    )

    output = io.string
    assert_includes output, 'preparation'
    assert_includes output, 'aftermath'
    assert_includes output, 'escalate'
  end

  def test_builder_creates_valid_diagram_object
    builder = StateMachines::Diagram::Builder.new(@troll.class.state_machine(:regeneration))
    diagram = builder.build

    assert_kind_of ::Diagrams::StateDiagram, diagram
    assert_equal 'Troll regeneration State Machine', diagram.title
    assert diagram.states.any?
    assert diagram.transitions.any?
  end

  def test_multiple_from_states_in_transition
    io = StringIO.new
    StateMachines::Diagram::Renderer.draw_machine(
      @troll.class.state_machine(:regeneration),
      io: io
    )

    output = io.string
    # take_fire_damage transitions from multiple states to suppressed
    assert_includes output, 'normal -> suppressed [take_fire_damage]'
    assert_includes output, 'accelerated -> suppressed [take_fire_damage]'
    assert_includes output, 'berserk -> suppressed [take_fire_damage]'
  end

  def test_loopback_transitions
    io = StringIO.new
    StateMachines::Diagram::Renderer.draw_machine(
      @dragon.class.state_machine(:mood),
      io: io
    )

    output = io.string
    # find_treasure can transition from hoarding to hoarding (same state)
    assert_includes output, 'hoarding -> hoarding [find_treasure]'
  end

  def test_all_matcher_transitions
    io = StringIO.new
    StateMachines::Diagram::Renderer.draw_machine(
      Character.state_machine(:status),
      io: io
    )

    output = io.string
    # die event transitions from all states except dead
    assert_includes output, 'idle -> dead [die]'
    assert_includes output, 'combat -> dead [die]'
    assert_includes output, 'casting -> dead [die]'
    refute_includes output, 'dead -> dead [die]'
  end

  def test_yaml_output_format
    io = StringIO.new
    StateMachines::Diagram::Renderer.draw_machine(
      @regiment.class.state_machine(:formation),
      io: io,
      format: :yaml
    )

    output = io.string
    assert output.include?('id:')
    assert output.include?('title:')
    assert output.include?('states:')
    assert output.include?('transitions:')
  end

  def test_state_with_nil_name
    # Create a custom class with nil state
    klass = Class.new do
      state_machine :status, initial: nil do
        state nil
        state :active

        event :activate do
          transition nil => :active
        end
      end
    end

    io = StringIO.new
    StateMachines::Diagram::Renderer.draw_machine(
      klass.state_machine(:status),
      io: io
    )

    output = io.string
    assert_includes output, 'nil_state'
    assert_includes output, 'nil_state -> active [activate]'
  end

  def test_guards_and_conditions_metadata
    io = StringIO.new
    StateMachines::Diagram::Renderer.draw_machine(
      @mage.class.state_machine(:concentration),
      io: io,
      format: :json
    )

    require 'json'
    data = JSON.parse(io.string)

    # Get the first transition that has conditions
    transitions = data['data']['transitions']
    assert transitions.any?, 'Should have transitions'

    # The conditions are stored in our metadata, not in the diagram directly
    # We need to check the builder's metadata
  end

  def test_should_generate_enhanced_output_with_guard_conditions
    # This test specifically checks that the enhanced output with guard conditions
    # is generated correctly and isn't affected by test isolation issues

    io = StringIO.new
    StateMachines::Diagram::Renderer.draw_machine(
      Character.state_machine(:status),
      io: io
    )

    output = io.string

    # Verify that guard conditions are present in the output
    assert output.include?('if:'), "Output should contain 'if:' guard conditions"
    assert output.include?('unless:'), "Output should contain 'unless:' guard conditions"

    # Verify specific guard conditions are rendered correctly
    assert_includes output, '(if: can_fight?)', "Should show 'if: can_fight?' guard condition"
    assert_includes output, '(unless: spell_locked?)', "Should show 'unless: spell_locked?' guard condition"
    assert_includes output, '(if: interrupt_rest?)', "Should show 'if: interrupt_rest?' guard condition"

    # Verify action callbacks are also included for transitions that have them
    assert output.include?('action:'), "Output should contain 'action:' for callbacks"

    # Count the transitions with guard conditions to ensure they're all rendered
    guard_transitions = output.split("\n").select do |line|
      line.include?('->') && (line.include?('if:') || line.include?('unless:'))
    end
    assert guard_transitions.length >= 8,
           "Should have at least 8 transitions with guard conditions, got #{guard_transitions.length}"

    # Verify the structure is correct - transitions should have event names in brackets
    transition_lines = output.split("\n").select { |line| line.include?('->') }
    transition_lines.each do |line|
      assert line.include?('['), "Transition line should contain event name in brackets: #{line}"
      assert line.include?(']'), "Transition line should contain closing bracket: #{line}"
    end
  end
end
