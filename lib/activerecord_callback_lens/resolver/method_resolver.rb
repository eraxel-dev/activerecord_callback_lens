# frozen_string_literal: true

require "prism"

require_relative "../parser/condition_tree"
require_relative "../parser/ast_walker"

module ActiverecordCallbackLens
  module Resolver
    # Resolves a callback's MethodRefNode symbol (e.g. :sync_required?) into an
    # expanded ConditionTree.
    #
    # Given a model class and a method name, MethodResolver locates the method's
    # source via `instance_method(name).source_location`, parses the file with
    # Prism, isolates the matching DefNode, and maps its body onto a
    # ConditionTree with the shared Parser::AstWalker. Any MethodRefNode found in
    # that tree is then resolved recursively, so a predicate that delegates to
    # other predicates expands into a full boolean tree.
    #
    # Two guards prevent runaway recursion:
    #   - a `visited` Set closes direct (A -> A) and indirect (A -> B -> A) cycles
    #   - a MAX_DEPTH cap bounds otherwise-acyclic but deep chains
    #
    # Known limitation: a DefNode body is a StatementsNode and the resolver treats
    # the *last* statement as the effective return value (the same assumption
    # ConditionParser makes for lambda bodies). Methods with early returns or
    # guard clauses are therefore only partially understood and are left
    # unexpanded where the heuristic does not apply.
    class MethodResolver
      # Hard cap on recursion depth. A chain of method refs deeper than this is
      # left unexpanded rather than followed further.
      MAX_DEPTH = 5

      # @param model_class [Class] the ActiveRecord model the method is defined on
      # @param method_name [Symbol] the predicate/method to resolve
      # @return [Parser::ConditionTree::Node, nil] the expanded tree, or nil when
      #   the method cannot be located/parsed
      def self.resolve(model_class, method_name)
        new(model_class).resolve(method_name)
      end

      # Per-definition expansion entry point. Walks a CallbackDefinition's
      # condition_tree, resolves every MethodRefNode against the model, and
      # returns a new definition whose tree carries populated expanded_tree
      # fields. Bridges the resolver core and the CLI/Rake integration.
      #
      # @param definition [Collector::CallbackDefinition]
      # @param model_class [Class]
      # @return [Collector::CallbackDefinition] with condition_tree fully expanded
      def self.expand(definition, model_class)
        new(model_class).expand(definition)
      end

      # @param model_class [Class]
      def initialize(model_class)
        @model_class = model_class
      end

      # Expands every MethodRefNode in the definition's condition_tree.
      #
      # A definition with no condition_tree (nil) is returned unchanged; so is a
      # tree that contains no MethodRefNodes (expand_tree rebuilds it into a
      # value-equal copy, leaving non-expansion output identical to v0.1).
      #
      # @param definition [Collector::CallbackDefinition]
      # @return [Collector::CallbackDefinition]
      def expand(definition)
        return definition unless definition.condition_tree

        expanded = expand_tree(definition.condition_tree)
        definition.with(condition_tree: expanded)
      end

      # Resolves a method name into an expanded ConditionTree.
      #
      # @param method_name [Symbol]
      # @param depth [Integer] current recursion depth (0 at the entry point)
      # @param visited [Set<Symbol>] method names already on the current path
      # @return [Parser::ConditionTree::Node, nil]
      def resolve(method_name, depth: 0, visited: Set.new)
        if depth >= MAX_DEPTH
          warn("[ActiverecordCallbackLens] Max resolution depth (#{MAX_DEPTH}) reached at #{method_name}")
          return nil
        end
        return nil if visited.include?(method_name)

        visited = visited.dup
        visited.add(method_name)

        node = locate_and_parse(method_name)
        return nil if node.nil?

        expand_refs(node, depth: depth + 1, visited: visited)
      end

      private

      # Recursively rebuilds a condition_tree, populating expanded_tree on every
      # MethodRefNode. And/Or/Not structure is preserved by rebuilding children
      # through Data#with so callers' references are never mutated; nodes with no
      # MethodRefNode beneath them rebuild into value-equal copies.
      #
      # Each MethodRefNode is resolved from a fresh depth-0 walk (resolve applies
      # its own MAX_DEPTH/visited guards), so a ref's name (a String) is converted
      # to a Symbol before being handed to resolve.
      #
      # @param node [Parser::ConditionTree::Node, nil]
      # @return [Parser::ConditionTree::Node, nil]
      def expand_tree(node)
        case node
        in Parser::ConditionTree::AndNode | Parser::ConditionTree::OrNode
          node.with(children: node.children.map { |child| expand_tree(child) })
        in Parser::ConditionTree::NotNode
          node.with(child: expand_tree(node.child))
        in Parser::ConditionTree::MethodRefNode
          node.with(expanded_tree: resolve(node.name.to_sym))
        else
          node
        end
      end

      # Locates the method's source and parses its body into a ConditionTree.
      #
      # @param method_name [Symbol]
      # @return [Parser::ConditionTree::Node, nil] nil when the method has no Ruby
      #   source, the file is missing/unparseable, or no DefNode is found
      def locate_and_parse(method_name)
        location = source_location_for(method_name)
        return nil if location.nil?

        file, line = location
        return nil unless file && File.exist?(file)

        result = Prism.parse_file(file)
        unless result.success?
          warn("[ActiverecordCallbackLens] Failed to parse #{file}: #{result.errors.map(&:message).join(', ')}")
          return nil
        end

        locator = DefLocator.new(target_line: line, method_name: method_name)
        locator.visit(result.value)
        reclassify_refs(Parser::AstWalker.walk(locator.node))
      end

      # The shared AstWalker maps every bare predicate call to a PredicateNode
      # leaf. Inside a *method* body, though, a call to another method that this
      # model defines in Ruby is a MethodRefNode the resolver can expand. This
      # pass rewrites those leaves: a PredicateNode whose name resolves to a
      # method with a Ruby source_location becomes a (yet-unexpanded)
      # MethodRefNode; everything else (AR-generated dirty-tracking predicates,
      # C-level methods) stays a PredicateNode leaf.
      #
      # @param node [Parser::ConditionTree::Node, nil]
      # @return [Parser::ConditionTree::Node, nil]
      def reclassify_refs(node)
        tree = Parser::ConditionTree
        case node
        when tree::PredicateNode
          resolvable?(node.name) ? tree::MethodRefNode.new(name: node.name, expanded_tree: nil) : node
        when tree::AndNode, tree::OrNode
          node.with(children: node.children.map { |child| reclassify_refs(child) })
        when tree::NotNode
          node.with(child: reclassify_refs(node.child))
        else
          node
        end
      end

      # @param name [String] a predicate/method name
      # @return [Boolean] true when the model defines a method by this name that
      #   has a Ruby source_location (i.e. can be followed by the resolver)
      def resolvable?(name)
        location = source_location_for(name.to_sym)
        !location.nil?
      end

      # @param method_name [Symbol]
      # @return [Array(String, Integer), nil] the [file, line] pair, or nil when
      #   the method is undefined or C-level/eval'd (nil source_location)
      def source_location_for(method_name)
        @model_class.instance_method(method_name).source_location
      rescue NameError
        nil
      end

      # Walks a parsed ConditionTree and replaces every MethodRefNode with a copy
      # whose `expanded_tree` is the recursive resolution of that ref. And/Or/Not
      # structure is preserved by rebuilding children through Data#with.
      #
      # @param node [Parser::ConditionTree::Node, nil]
      # @param depth [Integer]
      # @param visited [Set<Symbol>]
      # @return [Parser::ConditionTree::Node, nil]
      def expand_refs(node, depth:, visited:)
        tree = Parser::ConditionTree
        case node
        when tree::MethodRefNode
          sub_tree = resolve(node.name.to_sym, depth: depth, visited: visited)
          node.with(expanded_tree: sub_tree)
        when tree::AndNode, tree::OrNode
          node.with(children: node.children.map { |child| expand_refs(child, depth: depth, visited: visited) })
        when tree::NotNode
          node.with(child: expand_refs(node.child, depth: depth, visited: visited))
        else
          node
        end
      end

      # A Prism visitor that captures the body of the DefNode matching a target
      # line (and, when available, a target method name). Mirrors ConditionParser's
      # LambdaLocator but targets `def` definitions rather than lambdas/blocks.
      class DefLocator < Prism::Visitor
        # @return [Prism::Node, nil] the body of the matched DefNode
        attr_reader :node

        # @param target_line [Integer] the line source_location reports for the def
        # @param method_name [Symbol, nil] the method name to disambiguate overloads
        def initialize(target_line:, method_name: nil)
          @target_line = target_line
          @method_name = method_name
          @node = nil
          super()
        end

        # @param def_node [Prism::DefNode]
        # @return [void]
        def visit_def_node(def_node)
          capture(def_node)
          super
        end

        private

        # Records the def's body when it both starts on the target line and (if a
        # name was supplied) carries the expected method name. Matching on the
        # start line keeps a method's own `def` from being shadowed by an enclosing
        # definition, while the name check guards against same-line edge cases.
        #
        # @param candidate [Prism::DefNode]
        # @return [void]
        def capture(candidate)
          return unless candidate.location.start_line == @target_line
          return if @method_name && candidate.name != @method_name

          @node = candidate.body
        end
      end
    end
  end
end
