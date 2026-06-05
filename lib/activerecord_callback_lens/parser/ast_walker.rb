# frozen_string_literal: true

require "prism"

require_relative "condition_tree"

module ActiverecordCallbackLens
  module Parser
    # Maps a Prism boolean AST (`&&`, `||`, `!`, predicate calls) onto the
    # ConditionTree node types. Shared by ConditionParser (lambda bodies) and
    # MethodResolver (method bodies) so the two stay in lockstep.
    #
    # The walker recognises the same boolean vocabulary the v0.1 ConditionParser
    # established:
    #   - StatementsNode  -> the last statement is the effective return value
    #   - ParenthesesNode -> transparent; walk the inner body
    #   - AndNode/OrNode  -> AndNode/OrNode combinators (nil operands dropped)
    #   - CallNode `!`    -> NotNode wrapping the negated receiver
    #   - CallNode        -> PredicateNode for the called method name
    #   - anything else    -> nil (unresolvable)
    module AstWalker
      module_function

      # Recursively maps a Prism boolean AST onto ConditionTree nodes.
      #
      # @param node [Prism::Node, nil]
      # @return [ConditionTree::Node, nil]
      def walk(node)
        case node
        in Prism::StatementsNode then walk(node.body.last)
        in Prism::ParenthesesNode then walk(node.body)
        in Prism::AndNode then combinator(ConditionTree::AndNode, node)
        in Prism::OrNode then combinator(ConditionTree::OrNode, node)
        in Prism::CallNode if node.name == :! then negate(walk(node.receiver))
        in Prism::CallNode then ConditionTree::PredicateNode.new(name: node.name.to_s)
        else nil
        end
      end

      # Builds an And/Or combinator from a binary Prism node, walking both sides
      # and dropping any unresolved (nil) operand.
      #
      # @param klass [Class] ConditionTree::AndNode or ConditionTree::OrNode
      # @param node [Prism::AndNode, Prism::OrNode]
      # @return [ConditionTree::Node]
      def combinator(klass, node)
        klass.new(children: [walk(node.left), walk(node.right)].compact)
      end

      # @param node [ConditionTree::Node, nil]
      # @return [ConditionTree::NotNode, nil]
      def negate(node)
        return nil if node.nil?

        ConditionTree::NotNode.new(child: node)
      end
    end
  end
end
