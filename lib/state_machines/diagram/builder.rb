# frozen_string_literal: true

require 'diagram'

module StateMachines
  module Diagram
    class Builder
      attr_reader :machine, :options, :diagram, :state_metadata, :transition_metadata

      def initialize(machine, options = {})
        @machine = machine
        @options = options
        @diagram = create_diagram
        @state_metadata = {}
        @transition_metadata = []
      end

      def build
        add_states
        add_transitions
        diagram
      end

      private

      def create_diagram
        ::Diagrams::StateDiagram.new(
          title: diagram_title
        )
      end

      def diagram_id
        "#{machine.owner_class.name}_#{machine.name}"
      end

      def diagram_title
        "#{machine.owner_class.name} #{machine.name} State Machine"
      end

      def diagram_description
        "State machine for #{machine.owner_class.name}##{machine.name}"
      end

      def add_states
        machine.states.by_priority.each do |state|
          add_state_node(state)
        end
      end

      def add_state_node(state)
        state_node = ::Diagrams::Elements::State.new(
          id: state_id(state),
          label: state_label(state)
        )

        diagram.add_state(state_node)

        # Store metadata separately for now
        @state_metadata ||= {}
        @state_metadata[state_id(state)] = {
          type: state_type(state),
          metadata: build_state_metadata(state)
        }
      end

      def state_id(state)
        state.name ? state.name.to_s : 'nil_state'
      end

      def state_label(state)
        if options[:human_names]
          state.human_name(machine.owner_class)
        else
          state_id(state)
        end
      end

      def state_type(state)
        if state.initial?
          'initial'
        elsif state.final?
          'final'
        else
          'normal'
        end
      end

      def build_state_metadata(state)
        {
          initial: state.initial?,
          final: state.final?,
          value: state.value,
          methods: state.methods.grep(/^#{state.name}_/).map(&:to_s)
        }
      end

      def add_transitions
        machine.events.each do |event|
          add_event_transitions(event)
        end
      end

      def add_event_transitions(event)
        event.branches.each do |branch|
          add_branch_transitions(branch, event)
        end
      end

      def add_branch_transitions(branch, event)
        valid_states = machine.states.by_priority.map(&:name)

        branch.state_requirements.each do |requirement|
          from_states = requirement[:from].filter(valid_states)
          to_states = determine_to_states(requirement, from_states)

          create_transitions(from_states, to_states, event, branch)
        end
      end

      def determine_to_states(requirement, from_states)
        if requirement[:to].values.empty?
          # Loopback transitions
          from_states
        else
          [requirement[:to].values.first]
        end
      end

      def create_transitions(from_states, to_states, event, branch)
        from_states.each do |from|
          to_states.each do |to|
            add_transition(from, to, event, branch)
          end
        end
      end

      def add_transition(from, to, event, branch)
        from_id = from ? from.to_s : 'nil_state'
        to_id = to ? to.to_s : 'nil_state'

        guard_info = extract_guard_conditions(branch)

        transition = ::Diagrams::Elements::Transition.new(
          source_state_id: from_id.empty? ? 'nil_state' : from_id,
          target_state_id: to_id.empty? ? 'nil_state' : to_id,
          label: transition_label(event),
          guard: guard_info[:display],
          action: extract_action_info(branch, event)
        )

        diagram.add_transition(transition)

        # Store additional metadata separately for advanced analysis
        @transition_metadata ||= []
        transition_data = {
          transition: transition,
          from: from.to_s,
          to: to.to_s,
          event: event.name.to_s,
          conditions: guard_info[:conditions],
          callbacks: build_callbacks(branch, event),
          metadata: build_transition_metadata(event, branch)
        }
        @transition_metadata << transition_data
      end

      def transition_label(event)
        if options[:human_names]
          event.human_name(machine.owner_class)
        else
          event.name.to_s
        end
      end

      def build_callbacks(branch, event)
        {
          before: callback_method_names(branch, event, :before),
          after: callback_method_names(branch, event, :after),
          around: callback_method_names(branch, event, :around)
        }
      end

      def callback_method_names(branch, event, type)
        machine.callbacks[type == :around ? :before : type].select do |callback|
          callback.branch.matches?(branch,
                                   from: branch.state_requirements.map { |req| req[:from] },
                                   to: branch.state_requirements.map { |req| req[:to] },
                                   on: event.name)
        end.flat_map do |callback|
          callback.instance_variable_get('@methods')
        end.compact
      end

      def build_transition_metadata(_event, branch)
        {
          requirements: branch.state_requirements.size
        }
      end

      def extract_guard_conditions(branch)
        guard_conditions = {
          if: [],
          unless: []
        }
        condition_tokens = []

        if branch.if_condition
          token = guard_condition_token(branch.if_condition)
          guard_conditions[:if] << token if token
          condition_tokens << token if token
        end

        if branch.unless_condition
          token = guard_condition_token(branch.unless_condition)
          guard_conditions[:unless] << token if token
          condition_tokens << "!#{token}" if token
        end

        {
          display: condition_tokens.empty? ? nil : condition_tokens.join(' && '),
          conditions: guard_conditions
        }
      end

      def guard_condition_token(condition)
        return if condition.nil?

        case condition
        when Symbol
          method_name = condition.to_s
          method_name += '?' unless method_name.end_with?('?')
          method_name
        when Proc, Method
          if condition.respond_to?(:source_location) && condition.source_location
            file, line = condition.source_location
            filename = File.basename(file) if file
            "lambda@#{filename}:#{line}"
          else
            'lambda'
          end
        else
          condition.to_s
        end
      end

      def extract_action_info(branch, event)
        actions = []

        # Add explicit action if available (store the object, format during rendering)
        actions << event.action if event.respond_to?(:action) && event.action

        # Add callback methods as actions
        before_callbacks = callback_method_names(branch, event, :before)
        after_callbacks = callback_method_names(branch, event, :after)

        actions.concat(before_callbacks) if before_callbacks.any?
        actions.concat(after_callbacks) if after_callbacks.any?

        return nil if actions.empty?

        # Format all actions appropriately
        formatted_actions = actions.map { |action| format_action(action) }
        formatted_actions.join(', ')
      end

      def format_action(action)
        case action
        when Proc, Method
          # Try to extract source location for better readability
          if action.respond_to?(:source_location) && action.source_location
            file, line = action.source_location
            filename = File.basename(file) if file
            "lambda@#{filename}:#{line}"
          else
            'lambda'
          end
        when Symbol
          action.to_s
        else
          action.to_s
        end
      end
    end
  end
end
