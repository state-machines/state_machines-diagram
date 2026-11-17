# frozen_string_literal: true

module StateMachines
  module Diagram
    # Text for what a diagram shows of a machine: state names, conditions,
    # guard expressions and callbacks. Every renderer uses these, so a
    # machine reads the same in each format.
    module Labels
      # A condition token that is not one term of an expression as it stands
      COMPOUND = /[\s&|]|\A!/

      module_function

      # A state name as text, as the core shows it (State#description): the
      # nil state reads "nil"
      def state_text(name)
        name.nil? ? 'nil' : name.to_s
      end

      # One state guard as text, its requirements kept together under the
      # guard's own kind: "if_any_state (gate=open, alarm=on)"
      def state_guard_token(kind, requirements)
        pairs = requirements.map { |machine_name, state| "#{machine_name}=#{state_text(state)}" }
        pairs.one? ? "#{kind} #{pairs.first}" : "#{kind} (#{pairs.join(', ')})"
      end

      # The tokens of an if:/unless: condition. The core takes an Array as
      # several conditions (all must pass for if:, none for unless:), so
      # each is its own token.
      def condition_tokens(condition)
        return [] if condition.nil?

        (condition.is_a?(Array) ? condition : [condition]).map { action_label(it) }
      end

      # A token as one term of a guard expression: code that is more than
      # one term is parenthesized, so && and ! keep their meaning.
      def condition_term(token)
        token.match?(COMPOUND) ? "(#{token})" : token
      end

      # A branch's guards (Introspection.guard_conditions) as one expression:
      # every if: term, every unless: term negated, every state guard group;
      # all must hold.
      def guard_expression(conditions)
        terms = conditions.flat_map do |kind, value|
          case kind
          when :if then value.map { condition_term(it) }
          when :unless then value.map { "!#{condition_term(it)}" }
          else [state_guard_token(kind, value)]
          end
        end
        terms.join(' && ') unless terms.empty?
      end

      # A condition or callback method: a Symbol names the method the core
      # calls, a String is code it evaluates, a Proc or Method is shown by
      # where it is defined.
      def action_label(action)
        case action
        when Proc, Method then callable_label(action)
        else action.to_s
        end
      end

      # Human-readable label for a Proc/Method, pointing at its source
      # location; a Symbol#to_proc shows its Symbol
      def callable_label(callable)
        file, line = callable.source_location
        return "lambda@#{File.basename(file)}:#{line}" if file

        callable.inspect[/\(&(:\S+)\)/, 1]&.then { "&#{it}" } || 'lambda'
      end
    end
  end
end
