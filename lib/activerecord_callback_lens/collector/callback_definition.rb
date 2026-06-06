# frozen_string_literal: true

require "prism"

module ActiverecordCallbackLens
  module Collector
    # Represents a single callback registered on an ActiveRecord model.
    #
    # event + phase together reconstruct the full callback name
    # (e.g. :before + :save => before_save).
    # raw_conditions holds the unprocessed if/unless arrays from AR internals.
    # condition_tree is nil until the Parser populates it (nil when no conditions).
    CallbackDefinition = Data.define(
      :model,           # Class — the ActiveRecord model class
      :event,           # Symbol — :save, :create, :update, :destroy, :validation
      :phase,           # Symbol — :before, :after, :around
      :filter,          # Symbol | Proc | String — the callback body
      :raw_conditions,  # { if: [...], unless: [...] } — raw arrays from AR internals
      :condition_tree,  # ConditionTree::Node | nil — parsed logical tree
      :source_location  # [String, Integer] | nil — file and line of the filter
    )

    # Reopened to add the shared formatting behaviour every renderer needs: the
    # callback's lifecycle name and a human-readable label for its filter. Keeping
    # this on the domain object (rather than duplicating it across the Mermaid,
    # Graphviz, and HTML renderers) guarantees identical output everywhere and
    # isolates the one I/O-heavy path (proc source slicing) for focused testing.
    class CallbackDefinition
      # The callback's lifecycle name, e.g. "before_save". Centralises the string
      # the renderers previously each rebuilt from phase + event.
      #
      # @return [String]
      def callback_name
        "#{phase}_#{event}"
      end

      # A human-readable label for the filter (Symbol, String, or Proc).
      #
      # Symbol/String filters render as their own text. A Proc renders as
      # "(proc)" by default; when +expand+ is true it renders its actual source
      # snippet (e.g. "-> { compute_reading_time }"), falling back to "(proc)" on
      # any I/O or parse error.
      #
      # @param expand [Boolean]
      # @return [String]
      def filter_label(expand: false)
        case filter
        when Proc
          return "(proc)" unless expand

          proc_source || "(proc)"
        else
          filter.to_s
        end
      end

      private

      # Extracts the Proc's raw source snippet by reading its source file with
      # Prism and slicing the enclosing lambda/block node, reusing the same
      # technique as ConditionParser#parse_proc. Returns nil on any error
      # (nil source_location, missing/unreadable file, parse failure, slice
      # error), so #filter_label falls back to "(proc)".
      #
      # @return [String, nil] the single-line source snippet, or nil on any error
      def proc_source
        file, line = filter.source_location
        return nil unless file && File.exist?(file)

        result = Prism.parse_file(file)
        return nil unless result.success?

        locator = ProcNodeLocator.new(target_line: line)
        locator.visit(result.value)
        node = locator.node
        return nil if node.nil?

        node.location.slice.strip.gsub(/\s*\n\s*/, " ")
      rescue StandardError
        nil
      end

      # A Prism visitor that captures the innermost LambdaNode or BlockNode whose
      # source range encloses a target line — the *whole* node (so its
      # location.slice yields the full "-> { ... }" / "{ ... }" text), unlike
      # ConditionParser::LambdaLocator which captures only the node body.
      class ProcNodeLocator < Prism::Visitor
        # @return [Prism::Node, nil] the innermost matching lambda/block node
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

        # Records the candidate when it encloses the target line. Because the
        # visitor descends depth-first, the last (innermost) enclosing match
        # wins, isolating nested blocks correctly.
        #
        # @param candidate [Prism::LambdaNode, Prism::BlockNode]
        # @return [void]
        def capture(candidate)
          location = candidate.location
          return unless @target_line.between?(location.start_line, location.end_line)

          @node = candidate
        end
      end
    end
  end
end
