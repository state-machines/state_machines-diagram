# frozen_string_literal: true

require 'json'
require_relative 'builder'

module StateMachines
  module Diagram
    # Builds a MachineSchema-compatible hash from a state_machines machine.
    # This format is compatible with the state-machines-rs CLI tool. States
    # are named by their diagram id (Builder.state_id), which is distinct for
    # distinct states: the nil state is "nil_state", a state named :nil "nil".
    class SchemaBuilder
      attr_reader :machine, :options

      def initialize(machine, options = {})
        @machine = machine
        @options = options
      end

      # name, initial, states and events are required, even when empty;
      # final_states is optional
      def build
        events = build_events
        finals = final_state_names(events)
        { name: machine_name, initial: initial_state, states: state_names, events: events }
          .then { finals.empty? ? it : it.merge(final_states: finals) }
      end

      def to_json(*)
        build.to_json(*)
      end

      private

      def machine_name
        "#{machine.owner_class.name}##{machine.name}"
      end

      # MachineSchema needs one initial state. A dynamic one depends on the
      # object, so no state is marked initial and none can stand in for it.
      def initial_state
        state = Introspection.states_of(machine).find(&:initial?)
        raise ArgumentError, "MachineSchema needs a static initial state; #{machine_name} has none" unless state

        schema_id(state.name)
      end

      def state_names
        Introspection.states_of(machine).map { schema_id(it.name) }
      end

      def schema_id(name) = Builder.state_id(name)

      # The states the core calls final (State#final?) that no transition
      # leaves. The core still calls a state final when its only transitions
      # are loopbacks; MachineSchema refuses any outgoing transition from a
      # final state, and a loopback still fires its event and callbacks, so
      # such a state is not final there.
      def final_state_names(events)
        sources = events.flat_map { |event| event[:transitions].flat_map { it[:sources] } }
        Introspection.states_of(machine).select(&:final?).map { schema_id(it.name) } - sources
      end

      # The core has no event-level guards: every guard belongs to one branch.
      # An event without transitions can never fire, and MachineSchema refuses
      # one, so it is left out.
      def build_events
        machine.events.filter_map do |event|
          transitions = candidates(event)
          next if transitions.empty?

          { name: event.name.to_s, branching: branching?(transitions), transitions: transitions }
            .then { |schema| schema[:branching] ? mark_fallbacks(schema) : schema.except(:branching) }
        end
      end

      # The core tries an event's branches in order and takes the first whose
      # source and guards match (Introspection.event_transitions leaves out
      # what an earlier unguarded branch takes): one candidate per branch,
      # target and callbacks, with the sources that reach it.
      def candidates(event)
        Introspection.event_transitions(machine, event).chunk_while { |one, other| one.last.equal?(other.last) }
                     .flat_map { |group| branch_transitions(event, group.first.last, group) }
      end

      # Several candidates from one source are MachineSchema's ordered
      # branching, which is how the core picks between them
      def branching?(transitions)
        sources = transitions.flat_map { it[:sources] }
        sources.uniq.size < sources.size
      end

      # In branching, a candidate without guards is the fallback; candidates()
      # already put it last for each of its sources
      def mark_fallbacks(event)
        event.merge(transitions: event[:transitions].map { guarded?(it) ? it : it.merge(fallback: true) })
      end

      def guarded?(transition)
        transition.nil? || transition.key?(:guards) || transition.key?(:unless)
      end

      # A branch's guards all must hold: its if: conditions and state guards
      # go in guards, its unless: conditions in unless. The callbacks are
      # those the core runs on that transition.
      def branch_transitions(event, branch, performed)
        conditions = Introspection.guard_conditions(branch)
        guards = conditions[:if] + conditions.except(:if, :unless).map do |kind, value|
          Labels.state_guard_token(kind, value)
        end

        pairs = performed.map do |from, to, _branch|
          [from, to, callback_names(from, to, event)]
        end
        pairs.group_by { |_from, to, callbacks| [to, callbacks] }.map do |(target, callbacks), group|
          {
            sources: group.map { |from, _to, _callbacks| schema_id(from) },
            target: schema_id(target),
            guards: guards,
            unless: conditions[:unless],
            **callbacks
          }.reject { |_key, value| value.empty? }
        end
      end

      # MachineSchema callbacks are names of functions that run whenever the
      # transition does; it has no place for a callback's own conditions. An
      # unconditional name would claim the callback always runs, a marker in
      # the name would name no function, so a conditional callback is refused.
      def callback_names(from, to, event)
        Introspection.callbacks(machine, from, to, event.name).transform_values do |list|
          list.map do |callback|
            if Introspection.conditional?(callback[:conditions])
              raise ArgumentError, 'MachineSchema cannot express the conditional callback ' \
                                   "#{Labels.callback_text(callback)} on #{event.name}"
            end

            callback[:label]
          end
        end
      end
    end
  end
end
