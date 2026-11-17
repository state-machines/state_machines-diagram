# frozen_string_literal: true

require 'prism'
require_relative 'labels'

module StateMachines
  module Diagram
    # Reads a machine as the core resolves it: its states, the transitions
    # each branch performs, their guards and the callbacks that run on them.
    module Introspection
      # Callback kinds in the order they run around a transition
      CALLBACK_TYPES = %i[before around after].freeze
      # The core checks a String condition with EvalHelpers#validate_eval_string,
      # which is private: it is called on an object extended with EvalHelpers
      # alone, not on any machine part, until the core exposes it.
      CORE_EVAL = Object.new.extend(EvalHelpers)

      module_function

      # The machine's states by priority, each once: the core looks names up
      # by their String form, so nil and :"" find the same state and
      # StateCollection#by_priority can list it twice
      def states_of(machine)
        machine.states.by_priority.uniq
      end

      # The (source, target) pairs a branch performs. From one source the
      # core takes the first requirement that matches, so a later one from
      # the same source is never performed.
      def transition_pairs(machine, branch)
        state_names = machine.states.map(&:name)
        source_names = states_of(machine).map(&:name)

        branch.state_requirements.flat_map do |requirement|
          requirement[:from].filter(source_names).map do |from|
            [from, to_state_for(requirement, from, state_names)]
          end
        end.uniq(&:first)
      end

      # The (source, target, branch) transitions an event performs, in order.
      # The core takes the first branch whose source and guards match, so a
      # source an unguarded branch takes never reaches a later branch, and a
      # branch whose conditions never pass (#never?) performs nothing.
      def event_transitions(machine, event)
        settled = []
        event.branches.reject { never?(it) }.flat_map do |branch|
          pairs = transition_pairs(machine, branch).reject { settled.include?(it.first) }
          settled |= pairs.map(&:first) unless guarded?(branch)
          pairs.map { |from, to| [from, to, branch] }
        end
      end

      def guarded?(branch)
        conditional?(guard_conditions(branch))
      end

      def to_state_for(requirement, from, state_names)
        return from if requirement[:to].is_a?(LoopbackMatcher)

        requirement[:to].filter([from] | state_names).first
      end

      # A branch's guards: the if: and unless: tokens, then each state guard
      # under its kind with its requirements, in the core's order.
      # A condition that always passes is no condition, so it is left out
      # (a String the core always evaluates the same way, see #constant).
      def guard_conditions(branch)
        {
          if: Labels.condition_tokens(conditions_of(branch.if_condition).reject { constant(it) == true }),
          unless: Labels.condition_tokens(conditions_of(branch.unless_condition).reject { constant(it) == false }),
          **branch.state_guards.transform_values(&:to_h)
        }
      end

      # Whether the core never passes the branch's conditions: an if: that
      # always fails or an unless: that always holds, such as `if: ''`
      def never?(branch)
        conditions_of(branch.if_condition).any? { constant(it) == false } ||
          conditions_of(branch.unless_condition).any? { constant(it) == true }
      end

      # The conditions of an if:/unless: as the core reads them: nil, false
      # and [] are none, an Array is several
      def conditions_of(condition)
        return [] unless condition

        condition.is_a?(Array) ? condition : [condition]
      end

      # The value a condition always has, or nil when it depends on the
      # object. The core evaluates a String as code: code without an
      # expression ('', '   ', a comment) yields nil, a lone nil, false or
      # true literal its value. Before evaluating, the core checks the whole
      # String, comments included, with its own validator, raising
      # SecurityError for patterns it refuses and ArgumentError for bad
      # syntax; so does this, whatever the String would yield.
      def constant(condition)
        return unless condition.is_a?(String)

        validate_eval_string(condition)
        result = Prism.parse(condition)
        body = result.value.statements.body
        return false if body.empty?
        return unless body.one?

        case body.first
        when Prism::NilNode, Prism::FalseNode then false
        when Prism::TrueNode then true
        end
      end

      # The callbacks the core runs on +event_name+ from +from+ to +to+, by
      # kind, each method as { label:, conditions: } with the callback's own
      # guards (Introspection.guard_conditions form; all empty when it always
      # runs). The core files around callbacks with the before ones.
      def callbacks(machine, from, to, event_name)
        query = { from: from, to: to, on: event_name, guard: false }
        CALLBACK_TYPES.to_h do |type|
          matching = machine.callbacks[type == :after ? :after : :before].select do |callback|
            callback.type == type && !never?(callback.branch) && callback.branch.matches?(nil, query)
          end
          [type, matching.flat_map do |callback|
            conditions = guard_conditions(callback.branch)
            callback.instance_variable_get(:@methods).map { { label: Labels.action_label(it), conditions: conditions } }
          end]
        end
      end

      # #callbacks as text, by kind: "audit", or "audit (if enabled?)" for a
      # callback that runs only under its conditions
      def callback_labels(machine, from, to, event_name)
        callbacks(machine, from, to, event_name).transform_values { |list| list.map { Labels.callback_text(it) } }
      end

      # The core's own check of a String condition (see CORE_EVAL)
      def validate_eval_string(code)
        CORE_EVAL.send(:validate_eval_string, code)
      end

      def conditional?(conditions)
        conditions.values.any? { !it.empty? }
      end
    end
  end
end
