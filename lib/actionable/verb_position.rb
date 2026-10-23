# frozen_string_literal: true

module Actionable
  # Where a non-bang recording verb (+fail+ / +fail_with+ / +skip+ /
  # +succeed+) may sit in a step or hook method (owner rulings R5, R10). Those verbs record an outcome and
  # keep running, so +fail :card_expired if card.expired?+ followed by more
  # code is almost always a +fail!+ that forgot its bang. The rule: the verb
  # must be the method's last expression, or explicitly end it.
  #
  # One implementation over a Prism AST, shared by the first-run check
  # ({Action.run} raises a {DefinitionError}) and the opt-in RuboCop cop
  # (+require: actionable/rubocop+). Self-contained on purpose: the cop loads
  # it without the rest of the gem. Prism is optional (Ruby 3.2 ships without
  # it), so nothing here requires it at load time; see {.prism?}.
  #
  # A verb call (receiver-less, or on +self+) is fine when it is:
  # - in tail position: the method body's last statement, or the last
  #   statement of a branch (+if+/+elsif+/+else+, ternary, +case+/+when+/+in+,
  #   +rescue+, +ensure+, the right side of +&&+/+and+/+||+/+or+, a block or
  #   loop body) whose enclosing construct is itself in tail position;
  # - returned: +return fail(:x)+, or followed directly by +return+;
  # - inside a block or loop body, followed directly by +next+/+break+, when
  #   that block's call is in tail position.
  # Anything else (more code follows on the method's path) is an offense. A
  # begin body that has an +else+ is followed by it; +ensure+ is cleanup that
  # runs even after a bang verb, so it never counts as following code.
  #
  # @api private
  module VerbPosition
    # The non-bang verbs that record an outcome without halting: every
    # +Action+ verb that writes the result and returns. +adopt_failure!+ (the
    # runner's nested-failure hand-off) halts, so it is not one.
    # @return [Array<Symbol>]
    VERBS = %i[fail fail_with skip succeed].freeze

    # The class-body declarations whose named methods run as steps or hooks.
    # @return [Array<Symbol>]
    DECLARATIONS = %i[step on_success on_failure on_skip always after_commit].freeze

    # The two-argument +on+ / one-argument +default+ branch targets inside a
    # +case_step+ block.
    # @return [Array<Symbol>]
    CASE_BRANCHES = %i[on default].freeze

    # The classes the RuboCop cop treats as action bases by default (its
    # +ActionBaseClasses+ option): a class body is checked only when its
    # superclass is one of these, or a class defined in the same file whose
    # own superclass chain reaches one.
    # @return [Array<String>]
    ACTION_BASE_CLASSES = %w[Actionable::Action ApplicationAction].freeze

    # The node types that open a new method scope: never looked inside.
    # @return [Array<Symbol>]
    SCOPES = %i[def_node class_node module_node singleton_class_node].freeze

    # One misplaced verb call.
    class Offense
      # @return [Symbol] the verb (one of {VERBS})
      attr_reader :verb
      # @return [Integer] the 1-based line of the call
      attr_reader :line
      # @return [Integer] the 0-based column of the call
      attr_reader :column
      # @return [Integer] the call's start, as a character offset into the source
      attr_reader :start_character
      # @return [Integer] the call's end, as a character offset into the source
      attr_reader :end_character

      # @param verb [Symbol]
      # @param line [Integer]
      # @param column [Integer]
      # @param start_character [Integer]
      # @param end_character [Integer]
      def initialize(verb, line, column, start_character, end_character)
        @verb = verb
        @line = line
        @column = column
        @start_character = start_character
        @end_character = end_character
      end
    end

    @files = {}
    @files_lock = Mutex.new

    class << self
      # Whether Prism can be loaded (it is a default gem from Ruby 3.3, and a
      # dependency of RuboCop). Checked once. Prism before 1.0 counts as
      # missing: its node API differs.
      #
      # @return [Boolean]
      def prism?
        return @prism if defined?(@prism)

        @prism = begin
          require 'prism'
          Gem::Version.new(::Prism::VERSION) >= Gem::Version.new('1.0')
        rescue LoadError
          false
        end
      end

      # The misplaced verb calls in one method.
      #
      # @param def_node [Prism::DefNode]
      # @return [Array<Offense>]
      def offenses(def_node)
        found = [] # : Array[Offense]
        visit(def_node.body, true, nil, found)
        found
      end

      # The misplaced verb calls in an instance method, read from its source
      # file (parsed once per path and mtime). Empty when Prism is missing,
      # the method has no readable source (+eval+, a C method), the file does
      # not parse cleanly, or no +def+ by that name starts on that line (a
      # +define_method+). The def is looked up by +original_name+, so a step
      # naming an +alias_method+ of it is checked too.
      #
      # Known limit: for a module prepended over the class's def, the method
      # resolved is the wrapper, so only the wrapper's body is checked, not
      # the class's own def it calls through +super+.
      #
      # @param method [UnboundMethod]
      # @return [Array<Offense>]
      def method_offenses(method)
        path, line = method.source_location
        return [] unless path && prism? && File.file?(path) && File.readable?(path)

        file_offenses(path).fetch([method.original_name, line], [])
      end

      # The step and hook methods an action class body declares, with their
      # offenses, for the RuboCop cop. A class body counts when its superclass
      # is an action base (owner ruling R10): one of +base_classes+, or a
      # class defined in this file (+class X < Y+ or +X = Class.new(Y)+, any
      # depth) whose superclass is. So a dry-transaction class, which also
      # declares +step+, is left alone. A superclass name resolves the way
      # Ruby looks it up: from the enclosing +module+ / +class+ keywords
      # outwards (a compact +class A::B+ opens only +A::B+), to the first
      # match among the file's classes and modules and +base_classes+, else
      # the top level; +::X+ is the top level. So +B::Base+ is not +A::Base+,
      # and a file class shadows a base class of the same name. It
      # must also declare a +step+ or +case_step+; the methods checked are the
      # ones it names in a declaration ({DECLARATIONS}, +case_step+ branch
      # targets), never a +case_step+'s value source. Covers +class X < Y+ and
      # +Class.new(Y) do ... end+.
      #
      # @param root [Prism::Node] a parsed file's root
      # @param base_classes [Array<String>] the action base class names
      # @return [Array<Offense>]
      def declared_step_offenses(root, base_classes: ACTION_BASE_CLASSES)
        bases = base_classes.map { |name| name.to_s.delete_prefix('::') }
        parents = file_superclasses(root)
        lineage = {bases: bases, parents: parents, known: known_names(parents.keys + bases)}
        found = [] # : Array[Offense]
        each_class_body(root) do |statements, superclass, nesting|
          next unless action_superclass?(superclass, nesting, lineage, [])

          names = declared_methods(statements)
          next if names.empty?

          each_instance_def(statements) { |def_node| found.concat(offenses(def_node)) if names.include?(def_node.name) }
        end
        found
      end

      private

      # @param path [String]
      # @return [Hash{Array(Symbol, Integer)=>Array<Offense>}] [name, def line] => offenses
      def file_offenses(path)
        key = [path, File.mtime(path)]
        @files_lock.synchronize { @files[key] ||= analyze_file(path) }
      end

      # Every def in the file, keyed by name and start line. Holding the
      # results, not the tree, keeps the cache small.
      #
      # @param path [String]
      # @return [Hash{Array(Symbol, Integer)=>Array<Offense>}]
      def analyze_file(path)
        result = ::Prism.parse_file(path)
        return {} unless result.errors.empty?

        index = {} # : Hash[[Symbol, Integer], Array[Offense]]
        each_node(result.value) do |node|
          index[[node.name, node.location.start_line]] = offenses(node) if node.type == :def_node
        end
        index
      end

      # Depth-first walk over every node.
      #
      # @param node [Prism::Node]
      # @yieldparam node [Prism::Node]
      # @return [void]
      def each_node(node, &block)
        yield node
        node.compact_child_nodes.each { |child| each_node(child, &block) }
      end

      # @param node [Prism::Node, nil]
      # @param tail [Boolean] whether nothing follows +node+ on the method's path
      # @param loop_tail [Boolean, nil] the tail of the innermost block or loop
      #   body (+next+/+break+ end it), +nil+ outside one
      # @param found [Array<Offense>]
      # @return [void]
      def visit(node, tail, loop_tail, found)
        return if node.nil? || SCOPES.include?(node.type)

        case node.type
        when :statements_node then visit_statements(node.body, tail, loop_tail, found)
        when :call_node then visit_call(node, tail, loop_tail, found)
        when :if_node, :unless_node, :else_node, :case_node, :case_match_node, :when_node, :in_node,
             :rescue_node, :ensure_node, :parentheses_node
          visit_branches(node, tail, loop_tail, found)
        when :begin_node then visit_begin(node, tail, loop_tail, found)
        when :and_node, :or_node
          visit(node.left, false, loop_tail, found)
          visit(node.right, tail, loop_tail, found)
        when :rescue_modifier_node
          visit(node.expression, tail, loop_tail, found)
          visit(node.rescue_expression, tail, loop_tail, found)
        when :return_node then visit_returned(node, true, loop_tail, found)
        when :next_node, :break_node then visit_returned(node, loop_tail || false, loop_tail, found)
        when :while_node, :until_node, :for_node then visit_loop(node, tail, loop_tail, found)
        when :lambda_node then visit(node.body, tail, tail, found)
        else visit_children(node.compact_child_nodes, loop_tail, found)
        end
      end

      # A statement is in tail position when it is the last one, and is
      # treated as such when the next one ends the path: +return+ always,
      # +next+/+break+ as the end of the block or loop body.
      #
      # @param statements [Array<Prism::Node>]
      # @param tail [Boolean]
      # @param loop_tail [Boolean, nil]
      # @param found [Array<Offense>]
      # @return [void]
      def visit_statements(statements, tail, loop_tail, found)
        statements.each_with_index do |statement, index|
          following = statements[index + 1]
          statement_tail =
            case following&.type
            when nil then tail
            when :return_node then true
            when :next_node, :break_node then loop_tail || false
            else false
            end
          visit(statement, statement_tail, loop_tail, found)
        end
      end

      # @param node [Prism::CallNode]
      # @param tail [Boolean]
      # @param loop_tail [Boolean, nil]
      # @param found [Array<Offense>]
      # @return [void]
      def visit_call(node, tail, loop_tail, found)
        found << offense(node) if verb_call?(node) && !tail
        visit(node.receiver, false, loop_tail, found)
        visit(node.arguments, false, loop_tail, found)
        block = node.block
        if block&.type == :block_node
          visit(block.body, tail, tail, found)
        else
          visit(block, false, loop_tail, found)
        end
      end

      # Conditions and patterns run first, so they are never in tail
      # position; every branch body inherits the construct's.
      #
      # @param node [Prism::Node]
      # @param tail [Boolean]
      # @param loop_tail [Boolean, nil]
      # @param found [Array<Offense>]
      # @return [void]
      def visit_branches(node, tail, loop_tail, found)
        branches = branch_nodes(node)
        conditions = node.compact_child_nodes - branches
        visit_children(conditions, loop_tail, found)
        branches.each { |branch| visit(branch, tail, loop_tail, found) }
      end

      # @param node [Prism::Node]
      # @return [Array<Prism::Node>] the child nodes that are branch bodies
      def branch_nodes(node)
        case node.type
        when :if_node then [node.statements, node.subsequent]
        when :unless_node then [node.statements, node.else_clause]
        when :case_node, :case_match_node then [*node.conditions, node.else_clause]
        when :rescue_node then [node.statements, node.subsequent]
        when :parentheses_node then [node.body]
        else [node.statements] # else / when / in / ensure
        end.compact
      end

      # The value of +return+ / +next+ / +break+ is what ends the path.
      #
      # @param node [Prism::ReturnNode, Prism::NextNode, Prism::BreakNode]
      # @param tail [Boolean]
      # @param loop_tail [Boolean, nil]
      # @param found [Array<Offense>]
      # @return [void]
      def visit_returned(node, tail, loop_tail, found)
        (node.arguments&.arguments || []).each { |value| visit(value, tail, loop_tail, found) }
      end

      # A begin body is followed by its +else+ (which runs when nothing was
      # rescued), never by its +ensure+.
      #
      # @param node [Prism::BeginNode]
      # @param tail [Boolean]
      # @param loop_tail [Boolean, nil]
      # @param found [Array<Offense>]
      # @return [void]
      def visit_begin(node, tail, loop_tail, found)
        visit(node.statements, node.else_clause ? false : tail, loop_tail, found)
        [node.rescue_clause, node.else_clause, node.ensure_clause].each { |part| visit(part, tail, loop_tail, found) }
      end

      # A loop body is like a block body: its end (or +next+/+break+) is in
      # tail position only when the loop is.
      #
      # @param node [Prism::WhileNode, Prism::UntilNode, Prism::ForNode]
      # @param tail [Boolean]
      # @param loop_tail [Boolean, nil]
      # @param found [Array<Offense>]
      # @return [void]
      def visit_loop(node, tail, loop_tail, found)
        visit_children(node.compact_child_nodes - [node.statements], loop_tail, found)
        visit(node.statements, tail, tail, found)
      end

      # @param nodes [Array<Prism::Node>]
      # @param loop_tail [Boolean, nil]
      # @param found [Array<Offense>]
      # @return [void]
      def visit_children(nodes, loop_tail, found)
        nodes.each { |child| visit(child, false, loop_tail, found) }
      end

      # @param node [Prism::CallNode]
      # @return [Boolean]
      def verb_call?(node)
        VERBS.include?(node.name) && (node.receiver.nil? || node.receiver.type == :self_node) && !node.safe_navigation?
      end

      # @param node [Prism::CallNode]
      # @return [Offense]
      def offense(node)
        location = node.location
        Offense.new(node.name, location.start_line, location.start_column,
          location.start_character_offset, location.end_character_offset)
      end

      # Every class body in the tree, with its superclass and the lexical
      # nesting the superclass is looked up in: +class X < Y+ bodies and
      # +Class.new(Y) do ... end+ blocks.
      #
      # @param root [Prism::Node]
      # @yieldparam statements [Prism::StatementsNode]
      # @yieldparam superclass [Prism::Node, nil]
      # @yieldparam nesting [Array<String>]
      # @return [void]
      def each_class_body(root)
        each_scoped_node(root, []) do |node, nesting|
          body, superclass =
            if node.type == :class_node
              [node.body, node.superclass]
            elsif class_new?(node) && node.block&.type == :block_node
              [node.block.body, class_new_superclass(node)]
            end
          yield body, superclass, nesting if body&.type == :statements_node
        end
      end

      # Depth-first walk over every node, with the full names of the
      # +module+ / +class+ keywords around it, innermost first (Ruby's
      # +Module.nesting+). A class's own node (and so its superclass) sees the
      # nesting outside it.
      #
      # @param node [Prism::Node]
      # @param nesting [Array<String>]
      # @yieldparam node [Prism::Node]
      # @yieldparam nesting [Array<String>]
      # @return [void]
      def each_scoped_node(node, nesting, &block)
        yield node, nesting
        inner = nesting
        if %i[class_node module_node].include?(node.type)
          name = defined_name(node.constant_path, nesting)
          inner = [name, *nesting] if name
        end
        node.compact_child_nodes.each { |child| each_scoped_node(child, inner, &block) }
      end

      # The classes and modules defined in the file, keyed by full name, with
      # the superclass each definition names and the nesting it is looked up
      # in. A module, or a class with no superclass, maps to none: it still
      # shadows a base class of the same name.
      #
      # @param root [Prism::Node]
      # @return [Hash{String=>Array<Array(Prism::Node, Array<String>)>}]
      def file_superclasses(root)
        parents = Hash.new { |hash, name| hash[name] = [] } # : Hash[String, Array[untyped]]
        each_scoped_node(root, []) do |node, nesting|
          name, superclass =
            case node.type
            when :class_node, :module_node
              [defined_name(node.constant_path, nesting), node.type == :class_node && node.superclass]
            when :constant_write_node
              [defined_name(node, nesting), class_new_superclass(node.value)] if class_new?(node.value)
            end
          next unless name

          parents[name]
          parents[name] << [superclass, nesting] if superclass
        end
        parents
      end

      # Every name and each of its namespaces (+A::B::C+ gives +A+, +A::B+,
      # +A::B::C+).
      #
      # @param names [Array<String>]
      # @return [Array<String>]
      def known_names(names)
        names.flat_map do |name|
          segments = name.split('::')
          (1..segments.size).map { |size| segments.first(size).join('::') }
        end.uniq
      end

      # Whether +node+ names an action base, directly or through classes
      # defined in the file. +seen+ guards against a superclass cycle.
      #
      # @param node [Prism::Node, nil]
      # @param nesting [Array<String>] where +node+ is looked up
      # @param lineage [Hash{Symbol=>Array<String>, Hash}] +:bases+, +:parents+
      #   ({file_superclasses}) and +:known+ ({known_names})
      # @param seen [Array<String>]
      # @return [Boolean]
      def action_superclass?(node, nesting, lineage, seen)
        name = resolve(node, nesting, lineage[:known])
        return false unless name
        return true if lineage[:bases].include?(name)
        return false if seen.include?(name)

        seen << name
        lineage[:parents].fetch(name, []).any? { |parent, scope| action_superclass?(parent, scope, lineage, seen) }
      end

      # The full name a constant reference resolves to: its first segment
      # joined to the innermost +nesting+ entry that defines it, else the top
      # level.
      #
      # @param node [Prism::Node, nil]
      # @param nesting [Array<String>]
      # @param known [Array<String>]
      # @return [String, nil] +nil+ when +node+ is not a plain constant reference
      def resolve(node, nesting, known)
        path, absolute = constant_reference(node)
        return path if path.nil? || absolute

        head = path.split('::').first
        scope = nesting.find { |cref| known.include?("#{cref}::#{head}") }
        scope ? "#{scope}::#{path}" : path
      end

      # The full name a +class+ / +module+ keyword or constant assignment
      # defines: its path inside the innermost nesting entry (a compact path
      # is taken as written there), or as written after a leading +::+.
      #
      # @param node [Prism::Node] the constant path, or a +ConstantWriteNode+
      # @param nesting [Array<String>]
      # @return [String, nil]
      def defined_name(node, nesting)
        path, absolute = node.type == :constant_write_node ? [node.name.to_s, false] : constant_reference(node)
        return path if path.nil? || absolute || nesting.empty?

        "#{nesting.first}::#{path}"
      end

      # @param node [Prism::Node, nil]
      # @return [Array(String, Boolean), nil] the constant path +node+ spells,
      #   without a leading +::+, and whether it had one; +nil+ for anything
      #   else (+Class.new(base)+, +foo::Bar+)
      def constant_reference(node)
        case node&.type
        when :constant_read_node then [node.name.to_s, false]
        when :constant_path_node
          name = node.full_name
          [name.delete_prefix('::'), name.start_with?('::')]
        end
      rescue ::Prism::ConstantPathNode::DynamicPartsInConstantPathError
        nil
      end

      # @param node [Prism::Node, nil]
      # @return [Boolean] whether +node+ is +Class.new(...)+, with or without a block
      def class_new?(node)
        node&.type == :call_node && node.name == :new && node.receiver&.type == :constant_read_node &&
          node.receiver.name == :Class
      end

      # @param node [Prism::CallNode] a +Class.new(...)+ call
      # @return [Prism::Node, nil] its superclass argument
      def class_new_superclass(node)
        node.arguments&.arguments&.first
      end

      # The method names a class body's declarations name, or none when it
      # declares no +step+ / +case_step+ (an ActiveRecord model's
      # +after_commit+ alone is not an action).
      #
      # @param statements [Prism::StatementsNode]
      # @return [Array<Symbol>]
      def declared_methods(statements)
        calls = statements.body.select { |node| node.type == :call_node && node.receiver.nil? }
        return [] unless calls.any? { |call| %i[step case_step].include?(call.name) }

        calls.flat_map do |call|
          if call.name == :case_step
            case_branch_targets(call)
          elsif DECLARATIONS.include?(call.name)
            [target_name(call.arguments&.arguments&.first)]
          else
            []
          end
        end.compact
      end

      # @param call [Prism::CallNode] a +case_step+ declaration
      # @return [Array<Symbol, nil>]
      def case_branch_targets(call)
        body = call.block&.body
        return [] unless call.block&.type == :block_node && body&.type == :statements_node

        body.body.filter_map do |branch|
          next unless branch.type == :call_node && CASE_BRANCHES.include?(branch.name)

          arguments = branch.arguments&.arguments || []
          target_name(branch.name == :on ? arguments[1] : arguments[0])
        end
      end

      # @param node [Prism::Node, nil] a declaration's target argument
      # @return [Symbol, nil] the method it names, if it names one
      def target_name(node)
        case node&.type
        when :symbol_node then node.unescaped.to_sym
        when :string_node then node.unescaped.to_sym
        end
      end

      # The instance-method defs directly in a class body, including those
      # wrapped in +private def ...+.
      #
      # @param statements [Prism::StatementsNode]
      # @yieldparam def_node [Prism::DefNode]
      # @return [void]
      def each_instance_def(statements)
        statements.body.each do |node|
          candidates = node.type == :call_node && node.receiver.nil? ? node.arguments&.arguments || [] : [node]
          candidates.each { |candidate| yield candidate if candidate.type == :def_node && candidate.receiver.nil? }
        end
      end
    end
  end
end
