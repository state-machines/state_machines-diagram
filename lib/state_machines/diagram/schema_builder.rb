# frozen_string_literal: true

require 'json'
require_relative 'introspection'

module StateMachines
  module Diagram
    # Builds a MachineSchema-compatible hash from a state_machines machine.
    # This format is compatible with the state-machines-rs CLI tool.
    class SchemaBuilder
      attr_reader :machine, :options

      def initialize(machine, options = {})
        @machine = machine
        @options = options
      end

      def build
        {
          name: machine_name,
          initial: initial_state,
          states: state_names,
          final_states: final_state_names,
          events: build_events
        }.reject { |_key, value| value.respond_to?(:empty?) && value.empty? }
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

        Labels.state_text(state.name)
      end

      def state_names
        Introspection.states_of(machine).map { Labels.state_text(it.name) }
      end

      # The states the core calls final (State#final?): no transition leaves them
      def final_state_names
        Introspection.states_of(machine).select(&:final?).map { Labels.state_text(it.name) }
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
          [from, to, Introspection.callback_labels(machine, from, to, event.name)]
        end
        pairs.group_by { |_from, to, callbacks| [to, callbacks] }.map do |(target, callbacks), group|
          {
            sources: group.map { |from, _to, _callbacks| Labels.state_text(from) },
            target: Labels.state_text(target),
            guards: guards,
            unless: conditions[:unless],
            **callbacks
          }.reject { |_key, value| value.empty? }
        end
      end
    end
  end
end
