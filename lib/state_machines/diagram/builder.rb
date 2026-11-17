# frozen_string_literal: true

require 'diagram'
require_relative 'introspection'

module StateMachines
  module Diagram
    # Builds a Diagrams::StateDiagram from a machine: the whole machine
    # (#build), or the part one state, event or branch draws. The diagram
    # holds ids, labels and one-line guard/action text; the builder keeps
    # what it cannot hold in #state_metadata and #transition_metadata.
    class Builder
      include Introspection

      # The diagram id of the nil state
      NIL_STATE_ID = 'nil_state'
      # The form of an escaped id: '%' and the name's bytes in hex
      ESCAPED_ID = /\A%(?:\h\h)*\z/

      attr_reader :machine, :options, :diagram, :scope, :state_metadata, :transition_metadata

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

      def initialize(machine, options = {})
        @machine = machine
        @options = options
      end

      # The whole machine
      def build
        fill(nil, states_of(machine), each_transition)
      end

      # The state, the transitions into or out of it, and the states at their
      # other end
      def build_state(state)
        transitions = each_transition.select { |from, to, _event, _branch| [from, to].include?(state.name) }
        fill("State: #{Labels.state_text(state.name)}", states_in(transitions, [state]), transitions)
      end

      # The transitions the event performs and the states they connect
      def build_event(event)
        transitions = each_transition.select { |_from, _to, other, _branch| other.equal?(event) }
        fill("Event: #{event.name}", states_in(transitions), transitions)
      end

      # The transitions one branch of +event+ performs and the states they connect
      def build_branch(branch, event)
        transitions = each_transition.select { |_from, _to, _event, other| other.equal?(branch) }
        position = event.branches.index(branch)
        fill("Event: #{event.name}, branch #{position + 1}", states_in(transitions), transitions)
      end

      private

      # Every (source, target, event, branch) the machine draws
      def each_transition
        machine.events.flat_map do |event|
          event_transitions(machine, event).map { |from, to, branch| [from, to, event, branch] }
        end
      end

      # The machine's states the transitions connect, and +focus+
      def states_in(transitions, focus = [])
        names = transitions.flat_map { |from, to, _event, _branch| [from, to] }
        states_of(machine).select { |state| focus.include?(state) || names.include?(state.name) }
      end

      def fill(scope, states, transitions)
        @scope = scope
        @diagram = ::Diagrams::StateDiagram.new(title: diagram_title)
        @state_metadata = {}
        @transition_metadata = []
        states.each { add_state(it) }
        transitions.each { |from, to, event, branch| add_transition(from, to, event, branch) }
        diagram
      end

      def diagram_title
        [machine.owner_class.name, machine.name, 'State Machine'].compact.join(' ')
      end

      # A diagram holds no blank text; the metadata keeps it as it is
      def diagram_text(value)
        value unless value.nil? || value.strip.empty?
      end

      def add_state(state)
        id = self.class.state_id(state.name)
        label = label_of(state, Labels.state_text(state.name))
        diagram.add_state(id: id, label: diagram_text(label))

        @state_metadata[id] = {
          name: state.name&.to_s,
          label: label,
          initial: state.initial?,
          final: state.final?
        }
      end

      def add_transition(from, to, event, branch)
        conditions = guard_conditions(branch)
        sequence = callback_sequence(machine, from, to, event.name)
        label = label_of(event, event.name.to_s)

        transition = diagram.add_transition(
          source_state_id: self.class.state_id(from),
          target_state_id: self.class.state_id(to),
          label: diagram_text(label),
          guard: diagram_text(Labels.guard_expression(conditions)),
          action: diagram_text(Labels.action_list(sequence))
        )

        @transition_metadata << {
          transition: transition,
          label: label,
          from: from&.to_s,
          to: to&.to_s,
          event: event.name.to_s,
          conditions: conditions,
          callbacks: labels_by_kind(callbacks_by_kind(sequence)),
          callback_sequence: sequence.map { it.slice(:kind, :phase).merge(text: Labels.callback_text(it)) }
        }
      end

      # A state's or event's name, or with human_names: its human name. A
      # human name callback may return nil: the name then shows, which still
      # says which state or event it is.
      def label_of(node, name)
        human_name = node.human_name(machine.owner_class) if options[:human_names]
        human_name.nil? ? name : human_name.to_s
      end
    end
  end
end
