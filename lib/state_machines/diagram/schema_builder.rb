# frozen_string_literal: true

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
          superstates: build_superstates,
          events: build_events,
          async_mode: false
        }.compact
      end

      def to_json(*args)
        build.to_json(*args)
      end

      private

      def machine_name
        "#{machine.owner_class.name}##{machine.name}"
      end

      def initial_state
        state = machine.initial_state(machine.owner_class)
        if state.respond_to?(:name)
          state.name&.to_s
        else
          state&.to_s
        end || machine.states.first&.name&.to_s
      end

      def state_names
        machine.states.by_priority.map { |s| s.name&.to_s || 'nil' }
      end

      def build_superstates
        # state_machines gem doesn't have native superstate support
        # Return empty array for compatibility
        []
      end

      def build_events
        machine.events.map do |event|
          {
            name: event.name.to_s,
            transitions: build_event_transitions(event),
            guards: extract_event_guards(event),
            payload: nil
          }.tap do |h|
            h.delete(:guards) if h[:guards].empty?
            h.delete(:payload) if h[:payload].nil?
          end
        end
      end

      def build_event_transitions(event)
        transitions = []

        event.branches.each do |branch|
          branch.state_requirements.each do |requirement|
            valid_states = machine.states.by_priority.map(&:name)
            from_states = requirement[:from].filter(valid_states)
            to_states = requirement[:to].values

            # Handle loopback transitions (empty to_states means same state)
            to_states = from_states if to_states.empty?

            to_states.each do |to_state|
              transitions << {
                sources: from_states.map { |s| s&.to_s || 'nil' },
                target: to_state&.to_s || 'nil',
                guards: extract_branch_guards(branch),
                unless: extract_branch_unless(branch)
              }.tap do |h|
                h.delete(:guards) if h[:guards].empty?
                h.delete(:unless) if h[:unless].empty?
              end
            end
          end
        end

        # Merge transitions with same target
        merge_transitions(transitions)
      end

      def merge_transitions(transitions)
        # Group by target and merge sources
        grouped = transitions.group_by { |t| [t[:target], t[:guards], t[:unless]] }

        grouped.map do |(_target, _guards, _unless), group|
          sources = group.flat_map { |t| t[:sources] }.uniq
          base = group.first.dup
          base[:sources] = sources
          base
        end
      end

      def extract_event_guards(event)
        guards = []
        event.branches.each do |branch|
          guards.concat(extract_branch_guards(branch))
        end
        guards.uniq
      end

      def extract_branch_guards(branch)
        guards = []
        if branch.if_condition
          guards << normalize_condition(branch.if_condition)
        end
        guards.compact
      end

      def extract_branch_unless(branch)
        guards = []
        if branch.unless_condition
          guards << normalize_condition(branch.unless_condition)
        end
        guards.compact
      end

      def normalize_condition(condition)
        case condition
        when Symbol
          name = condition.to_s
          name += '?' unless name.end_with?('?')
          name
        when Proc, Method
          if condition.respond_to?(:source_location) && condition.source_location
            file, line = condition.source_location
            "lambda@#{File.basename(file)}:#{line}"
          else
            'lambda'
          end
        else
          condition.to_s
        end
      end
    end
  end
end
