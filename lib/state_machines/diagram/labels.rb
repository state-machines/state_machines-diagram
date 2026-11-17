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

      # What the core can evaluate as a condition
      CALLABLE = [Symbol, String, Proc, Method].freeze

      # The tokens of an if:/unless: condition, as the core reads it: nil,
      # false and [] are no condition, an Array is several (all must pass
      # for if:, none for unless:), each its own token. Anything else the
      # core raises ArgumentError on when it evaluates it, so it is refused
      # here rather than drawn as a condition.
      def condition_tokens(condition)
        return [] unless condition

        (condition.is_a?(Array) ? condition : [condition]).map do |item|
          unless CALLABLE.any? { item.is_a?(it) }
            raise ArgumentError, "#{item.inspect} is not a condition the core can evaluate " \
                                 '(a Symbol, String, Proc or Method)'
          end

          action_label(item)
        end
      end

      # A branch's guards (Introspection.guard_conditions) as phrases: "if a",
      # "unless b", each one term, then each state guard group
      def condition_phrases(conditions)
        conditions.flat_map do |kind, value|
          next value.map { "#{kind} #{condition_term(it)}" } if %i[if unless].include?(kind)

          [state_guard_token(kind, value)]
        end
      end

      # A callback sequence (Introspection.callback_sequence) in run order,
      # an around where it enters: "prepare, wrap, log"
      def action_list(sequence)
        sequence.reject { it[:phase] == :exit }.map { callback_text(it) }.join(', ')
      end

      # A callback (Introspection.callbacks) as text: its label, and the
      # conditions it runs under, "audit (if enabled?)"
      def callback_text(callback)
        phrases = condition_phrases(callback[:conditions])
        phrases.empty? ? callback[:label] : "#{callback[:label]} (#{phrases.join(' && ')})"
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
