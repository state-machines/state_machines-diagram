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
          events: build_events
        }.compact
      end

      def to_json(*)
        build.to_json(*)
      end

      private

      def machine_name
        "#{machine.owner_class.name}##{machine.name}"
      end

      # A dynamic initial state depends on the object, and no state is
      # marked initial; the schema needs one, so the first state stands in
      def initial_state
        states = Introspection.states_of(machine)
        state = states.find(&:initial?) || states.first
        Labels.state_text(state.name) if state
      end

      def state_names
        Introspection.states_of(machine).map { Labels.state_text(it.name) }
      end

      # The core has no event-level guards: every guard belongs to one branch
      def build_events
        machine.events.map do |event|
          { name: event.name.to_s, transitions: event.branches.flat_map { build_branch_transitions(it) } }
        end
      end

      # One transition per target of the branch, with the sources that reach
      # it. A branch's guards all must hold: its if: conditions and state
      # guards go in guards, its unless: conditions in unless.
      def build_branch_transitions(branch)
        conditions = Introspection.guard_conditions(branch)
        guards = conditions[:if] + conditions.except(:if, :unless).map do |kind, value|
          Labels.state_guard_token(kind, value)
        end

        Introspection.transition_pairs(machine, branch).group_by(&:last).map do |target, pairs|
          {
            sources: pairs.map { |from, _to| Labels.state_text(from) },
            target: Labels.state_text(target),
            guards: guards,
            unless: conditions[:unless]
          }.reject { |_key, value| value.empty? }
        end
      end
    end
  end
end
