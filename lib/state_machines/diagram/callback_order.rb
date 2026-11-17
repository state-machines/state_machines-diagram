# frozen_string_literal: true

module StateMachines
  module Diagram
    # Whether MachineSchema's separate before/around/after arrays run a
    # transition's callbacks in the order the core runs them. The schema has
    # no field to say they would not, so a SchemaBuilder refuses such a
    # transition rather than describe another machine.
    module CallbackOrder
      module_function

      # Raises ArgumentError when the orders differ. +sequence+ is
      # Introspection.callback_sequence, +names+ the schema's arrays by kind,
      # +guarded+ whether the transition has guards, +selected+ whether its
      # source has several candidates in the event.
      def check(sequence, names, guarded:, selected:, transition:)
        core = core_order(sequence, guarded)
        schema = schema_order(names, guarded, selected)
        return if core == schema

        raise ArgumentError, "MachineSchema cannot express the callback order of #{transition}: the core runs " \
                             "#{core.join(', ')}; the schema would run #{schema.join(', ')}"
      end

      # The core: guards select the branch first, then the callback sequence
      def core_order(sequence, guarded)
        [*(['guards'] if guarded), *sequence.map { step_text(it[:kind], it[:phase], it[:label]) }]
      end

      # Code generated from MachineSchema (state-machines-rs typestate
      # codegen): every around's Before stage, guards, before callbacks, the
      # state change, after callbacks, then every around's AfterSuccess
      # stage, each list in its own order. A source with several candidates
      # checks guards first, to select one.
      def schema_order(names, guarded, selected)
        arounds = names[:around]
        [*(['guards'] if guarded && selected), *arounds.map { step_text(:around, :enter, it) },
         *(['guards'] if guarded && !selected),
         *names[:before].map { step_text(:before, nil, it) }, *names[:after].map { step_text(:after, nil, it) },
         *arounds.map { step_text(:around, :exit, it) }]
      end

      def step_text(kind, phase, label) = [kind, phase, label].compact.join(' ')
    end
  end
end
