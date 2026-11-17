# frozen_string_literal: true

require 'diagram'

module StateMachines
  module Diagram
    class Builder
      # The diagram id of the nil state
      NIL_STATE_ID = 'nil_state'
      # The form of an escaped id: '%' and the name's bytes in hex
      ESCAPED_ID = /\A%(?:\h\h)*\z/

      attr_reader :machine, :options, :diagram, :state_metadata, :transition_metadata

      # The diagram id of the state named +name+. A diagram refuses blank ids
      # and its terminal pseudo-state '*', which are legal state names, so
      # those, 'nil_state' (the nil state's id) and names already of the
      # escaped form are escaped: distinct names always get distinct ids. The
      # name itself stays in the state's metadata.
      def self.state_id(name)
        return NIL_STATE_ID if name.nil?

        value = name.to_s
        return value unless value == ::Diagrams::StateDiagram::TERMINAL || value.strip.empty? ||
                            value == NIL_STATE_ID || value.match?(ESCAPED_ID)

        "%#{value.unpack1('H*')}"
      end

      # A state name as text, as the core shows it (State#description): the
      # nil state reads "nil"
      def self.state_text(name)
        name.nil? ? 'nil' : name.to_s
      end

      # One state guard as text, its requirements kept together under the
      # guard's own kind: "if_any_state (gate=open, alarm=on)"
      def self.state_guard_token(kind, requirements)
        pairs = requirements.map { |machine_name, state| "#{machine_name}=#{state}" }
        pairs.one? ? "#{kind} #{pairs.first}" : "#{kind} (#{pairs.join(', ')})"
      end

      # The (source, target) pairs a branch draws, resolved as the core resolves them
      def self.transition_pairs(machine, branch)
        state_names = machine.states.map(&:name)
        source_names = states_of(machine).map(&:name)

        branch.state_requirements.flat_map do |requirement|
          requirement[:from].filter(source_names).map do |from|
            [from, to_state_for(requirement, from, state_names)]
          end
        end
      end

      # The machine's states by priority, each once: the core looks names up
      # by their String form, so nil and :"" find the same state and
      # StateCollection#by_priority can list it twice
      def self.states_of(machine)
        machine.states.by_priority.uniq
      end

      def self.to_state_for(requirement, from, state_names)
        return from if requirement[:to].is_a?(LoopbackMatcher)

        requirement[:to].filter([from] | state_names).first
      end

      # Human-readable label for a Proc/Method, pointing at its source location
      def self.callable_label(callable)
        if callable.respond_to?(:source_location) && callable.source_location
          file, line = callable.source_location
          filename = File.basename(file) if file
          "lambda@#{filename}:#{line}"
        else
          'lambda'
        end
      end

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
        self.class.states_of(machine).each do |state|
          add_state_node(state)
        end
      end

      # A diagram holds no blank text; the metadata keeps it as it is
      def diagram_text(value)
        value unless value.nil? || value.strip.empty?
      end

      def add_state_node(state)
        id = self.class.state_id(state.name)
        label = state_label(state)
        diagram.add_state(id: id, label: diagram_text(label))

        @state_metadata[id] = {
          name: state.name&.to_s,
          label: label,
          initial: state.initial?,
          final: state.final?,
          metadata: build_state_metadata(state)
        }
      end

      # A human name callback may return nil: the state then shows its name
      def state_label(state)
        name = self.class.state_text(state.name)
        return name unless options[:human_names]

        human_name = state.human_name(machine.owner_class)
        human_name.nil? ? name : human_name.to_s
      end

      def build_state_metadata(state)
        {
          initial: state.initial?,
          final: state.final?,
          value: state.value
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
        self.class.transition_pairs(machine, branch).each do |from, to|
          add_transition(from, to, event, branch)
        end
      end

      def add_transition(from, to, event, branch)
        guard_info = extract_guard_conditions(branch)
        label = transition_label(event)

        transition = diagram.add_transition(
          source_state_id: self.class.state_id(from),
          target_state_id: self.class.state_id(to),
          label: diagram_text(label),
          guard: diagram_text(guard_info[:display]),
          action: diagram_text(extract_action_info(branch, event))
        )

        transition_data = {
          transition: transition,
          label: label,
          from: from.to_s,
          to: to.to_s,
          event: event.name.to_s,
          conditions: guard_info[:conditions],
          callbacks: build_callbacks(branch, event),
          metadata: build_transition_metadata(event, branch)
        }
        @transition_metadata << transition_data
      end

      # A human name callback may return nil: the transition then shows the
      # event's name, which still says which event fires
      def transition_label(event)
        name = event.name.to_s
        return name unless options[:human_names]

        human_name = event.human_name(machine.owner_class)
        human_name.nil? ? name : human_name.to_s
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

        # Each state guard stays one group: its kind says how its requirements
        # combine (if_any_state is an OR, unless_all_states a NOT ALL)
        branch.state_guards.each do |kind, requirements|
          guard_conditions[kind] = requirements.to_a
          condition_tokens << self.class.state_guard_token(kind, requirements)
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
          self.class.callable_label(condition)
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
          self.class.callable_label(action)
        else
          action.to_s
        end
      end
    end
  end
end
