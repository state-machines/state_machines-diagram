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
      state nil, :nil_state, :*, :' ', :'%2a', :'a[b'

      event :go do
        transition idle: :*
      end

      event :' ' do
        transition '*': :' '
      end

      event :"" do
        transition ' ': nil
      end

      event :reset do
        transition [nil, :nil_state, :'%2a', :'a[b'] => :idle
      end

      event :check do
        transition idle: :idle, if_any_state: { gate: :open, alarm: :on },
                   unless_all_states: { gate: :closed, alarm: :off }
      end
    end
  end

  class Alone
    state_machine initial: :alone
  end

  class Empty
    state_machine initial: :"" do
      event :go do
        transition '': :done
      end
    end
  end

  # core 0.302.0 finds nil and :"" as one state; later cores keep them apart
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
    assert_equal(['go'], builder.transition_metadata.map { it[:label] })
    assert_equal ['go'], diagram.transitions.map(&:label)
  end

  def test_an_empty_state_name_is_escaped
    builder = StateMachines::Diagram::Builder.new(Empty.state_machines[:state])
    diagram = builder.build

    assert_equal %w[% done], diagram.states.map(&:id)
    assert_equal '', builder.state_metadata.fetch('%')[:name]
    assert_equal([%w[% done]], diagram.transitions.map { [it.source_state_id, it.target_state_id] })
  end

  def test_each_state_the_core_has_is_drawn_once
    machine = NilAndEmpty.state_machines[:state]
    diagram = StateMachines::Diagram::Builder.new(machine).build
    id = ->(name) { StateMachines::Diagram::Builder.state_id(name) }

    assert_equal machine.states.map { id[it.name] }.sort, diagram.states.map(&:id).sort
    # The target is whichever state the core finds under :""
    assert_equal([['idle', id[machine.states[:""].name]]],
                 diagram.transitions.map { [it.source_state_id, it.target_state_id] })
    # A core that keeps nil and :"" apart has both, drawn as two
    assert_equal %w[% idle nil_state], diagram.states.map(&:id).sort if machine.states.map(&:name).include?(:"")
  end

  def test_blank_names_stay_in_the_metadata_not_the_diagram
    builder = StateMachines::Diagram::Builder.new(Oddity.state_machines[:state])
    diagram = builder.build

    assert_nil diagram.states.find { |state| state.id == '%20' }.label
    assert_equal ' ', builder.state_metadata.fetch('%20')[:label]
    assert_equal([' ', ''], builder.transition_metadata.filter_map { |data| data[:label] if data[:label].strip.empty? })
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

    assert builder.state_metadata.fetch('alone')[:initial]
    assert builder.state_metadata.fetch('alone')[:final]
  end

  class Vault
    attr_accessor :state

    state_machine :state, initial: :locked do
      before_transition from: :locked, do: :warm_up
      before_transition on: :open, do: :log_open
      around_transition to: :opened, do: :wrap
      after_transition to: :opened, do: :announce
      before_transition if: :audited?, do: :audit

      event :open do
        transition locked: :opened, if: %i[key_turned code_entered], unless: %i[alarm jammed]
      end

      event :close do
        transition opened: :locked, if: 'shut? || slammed?', unless: '!latched?'
      end
    end
  end

  def test_an_array_condition_is_each_of_its_conditions
    builder = StateMachines::Diagram::Builder.new(Vault.state_machines[:state])
    transition = builder.build.transitions.first

    assert_equal 'key_turned && code_entered && !alarm && !jammed', transition.guard
    assert_equal({ if: %w[key_turned code_entered], unless: %w[alarm jammed] },
                 builder.transition_metadata.first[:conditions])
  end

  def test_a_condition_names_the_method_the_core_calls
    builder = StateMachines::Diagram::Builder.new(Vault.state_machines[:state])

    refute_includes builder.build.transitions.first.guard, '?'
  end

  def test_code_conditions_stay_one_term_of_the_guard
    transition = StateMachines::Diagram::Builder.new(Vault.state_machines[:state]).build.transitions.last

    assert_equal '(shut? || slammed?) && !(!latched?)', transition.guard
  end

  def test_callbacks_are_those_the_core_runs_on_each_transition
    builder = StateMachines::Diagram::Builder.new(Vault.state_machines[:state])
    diagram = builder.build

    open, close = builder.transition_metadata.map { it[:callbacks] }

    assert_equal({ before: ['warm_up', 'log_open', 'audit (if audited?)'], around: %w[wrap], after: %w[announce] },
                 open)
    assert_equal({ before: ['audit (if audited?)'], around: [], after: [] }, close)
    assert_equal 'warm_up, log_open, audit (if audited?), wrap, announce', diagram.transitions.first.action
  end

  def test_callbacks_follow_the_source_of_each_pair_of_a_branch
    klass = Class.new do
      attr_accessor :state

      state_machine :state, initial: :a do
        state :b
        before_transition from: :a, do: :only_from_a

        event :go do
          transition %i[a b] => :c
        end
      end
    end

    builder = StateMachines::Diagram::Builder.new(klass.state_machines[:state])
    builder.build

    assert_equal([%w[only_from_a], []], builder.transition_metadata.map { it[:callbacks][:before] })
  end

  def test_a_symbol_to_proc_callback_shows_its_symbol
    builder = StateMachines::Diagram::Builder.new(Regiment.state_machines[:formation])
    diagram = builder.build

    assert_includes diagram.transitions.map(&:action), '&:prepare_pikes'
  end

  def test_partial_builds_hold_only_their_part
    machine = Vault.state_machines[:state]
    event = machine.events[:close]

    builder = StateMachines::Diagram::Builder.new(machine)
    diagram = builder.build_branch(event.branches.first, event)

    assert_equal 'Event: close, branch 1', builder.scope
    assert_equal([%w[opened locked]], diagram.transitions.map { [it.source_state_id, it.target_state_id] })
    assert_equal %w[locked opened], diagram.states.map(&:id)
    assert_equal 1, builder.transition_metadata.size
  end

  class Shadowed
    attr_accessor :state

    state_machine :state, initial: :a do
      state :b, :c, :d

      event :go do
        transition a: :b
        transition %i[a b] => :c
        transition :c => :d, [:c] => :a
      end
    end
  end

  def test_draws_only_what_the_core_performs_from_each_source
    assert_equal performed_pairs(Shadowed), drawn_pairs(Shadowed)
    assert_equal [%w[a b], %w[b c], %w[c d]], drawn_pairs(Shadowed)
  end

  def built(&)
    klass = Class.new do
      attr_accessor :state

      def ok? = true
      class_eval(&)
    end
    StateMachines::Diagram::Builder.new(klass.state_machines[:state]).tap(&:build)
  end

  def test_nil_false_and_empty_conditions_are_no_condition_as_in_the_core
    builder = built do
      state_machine :state, initial: :idle do
        event(:go) do
          transition idle: :a, if: false, unless: nil
          transition idle: :b, if: []
        end
      end
    end

    drawn = builder.diagram.transitions.map { [it.source_state_id, it.target_state_id, it.guard] }

    assert_equal [['idle', 'a', nil]], drawn
  end

  def test_a_condition_the_core_cannot_evaluate_is_refused
    [true, [:ok?, 1]].each do |condition|
      assert_raises(ArgumentError) do
        built { state_machine(:state, initial: :idle) { event(:go) { transition idle: :a, if: condition } } }
      end
    end
  end

  class Constants
    attr_accessor :state

    def ok? = true
    def always_runs = nil
    def never_runs = raise('the core never runs this callback')

    state_machine :state, initial: :idle do
      before_transition if: '', do: :never_runs
      after_transition unless: '   ', do: :always_runs

      event(:go) do
        transition idle: :a, if: ''
        transition idle: :b, if: ['true', :ok?]
        transition idle: :c, if: 'false'
        transition idle: :d, unless: '# nothing'
      end
    end
  end

  def test_string_conditions_the_core_always_reads_the_same_are_resolved
    drawn = StateMachines::Diagram::Builder.new(Constants.state_machines[:state]).tap(&:build)
                                           .transition_metadata.map do |data|
      [data[:to], data[:conditions], data[:callbacks][:before], data[:callbacks][:after]]
    end

    assert_equal [['b', { if: ['ok?'], unless: [] }, [], ['always_runs']],
                  ['d', { if: [], unless: [] }, [], ['always_runs']]], drawn
  end

  def test_the_core_skips_a_branch_whose_code_condition_never_passes
    object = Constants.new
    object.go

    assert_equal 'b', object.state
  end

  def test_code_that_does_not_parse_is_refused_as_in_the_core
    assert_raises(ArgumentError) do
      built { state_machine(:state, initial: :idle) { event(:go) { transition idle: :a, if: '1 +' } } }
    end
  end

  def test_a_callback_shows_the_conditions_it_runs_under
    builder = built do
      state_machine :state, initial: :idle do
        before_transition on: :go, if: :enabled?, unless: %i[muted], do: :audit
        after_transition on: :go, if: false, do: :log
        event(:go) { transition idle: :a }
      end
    end

    assert_equal({ before: ['audit (if enabled? && unless muted)'], around: [], after: ['log'] },
                 builder.transition_metadata.first[:callbacks])
  end

  def test_an_anonymous_owner_leaves_no_blank_in_the_title
    klass = Class.new do
      attr_accessor :state

      state_machine initial: :idle
    end

    assert_equal 'state State Machine', StateMachines::Diagram::Builder.new(klass.state_machines[:state]).build.title
  end

  private

  def drawn_pairs(klass)
    StateMachines::Diagram::Builder.new(klass.state_machines[:state]).build.transitions.map do |transition|
      [transition.source_state_id, transition.target_state_id]
    end.uniq.sort
  end
end
