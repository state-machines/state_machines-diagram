# frozen_string_literal: true

require_relative 'labels'

module StateMachines
  module Diagram
    # Reads a machine as the core resolves it: its states, the transitions
    # each branch performs, their guards and the callbacks that run on them.
    module Introspection
      # Callback kinds in the order they run around a transition
      CALLBACK_TYPES = %i[before around after].freeze

      module_function

      # The machine's states by priority, each once: the core looks names up
      # by their String form, so nil and :"" find the same state and
      # StateCollection#by_priority can list it twice
      def states_of(machine)
        machine.states.by_priority.uniq
      end

      # The (source, target) pairs a branch performs
      def transition_pairs(machine, branch)
        state_names = machine.states.map(&:name)
        source_names = states_of(machine).map(&:name)

        branch.state_requirements.flat_map do |requirement|
          requirement[:from].filter(source_names).map do |from|
            [from, to_state_for(requirement, from, state_names)]
          end
        end
      end

      def to_state_for(requirement, from, state_names)
        return from if requirement[:to].is_a?(LoopbackMatcher)

        requirement[:to].filter([from] | state_names).first
      end

      # A branch's guards: the if: and unless: tokens, then each state guard
      # under its kind with its requirements, in the core's order.
      def guard_conditions(branch)
        {
          if: Labels.condition_tokens(branch.if_condition),
          unless: Labels.condition_tokens(branch.unless_condition),
          **branch.state_guards.transform_values(&:to_h)
        }
      end

      # The callbacks the core runs on +event_name+ from +from+ to +to+, by
      # kind, as labels. The core files around callbacks with the before
      # ones. Callback conditions depend on the object, so a conditional
      # callback is listed as one that may run.
      def callback_labels(machine, from, to, event_name)
        query = { from: from, to: to, on: event_name, guard: false }
        CALLBACK_TYPES.to_h do |type|
          callbacks = machine.callbacks[type == :after ? :after : :before].select do |callback|
            callback.type == type && callback.branch.matches?(nil, query)
          end
          [type, callbacks.flat_map { it.instance_variable_get(:@methods) }.map { Labels.action_label(it) }]
        end
      end
    end
  end
end
