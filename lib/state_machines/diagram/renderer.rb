# frozen_string_literal: true

require_relative 'builder'
require_relative 'document'
require_relative 'schema_builder'

module StateMachines
  module Diagram
    # The machine renderer: writes a machine, state, event or branch as text
    # (the default), as diagram 0.4's JSON or YAML document, or as a
    # state-machines-rs MachineSchema (format: :machine_schema).
    module Renderer
      FORMATS = [nil, :text, :json, :yaml, :machine_schema].freeze

      module_function

      def draw_machine(machine, io: $stdout, **options)
        builder = Builder.new(machine, options)
        builder.build
        output_diagram(builder, io, options)
        builder.diagram
      end

      def draw_state(state, _graph, options = {}, io = $stdout)
        builder = Builder.new(state.machine, options)
        builder.build_state(state)
        output_diagram(builder, io, options)
        builder.diagram
      end

      def draw_event(event, _graph, options = {}, io = $stdout)
        builder = Builder.new(event.machine, options)
        builder.build_event(event)
        output_diagram(builder, io, options)
        builder.diagram
      end

      def draw_branch(branch, _graph, event, _valid_states, io = $stdout)
        builder = Builder.new(event.machine)
        builder.build_branch(branch, event)
        output_diagram(builder, io, {})
        builder.diagram
      end

      # The whole machine's diagram and the builder holding its metadata
      def build_state_diagram(machine, options = {})
        builder = Builder.new(machine, options)
        [builder.build, builder]
      end

      def machine_schema(machine, options = {})
        SchemaBuilder.new(machine, options).build
      end

      # Writes what +builder+ built in options[:format]
      def output_diagram(builder, io, options = {})
        io.puts render(builder, options)
      end

      def render(builder, options = {})
        case options[:format]
        when nil, :text then diagram_to_text(builder)
        when :json then Document.to_json(builder)
        when :yaml then Document.to_yaml(builder)
        when :machine_schema then machine_schema_json(builder, options)
        else raise ArgumentError, "unknown format #{options[:format].inspect}; known: #{FORMATS.compact.join(', ')}"
        end
      end

      # The schema describes a whole machine, not a part of one
      def machine_schema_json(builder, options)
        raise ArgumentError, "format: :machine_schema describes a whole machine, not #{builder.scope}" if builder.scope

        SchemaBuilder.new(builder.machine, options).to_json
      end

      def diagram_to_text(builder)
        diagram = builder.diagram
        output = []
        output.push(builder.scope, '') if builder.scope
        output.push("=== #{diagram.title} ===", '', 'States:')

        # Names and labels come from the builder's metadata: the diagram
        # holds escaped ids and no blank text
        diagram.states.each do |state|
          metadata = builder.state_metadata.fetch(state.id)
          markers = +''
          markers << ' [*]' if metadata[:initial]
          markers << ' (O)' if metadata[:final]
          output << "  - #{metadata[:label]}#{markers}"
        end

        output.push('', 'Transitions:')
        builder.transition_metadata.each { output << "  - #{transition_text(it)}" }
        output.join("\n")
      end

      def transition_text(metadata)
        from = Labels.state_text(metadata[:from])
        to = Labels.state_text(metadata[:to])
        "#{from} -> #{to} [#{metadata[:label]}]#{guard_text(metadata[:conditions])}#{action_text(metadata[:callbacks])}"
      end

      # Each condition in parentheses under its kind; all must hold
      def guard_text(conditions)
        parts = conditions.flat_map do |kind, value|
          next value.map { "(#{kind}: #{it})" } if %i[if unless].include?(kind)

          requirements = value.map { |machine_name, state| "#{machine_name}=#{Labels.state_text(state)}" }
          ["(#{kind}: #{requirements.join(', ')})"]
        end
        parts.empty? ? '' : " #{parts.join(' ')}"
      end

      def action_text(callbacks)
        actions = callbacks.values.flatten
        actions.empty? ? '' : " (action: #{actions.join(', ')})"
      end
    end
  end
end
