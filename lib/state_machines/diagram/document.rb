# frozen_string_literal: true

require 'json'

module StateMachines
  module Diagram
    # A built diagram as diagram 0.4's document (type, version, checksum,
    # data), exactly as the diagram gem writes it, so Diagrams::Base.from_json
    # loads it back and its checksum holds. What the diagram cannot hold sits
    # beside it under "metadata": each state's name and markers, and each
    # transition's event, structured guards and callbacks, in diagram order.
    module Document
      module_function

      def to_h(builder)
        builder.diagram.to_h.merge(metadata: {
          scope: builder.scope,
          states: builder.diagram.states.map { state_entry(builder, it) },
          transitions: builder.transition_metadata.map { transition_entry(it) }
        }.compact)
      end

      def to_json(builder) = JSON.generate(to_h(builder))

      # Plain YAML with string keys, so YAML.safe_load reads it
      def to_yaml(builder)
        require 'yaml'
        JSON.parse(to_json(builder)).to_yaml
      end

      def state_entry(builder, state)
        { id: state.id, **builder.state_metadata.fetch(state.id).slice(:name, :label, :initial, :final) }
      end

      def transition_entry(metadata)
        conditions = metadata[:conditions].to_h do |kind, value|
          next [kind, value] if %i[if unless].include?(kind)

          [kind, value.to_h { |machine_name, state| [machine_name.to_s, state&.to_s] }]
        end
        { **metadata.slice(:event, :from, :to, :label), conditions: conditions, callbacks: metadata[:callbacks] }
      end
    end
  end
end
