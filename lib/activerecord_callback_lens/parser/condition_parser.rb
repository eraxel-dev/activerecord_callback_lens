# frozen_string_literal: true

require "prism"

require_relative "condition_tree"
require_relative "ast_walker"

module ActiverecordCallbackLens
  module Parser
    # Turns a CallbackDefinition's raw if/unless conditions into a structured
    # ConditionTree.
    #
    # Proc/Lambda conditions are parsed by reading their source file with Prism,
    # isolating the enclosing lambda/block node by line number, and recursively
    # mapping the boolean AST (`&&`, `||`, `!`, predicate calls) onto ConditionTree
    # nodes. Symbol conditions become MethodRefNodes whose expansion is deferred to
    # the MethodResolver. Any other entry kind (e.g. ActiveModel's framework
    # injected Conditionals::Value guard on after_* callbacks) is ignored.
    #
    # Parsing never raises on missing or unreadable source: a nil source_location
    # or a missing file is skipped silently, and a Prism parse failure warns to
    # $stderr while leaving the condition unresolved.
    class ConditionParser
      # @param definition [Collector::CallbackDefinition]
      # @return [Collector::CallbackDefinition] a copy with condition_tree populated
      def self.parse(definition)
        new(definition).parse
      end

      # @param definition [Collector::CallbackDefinition]
      def initialize(definition)
        @definition = definition
      end

      # @return [Collector::CallbackDefinition] a copy with condition_tree set
      def parse
        @definition.with(condition_tree: build_tree)
      end

      private

      # Assembles if_nodes and negated unless_nodes into a single tree.
      #
      # @return [ConditionTree::Node, nil] nil when there are no resolvable conditions
      def build_tree
        conditions   = @definition.raw_conditions
        if_nodes     = Array(conditions[:if]).map { |c| parse_condition(c) }
        unless_nodes = Array(conditions[:unless]).map { |c| negate(parse_condition(c)) }

        combine((if_nodes + unless_nodes).compact)
      end

      # Reduces a flat list of resolved condition nodes to a single tree.
      #
      # @param nodes [Array<ConditionTree::Node>]
      # @return [ConditionTree::Node, nil]
      def combine(nodes)
        case nodes.size
        when 0 then nil
        when 1 then nodes.first
        else ConditionTree::AndNode.new(children: nodes)
        end
      end

      # @param node [ConditionTree::Node, nil]
      # @return [ConditionTree::NotNode, nil]
      def negate(node)
        AstWalker.negate(node)
      end

      # Dispatches a single raw condition entry to the right handler.
      #
      # @param condition [Symbol, Proc, Object]
      # @return [ConditionTree::Node, nil]
      def parse_condition(condition)
        case condition
        when Symbol then ConditionTree::MethodRefNode.new(name: condition.to_s, expanded_tree: nil)
        when Proc   then parse_proc(condition)
        end
      end

      # Parses a Proc/Lambda condition by reading and walking its source.
      #
      # @param proc_obj [Proc]
      # @return [ConditionTree::Node, nil]
      def parse_proc(proc_obj)
        file, line = proc_obj.source_location
        return nil unless file && File.exist?(file)

        result = Prism.parse_file(file)
        unless result.success?
          warn("[ActiverecordCallbackLens] Failed to parse #{file}: #{result.errors.map(&:message).join(', ')}")
          return nil
        end

        locator = LambdaLocator.new(target_line: line)
        locator.visit(result.value)
        AstWalker.walk(locator.node)
      end

      # A Prism visitor that captures the innermost LambdaNode or BlockNode whose
      # source range encloses a target line. Used to isolate a single proc's body
      # from the surrounding file AST.
      class LambdaLocator < Prism::Visitor
        # @return [Prism::Node, nil] the body of the innermost matching lambda/block
        attr_reader :node

        # @param target_line [Integer] the line the proc's source_location reports
        def initialize(target_line:)
          @target_line = target_line
          @node = nil
          super()
        end

        # @param lambda_node [Prism::LambdaNode]
        # @return [void]
        def visit_lambda_node(lambda_node)
          capture(lambda_node)
          super
        end

        # @param block_node [Prism::BlockNode]
        # @return [void]
        def visit_block_node(block_node)
          capture(block_node)
          super
        end

        private

        # Records the candidate's body when it encloses the target line. Because
        # the visitor descends depth-first, the last (innermost) enclosing match
        # wins, isolating nested blocks correctly.
        #
        # @param candidate [Prism::LambdaNode, Prism::BlockNode]
        # @return [void]
        def capture(candidate)
          location = candidate.location
          return unless @target_line.between?(location.start_line, location.end_line)

          @node = candidate.body
        end
      end
    end
  end
end
