# frozen_string_literal: true

require 'prism'

module StateMachines
  module Diagram
    # How the core reads an if:/unless: condition: which items it evaluates,
    # in order, and which always give the same value.
    module Conditions
      module_function

      # The leading conditions the core evaluates, up to the first whose
      # constant value is +stop_at+. Each String is checked first, as the
      # core checks it right before evaluating it (SecurityError or
      # ArgumentError); one the core never reaches is not.
      def evaluated(condition, stop_at)
        items = conditions_of(condition)
        index = items.index do |item|
          EvalHelpers.validate_eval_string(item) if item.is_a?(String)
          constant(item) == stop_at
        end
        index ? items.first(index + 1) : items
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
      # true literal its value. evaluated checks a String before this reads
      # it: the core checks the whole String, comments included, before it
      # evaluates it.
      def constant(condition)
        return unless condition.is_a?(String)

        result = Prism.parse(condition)
        body = result.value.statements.body
        return false if body.empty?
        return unless body.one?

        case body.first
        when Prism::NilNode, Prism::FalseNode then false
        when Prism::TrueNode then true
        end
      end
    end
  end
end
