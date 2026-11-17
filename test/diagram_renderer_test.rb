# frozen_string_literal: true

require 'test_helper'
require 'stringio'

class DiagramRendererTest < StateMachines::TestCase
  class Sentinel
    state_machine initial: :watching do
      state :dozing

      event :hold do
        transition %i[watching dozing] => same
      end

      event :rouse do
        transition dozing: :watching
      end
    end
  end

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

  def test_per_state_diagram_draws_every_transition_touching_that_state
    machine = Sentinel.state_machines[:state]
    performed = performed_pairs(Sentinel)

    machine.states.map(&:name).each do |state|
      io = StringIO.new
      StateMachines::Diagram::Renderer.draw_state(machine.states[state], nil, {}, io)
      drawn = io.string.lines.grep(/->/).map { |line| line[/(\S+) -> (\S+)/, 0].split(' -> ') }.uniq.sort

      assert_equal performed.select { |pair| pair.include?(state.to_s) }, drawn, "draw_state(#{state})"
    end
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
    assert_predicate diagram.states, :any?
    assert_predicate diagram.transitions, :any?
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

    assert_includes output, 'id:'
    assert_includes output, 'title:'
    assert_includes output, 'states:'
    assert_includes output, 'transitions:'
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

    assert_includes output, '  - nil [*]'
    assert_includes output, 'nil -> active [activate]'
  end

  def test_guards_and_conditions_metadata
    io = StringIO.new
    StateMachines::Diagram::Renderer.draw_machine(
      @mage.class.state_machine(:concentration),
      io: io,
      format: :json
    )

    data = JSON.parse(io.string)
    conditions = data['metadata']['transitions'].map { it['conditions'] }

    # The guard text is in the diagram, its structure in the metadata
    assert_includes conditions, { 'if' => [], 'unless' => ['iron_will?'] }
    assert_includes data['data']['transitions'].map { it['guard'] }, '!iron_will?'
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

    # Verify specific guard conditions are rendered correctly
    assert_includes output, '(if: can_fight?)', "Should show 'if: can_fight?' guard condition"
    assert_includes output, '(unless: spell_locked?)', "Should show 'unless: spell_locked?' guard condition"
    assert_includes output, '(if: interrupt_rest?)', "Should show 'if: interrupt_rest?' guard condition"

    # Verify action callbacks are also included for transitions that have them
    assert_includes output, 'action:', "Output should contain 'action:' for callbacks"

    # Count the transitions with guard conditions to ensure they're all rendered
    guard_transitions = output.split("\n").select do |line|
      line.include?('->') && (line.include?('if:') || line.include?('unless:'))
    end

    assert_operator guard_transitions.length, :>=, 8,
                    "Should have at least 8 transitions with guard conditions, got #{guard_transitions.length}"

    # Verify the structure is correct - transitions should have event names in brackets
    transition_lines = output.split("\n").select { |line| line.include?('->') }
    transition_lines.each do |line|
      assert_includes line, '[', "Transition line should contain event name in brackets: #{line}"
      assert_includes line, ']', "Transition line should contain closing bracket: #{line}"
    end
  end

  def test_text_shows_the_names_a_diagram_cannot_hold
    klass = Class.new do
      attr_accessor :state

      state_machine :state, initial: :idle do
        event :go do
          transition idle: :*
        end

        event :' ' do
          transition '*': :' '
        end
      end
    end

    io = StringIO.new
    StateMachines::Diagram::Renderer.draw_machine(klass.state_machine(:state), io: io)

    output = io.string

    assert_includes output, "  - *\n"
    assert_includes output, "  -   (O)\n"
    assert_includes output, '  - idle -> * [go]'
    assert_includes output, '  - * ->   [ ]'
  end

  def test_json_output_loads_back_with_a_valid_checksum
    machine = Character.state_machine(:status)
    io = StringIO.new
    StateMachines::Diagram::Renderer.draw_machine(machine, io: io, format: :json)

    loaded = Diagrams::Base.from_json(io.string)

    assert_equal StateMachines::Diagram::Builder.new(machine).build, loaded
    assert_equal loaded.checksum, JSON.parse(io.string)['checksum']
  end

  def test_yaml_output_loads_back_with_safe_load
    require 'yaml'
    machine = Character.state_machine(:status)
    io = StringIO.new
    StateMachines::Diagram::Renderer.draw_machine(machine, io: io, format: :yaml)

    assert_equal StateMachines::Diagram::Builder.new(machine).build, Diagrams::Base.from_h(YAML.safe_load(io.string))
  end

  def test_json_metadata_keeps_structured_guards_and_callbacks_beside_the_diagram
    io = StringIO.new
    StateMachines::Diagram::Renderer.draw_machine(BuilderTest::Vault.state_machine(:state), io: io, format: :json)

    document = JSON.parse(io.string)

    assert_equal(%w[locked opened], document['metadata']['states'].map { it['name'] })
    open = document['metadata']['transitions'].first

    assert_equal({ 'if' => %w[key_turned code_entered], 'unless' => %w[alarm jammed] }, open['conditions'])
    assert_equal %w[wrap], open['callbacks']['around']
    assert_equal document['data']['transitions'].size, document['metadata']['transitions'].size
  end

  def test_json_metadata_keeps_state_guard_requirements
    io = StringIO.new
    StateMachines::Diagram::Renderer.draw_machine(SchemaBuilderTest::Gatehouse.state_machine(:state), io: io,
                                                                                                      format: :json)

    conditions = JSON.parse(io.string)['metadata']['transitions'].first['conditions']

    assert_equal({ 'gate' => 'open', 'alarm' => 'on' }, conditions['if_any_state'])
  end

  def test_text_shows_array_conditions_and_state_guards_one_by_one
    io = StringIO.new
    StateMachines::Diagram::Renderer.draw_machine(SchemaBuilderTest::Gatehouse.state_machine(:state), io: io)

    assert_includes io.string, '  - nil -> idle [check] (if: armed) (if: staffed) (unless: storm) ' \
                               '(if_any_state: gate=open, alarm=on)'
  end

  def test_branch_draws_through_the_core
    machine = BuilderTest::Vault.state_machine(:state)
    event = machine.events[:open]
    io = StringIO.new

    diagram = event.branches.first.draw(nil, event, [], io)

    assert_kind_of Diagrams::StateDiagram, diagram
    assert io.string.start_with?("Event: open, branch 1\n")
    assert_includes io.string, '  - locked -> opened [open]'
  end

  def test_an_unknown_format_is_refused
    error = assert_raises(ArgumentError) do
      StateMachines::Diagram::Renderer.draw_machine(Character.state_machine(:status), io: StringIO.new,
                                                                                      format: :mermaid)
    end
    assert_match(/unknown format :mermaid/, error.message)
  end

  def test_machine_schema_is_refused_for_part_of_a_machine
    state = Character.state_machine(:status).states[:idle]

    assert_raises(ArgumentError) do
      StateMachines::Diagram::Renderer.draw_state(state, nil, { format: :machine_schema }, StringIO.new)
    end
  end

  def test_text_marks_a_state_both_initial_and_final
    klass = Class.new do
      attr_accessor :state

      state_machine :state, initial: :alone
    end

    io = StringIO.new
    StateMachines::Diagram::Renderer.draw_machine(klass.state_machine(:state), io: io)

    assert_includes io.string, '  - alone [*] (O)'
  end
end
