# frozen_string_literal: true

require_relative 'builder'
require_relative 'schema_builder'
require 'set'

module StateMachines
  module Diagram
    module Renderer
      module_function

      def draw_machine(machine, io: $stdout, **options)
        diagram, builder = build_state_diagram(machine, options)
        output_diagram(diagram, io, options, builder)
        diagram
      end

      def build_state_diagram(machine, options)
        builder = Builder.new(machine, options)
        diagram = builder.build
        [diagram, builder]
      end

      def machine_schema(machine, options = {})
        SchemaBuilder.new(machine, options).build
      end

      def output_diagram(diagram, io, options, builder = nil)
        case options[:format]
        when :json
          io.puts diagram_hash_with_metadata(diagram, builder).to_json
        when :yaml
          require 'yaml'
          io.puts diagram_hash_with_metadata(diagram, builder).to_yaml
        when :machine_schema
          # Output MachineSchema format compatible with state-machines-rs CLI
          schema = SchemaBuilder.new(builder.machine, options)
          io.puts schema.to_json
        else
          # Default text representation
          io.puts diagram_to_text(diagram, options, builder)
        end
      end

      def draw_state(state, _graph, options = {}, io = $stdout)
        # Build a diagram containing just this state and its transitions
        machine = state.machine

        # Find all states involved with this state
        states_involved = Set.new([state.name])

        machine.events.each do |event|
          event.branches.each do |branch|
            branch.state_requirements.each do |requirement|
              valid_states = machine.states.by_priority.map(&:name)
              from_states = requirement[:from].filter(valid_states)
              to_states = requirement[:to].values

              if from_states.include?(state.name)
                states_involved.merge(to_states)
              elsif to_states.include?(state.name)
                states_involved.merge(from_states)
              end
            end
          end
        end

        # Build diagram with all involved states
        builder = Builder.new(machine, options)
        builder.instance_variable_set(:@diagram, builder.send(:create_diagram))

        # Add all involved states first
        machine.states.select { |s| states_involved.include?(s.name) }.each do |s|
          builder.send(:add_state_node, s)
        end

        # Then add transitions
        machine.events.each do |event|
          event.branches.each do |branch|
            branch.state_requirements.each do |requirement|
              valid_states = machine.states.by_priority.map(&:name)
              from_states = requirement[:from].filter(valid_states)
              to_states = requirement[:to].values

              # Only add if involves our state
              if (from_states & states_involved.to_a).any? && (to_states & states_involved.to_a).any?
                builder.send(:create_transitions, from_states & states_involved.to_a, to_states & states_involved.to_a,
                             event, branch)
              end
            end
          end
        end

        output_diagram(builder.diagram, io, options.merge(state_filter: state.name.to_s), builder)
      end

      def diagram_hash_with_metadata(diagram, builder)
        base_hash = diagram.to_h
        return base_hash unless builder

        transition_metadata_index = build_transition_metadata_index(builder)
        transition_hashes = extract_transition_hashes(base_hash)
        return base_hash unless transition_hashes

        diagram.transitions.each_with_index do |transition, index|
          metadata = transition_metadata_index[transition] ||
                     find_fallback_transition_metadata(transition_metadata_index, transition) ||
                     {}
          transition_hash = transition_hashes[index]
          next unless transition_hash

          guard_terms = guard_terms_for(transition, metadata)
          action_list = action_list_for(transition, metadata)

          guard_payload = {}
          guard_payload[:if] = guard_terms[:if] unless guard_terms[:if].empty?
          guard_payload[:unless] = guard_terms[:unless] unless guard_terms[:unless].empty?
          transition_hash[:guard] = guard_payload unless guard_payload.empty?

          transition_hash[:action] = action_list unless action_list.empty?
        end

        base_hash
      end

      def extract_transition_hashes(base_hash)
        data = base_hash[:data] || base_hash['data']
        return unless data

        data[:transitions] || data['transitions']
      end

      def draw_event(event, _graph, options = {}, io = $stdout)
        machine = event.machine

        # Add all states involved in this event
        states_involved = Set.new
        event.branches.each do |branch|
          branch.state_requirements.each do |requirement|
            valid_states = machine.states.by_priority.map(&:name)
            from_states = requirement[:from].filter(valid_states)
            to_states = requirement[:to].values

            states_involved.merge(from_states)
            states_involved.merge(to_states)
          end
        end

        # Build a fresh diagram for this event
        builder = Builder.new(machine, options)
        builder.instance_variable_set(:@diagram, builder.send(:create_diagram))

        # Add states to diagram first
        machine.states.select { |s| states_involved.include?(s.name) }.each do |state|
          builder.send(:add_state_node, state)
        end

        # Add transitions for this event
        builder.send(:add_event_transitions, event)

        output_diagram(builder.diagram, io, options.merge(event_filter: event.name.to_s), builder)
      end

      def draw_branch(branch, _graph, event, valid_states, io = $stdout)
        machine = event.machine

        # Add states involved in this branch
        states_involved = Set.new
        branch.state_requirements.each do |requirement|
          from_states = requirement[:from].filter(valid_states)
          to_states = requirement[:to].values

          states_involved.merge(from_states)
          states_involved.merge(to_states)
        end

        # Build fresh diagram
        builder = Builder.new(machine, {})
        builder.instance_variable_set(:@diagram, builder.send(:create_diagram))

        # Add states first
        machine.states.select { |s| states_involved.include?(s.name) }.each do |state|
          builder.send(:add_state_node, state)
        end

        # Add transitions
        builder.send(:add_branch_transitions, branch, event)

        output_diagram(builder.diagram, io, {}, builder)
      end

      def diagram_to_text(diagram, options = {}, builder = nil)
        # Defensive copy of options to prevent mutation affecting other tests
        safe_options = options.dup.freeze
        output = []

        # Add filter headers if specified
        if safe_options[:state_filter]
          output << "State: #{safe_options[:state_filter]}"
          output << ''
        elsif safe_options[:event_filter]
          output << "Event: #{safe_options[:event_filter]}"
          output << ''
        end

        output << "=== #{diagram.title} ==="
        output << ''

        # Use provided builder to access metadata (with nil safety)
        metadata_source = builder&.state_metadata || {}

        # List states
        output << 'States:'
        diagram.states.each do |state|
          metadata = metadata_source[state.id] || {}
          type_marker = case metadata[:type]
                        when 'initial' then ' [*]'
                        when 'final' then ' (O)'
                        else ''
                        end
          label = state.label || state.id
          output << "  - #{label}#{type_marker}"
        end

        output << ''
        output << 'Transitions:'

        # List transitions with semantic information from the transition objects
        transition_metadata_index = build_transition_metadata_index(builder)

        diagram.transitions.each do |transition|
          metadata = transition_metadata_index[transition] ||
                     find_fallback_transition_metadata(transition_metadata_index, transition) ||
                     {}
          condition_str = format_guard_condition(transition, metadata)
          action_str = format_action_callback(transition, metadata)

          label = transition.label || ''
          output << "  - #{transition.source_state_id} -> #{transition.target_state_id} [#{label}]#{condition_str}#{action_str}"
        end

        output.join("\n")
      end

      def build_transition_metadata_index(builder)
        return {} unless builder&.respond_to?(:transition_metadata)

        Array(builder.transition_metadata).each_with_object({}) do |metadata, index|
          transition = metadata[:transition]
          if transition
            index[transition] = metadata
          end

          key = [
            metadata[:from].to_s,
            metadata[:to].to_s,
            metadata[:event].to_s
          ]
          (index[:by_key] ||= Hash.new { |h, k| h[k] = [] })[key] << metadata
        end
      end

      def find_fallback_transition_metadata(index, transition)
        by_key = index[:by_key]
        return unless by_key

        key = [
          transition.source_state_id.to_s,
          transition.target_state_id.to_s,
          transition.label.to_s
        ]

        metadata_list = by_key[key]
        metadata_list&.first
      end

      def format_guard_condition(transition, metadata = {})
        guard_terms = guard_terms_for(transition, metadata)

        return '' if guard_terms[:if].empty? && guard_terms[:unless].empty?

        parts = []
        guard_terms[:if].each { |condition| parts << "(if: #{condition})" }
        guard_terms[:unless].each { |condition| parts << "(unless: #{condition})" }
        " #{parts.join(' ')}"
      end

      def guard_terms_for(transition, metadata = {})
        guard_terms = { if: [], unless: [] }

        if transition.respond_to?(:guard) && transition.guard
          parse_guard_string(transition.guard.to_s, guard_terms)
        end

        conditions = metadata.fetch(:conditions, {})
        Array(conditions[:if]).compact.each do |condition|
          Array(condition).each { |item| guard_terms[:if] << normalize_condition_name(item) }
        end
        Array(conditions[:unless]).compact.each do |condition|
          Array(condition).each { |item| guard_terms[:unless] << normalize_condition_name(item) }
        end

        guard_terms[:if].uniq!
        guard_terms[:unless].uniq!

        guard_terms
      end

      def parse_guard_string(guard_string, guard_terms)
        guard_string.split(/\s*&&\s*/).each do |segment|
          next if segment.nil? || segment.empty?

          if segment.start_with?('!')
            guard_terms[:unless] << normalize_condition_name(segment[1..])
          else
            guard_terms[:if] << normalize_condition_name(segment)
          end
        end
      end

      def normalize_condition_name(condition)
        return '' if condition.nil?

        condition_name = condition.to_s.strip
        condition_name = condition_name[1..] if condition_name.start_with?(':')
        condition_name
      end

      def format_action_callback(transition, metadata = {})
        actions = action_list_for(transition, metadata)
        return '' if actions.empty?

        " (action: #{actions.join(', ')})"
      end

      def action_list_for(transition, metadata = {})
        actions = []

        if transition.respond_to?(:action) && transition.action
          actions << normalize_action_name(transition.action)
        end

        callbacks = metadata.fetch(:callbacks, {})
        callbacks.values.each do |callback_list|
          Array(callback_list).each do |callback|
            actions << normalize_action_name(callback)
          end
        end

        actions.compact!
        actions.uniq!
        actions
      end

      def normalize_action_name(action)
        return if action.nil?

        action.is_a?(Symbol) ? action.to_s : action.to_s
      end
    end
  end
end
