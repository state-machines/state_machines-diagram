# frozen_string_literal: true

require_relative 'conditions'
require_relative 'labels'

module StateMachines
  module Diagram
    # Reads a machine as the core resolves it: its states, the transitions
    # each branch performs, their guards and the callbacks that run on them.
    module Introspection
      # Callback kinds in the order they run around a transition
      CALLBACK_TYPES = %i[before around after].freeze

      module_function

      # The machine's states by priority
      def states_of(machine)
        machine.states.by_priority
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
      # The core only evaluates the conditions of a branch some source still
      # reaches, so only those are read (and checked, see #evaluated).
      def event_transitions(machine, event)
        settled = []
        event.branches.flat_map do |branch|
          pairs = transition_pairs(machine, branch).reject { settled.include?(it.first) }
          next [] if pairs.empty? || never?(branch)

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
      # The conditions the core evaluates, as tokens. A condition that always
      # passes is no condition, so it is left out (a String the core always
      # evaluates the same way, see Conditions.constant). Call it only for a branch
      # (or callback) the core reaches: it checks what the core would
      # (Conditions.evaluated).
      def guard_conditions(branch)
        {
          if: Labels.condition_tokens(if_conditions(branch).reject { Conditions.constant(it) == true }),
          unless: Labels.condition_tokens(unless_conditions(branch).reject { Conditions.constant(it) == false }),
          **branch.state_guards.transform_values(&:to_h)
        }
      end

      # Whether the core never passes the branch's conditions: an if: that
      # always fails or an unless: that always holds, such as `if: ''`. Call
      # it only for a branch (or callback) the core reaches.
      def never?(branch)
        # The core evaluates both lists, whatever the if: ones gave
        ifs = if_conditions(branch)
        unlesses = unless_conditions(branch)
        Conditions.constant(ifs.last) == false || Conditions.constant(unlesses.last) == true
      end

      # The if: conditions the core evaluates, in order: all must pass, so it
      # stops at one that always fails
      def if_conditions(branch) = Conditions.evaluated(branch.if_condition, false)

      # The unless: conditions the core evaluates, in order, whatever the
      # if: ones gave: none may hold, so it stops at one that always holds
      def unless_conditions(branch) = Conditions.evaluated(branch.unless_condition, true)

      # The callbacks the core runs on +event_name+ from +from+ to +to+, in
      # the order it runs them, each method as { kind:, phase:, label:,
      # conditions: } (conditions in #guard_conditions form; all empty when
      # it always runs). The core keeps before and around callbacks in one
      # list in declaration order: a before runs where it was declared, an
      # around enters there (phase: :enter) and wraps everything after it.
      # Then the state changes, the arounds exit innermost first
      # (phase: :exit), and the after callbacks run in declaration order.
      # phase is nil for before and after. Callback conditions depend on the
      # object, so a conditional callback is one that may run.
      def callback_sequence(machine, from, to, event_name)
        query = { from: from, to: to, on: event_name, guard: false }
        # The core matches the event and states before it evaluates a
        # callback's conditions
        live = ->(callback) { callback.branch.matches?(nil, query) && !never?(callback.branch) }
        befores = machine.callbacks[:before].select(&live).flat_map do |callback|
          callback_steps(callback, callback.type, callback.type == :around ? :enter : nil)
        end
        exits = befores.select { it[:phase] == :enter }.reverse.map { it.merge(phase: :exit) }
        afters = machine.callbacks[:after].select(&live).flat_map { callback_steps(it, :after, nil) }
        befores + exits + afters
      end

      def callback_steps(callback, kind, phase)
        conditions = guard_conditions(callback.branch)
        callback.callables.map do |method|
          { kind: kind, phase: phase, label: Labels.action_label(method), conditions: conditions }
        end
      end

      # #callback_sequence by kind, each in declaration order, as
      # { label:, conditions: }; an around is listed once
      def callbacks(machine, from, to, event_name)
        callbacks_by_kind(callback_sequence(machine, from, to, event_name))
      end

      # A #callback_sequence by kind, as #callbacks gives it
      def callbacks_by_kind(sequence)
        sequence = sequence.reject { it[:phase] == :exit }
        CALLBACK_TYPES.to_h do |type|
          [type, sequence.select { it[:kind] == type }.map { it.slice(:label, :conditions) }]
        end
      end

      # #callbacks as text, by kind: "audit", or "audit (if enabled?)" for a
      # callback that runs only under its conditions
      def callback_labels(machine, from, to, event_name)
        labels_by_kind(callbacks(machine, from, to, event_name))
      end

      def labels_by_kind(callbacks)
        callbacks.transform_values { |list| list.map { Labels.callback_text(it) } }
      end

      def conditional?(conditions)
        conditions.values.any? { !it.empty? }
      end
    end
  end
end
