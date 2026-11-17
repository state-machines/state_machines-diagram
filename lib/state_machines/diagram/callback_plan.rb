# frozen_string_literal: true

require_relative 'introspection'

module StateMachines
  module Diagram
    # Where a SchemaBuilder puts the callbacks the core runs on each
    # transition: in MachineSchema's machine-wide `callbacks` (with from /
    # to / on filters) or in the transition's own ordered `callbacks` list.
    #
    # Code generated from MachineSchema (state-machines-rs) checks guards
    # first, then runs the before and around callbacks in one list, the
    # machine-wide ones that match before the transition's, changes the
    # state, exits the arounds innermost first and runs the after callbacks
    # in the same merged order. The core runs the machine's before and around
    # callbacks before the branch's too, but the branch's after callbacks
    # before the machine's. So a machine callback goes machine-wide only when
    # its requirements map onto the filters exactly and every transition
    # still runs what the core runs, in its order; otherwise every callback
    # is listed on each transition, which always keeps the core's order.
    #
    # MachineSchema callbacks have no conditions: a conditional callback the
    # core may run is refused.
    class CallbackPlan
      # Whose callbacks may go machine-wide, tried in turn: all of the
      # machine's, its before and around ones, none
      LIFTS = [%i[before around after], %i[before around], []].freeze

      # The machine-wide callbacks, as MachineSchema writes them
      attr_reader :machine_callbacks

      # +performed+ is each event's (source, target, branch) transitions
      def initialize(machine, performed)
        @machine = machine
        @transitions = performed.flat_map do |event, transitions|
          transitions.map { |from, to, branch| Edge.new(event, from, to, branch, sequence(event, from, to, branch)) }
        end
        @event_names = performed.keys.map { it.name.to_s }
        lifted = LIFTS.lazy.map { |kinds| liftable(kinds) }.find { faithful?(it) }
        @lifted = lifted.to_h { [it.callback, it] }
        @machine_callbacks = lifted.select { |lift| @transitions.any? { lift.matches?(it) } }.flat_map(&:entries)
      end

      # The transition's own callbacks list: what the core runs on it that
      # no machine-wide callback covers, in its run order
      def transition_callbacks(event, from, to, branch)
        edge = @transitions.find { [it.event, it.from, it.to].eql?([event, from, to]) && it.branch.equal?(branch) }
        own_steps(edge).map { entry(it[:kind], it[:label]) }
      end

      # One transition the core performs and its callback sequence
      Edge = Data.define(:event, :from, :to, :branch, :sequence) do
        def source_id = Builder.state_id(from)
        def target_id = Builder.state_id(to)
      end

      # A machine callback written machine-wide: its filters, each nil when
      # it matches everything
      Lift = Data.define(:callback, :from, :to, :on) do
        def matches?(edge)
          (from.nil? || from.include?(edge.source_id)) && (to.nil? || to.include?(edge.target_id)) &&
            (on.nil? || on.include?(edge.event.name.to_s))
        end

        def entries
          filters = { from: from, to: to, on: on }.compact
          callback.callables.map { { kind: callback.type.to_s, name: Labels.action_label(it), **filters } }
        end
      end

      private

      def entry(kind, name) = { kind: kind.to_s, name: name }

      # The core's sequence, a conditional callback refused
      def sequence(event, from, to, branch)
        steps = Introspection.callback_sequence(@machine, from, to, event.name, branch: branch)
        steps.each do |step|
          next unless Introspection.conditional?(step[:conditions])

          raise ArgumentError, 'MachineSchema cannot express the conditional callback ' \
                               "#{Labels.callback_text(step)} on #{event.name}"
        end
        steps
      end

      def own_steps(edge)
        edge.sequence.reject { it[:phase] == :exit || @lifted.key?(it[:callback]) }
      end

      # The machine's callbacks of +kinds+ that run on some transition of the
      # schema, if all of their requirements map onto filters exactly; nil
      # when one does not. One that runs on none is left out.
      def liftable(kinds)
        running = @transitions.flat_map { |edge| edge.sequence.map { it[:callback] } }.uniq
        callbacks = (@machine.callbacks[:before] + @machine.callbacks[:after])
                    .select { kinds.include?(it.type) && running.include?(it) }
        lifts = callbacks.map { lift(it) }
        lifts.all? ? lifts : nil
      end

      # A callback without conditions and with one from / to requirement
      # that is not a loopback (same) maps onto filters: each matcher as the
      # states or events of the schema it matches. Its conditions are read,
      # not evaluated: the core evaluates (and checks) only those of a
      # callback whose transition matches.
      def lift(callback)
        branch = callback.branch
        return unless unconditional?(branch) && branch.state_requirements.one?

        requirement = branch.state_requirements.first
        return if requirement.values.any?(LoopbackMatcher)

        Lift.new(callback, state_filter(requirement[:from]), state_filter(requirement[:to]),
                 filter(branch.event_requirement, @event_names))
      end

      def unconditional?(branch)
        Conditions.conditions_of(branch.if_condition).empty? &&
          Conditions.conditions_of(branch.unless_condition).empty? && branch.state_guards.empty?
      end

      def state_filter(matcher)
        return if matcher.is_a?(AllMatcher)

        matcher.filter(Introspection.states_of(@machine).map(&:name)).map { Builder.state_id(it) }
      end

      def filter(matcher, names)
        return if matcher.is_a?(AllMatcher)

        matcher.filter(names.map(&:to_sym)).map(&:to_s)
      end

      # Whether generated code runs on every transition what the core runs,
      # in its order, with +lifts+ machine-wide
      def faithful?(lifts)
        return false unless lifts

        owned = lifts.to_h { [it.callback, true] }
        @transitions.all? do |edge|
          own = edge.sequence.reject { it[:phase] == :exit || owned.key?(it[:callback]) }
          merged = lifts.select { it.matches?(edge) }.flat_map(&:entries) + own.map { entry(it[:kind], it[:label]) }
          generated_order(merged) == core_order(edge.sequence)
        end
      end

      # How generated code runs a merged callbacks list
      def generated_order(callbacks)
        befores = callbacks.reject { it[:kind] == 'after' }
                           .map { [it[:kind], it[:kind] == 'around' ? :enter : nil, it[:name]] }
        exits = befores.select { it[1] == :enter }.reverse.map { [it[0], :exit, it[2]] }
        befores + exits + callbacks.select { it[:kind] == 'after' }.map { ['after', nil, it[:name]] }
      end

      def core_order(sequence)
        sequence.map { [it[:kind].to_s, it[:phase], it[:label]] }
      end
    end
  end
end
