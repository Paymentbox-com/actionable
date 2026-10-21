# frozen_string_literal: true

module Actionable
  # Generates RBS for a *user* action class — track 2 of the RBS strategy
  # (decision D13). Sord covers the library's static classes, but it can't see
  # +CreateInvoice.run(amount:)+ or +result.invoice+: those depend on the
  # action's declared +input+/+output+ schemas. This walks those schemas (via
  # FieldStruct's metadata and +ruby_type+ mapping) and emits:
  #
  # * a typed +.run+ signature from the input schema (or +(*untyped)+ when
  #   free-form);
  # * a nested +Output+ struct with a typed accessor per output field;
  # * a nested +Result+ with +output+ and the convenience-delegation readers,
  #   which +.run+ returns;
  # * when the action declares failures with +fails+, a +failure_code+ type
  #   alias listing every code it can fail with: the declared ones, then the
  #   {Action::GEM_FAILURE_CODES} (decision D20);
  # * when the action declares skips with +skips+, a +skip_code+ type alias
  #   listing every code it can skip with (decision D21). The gem emits no skip
  #   codes of its own, so the alias holds the declared ones only.
  #
  # Under typed outcomes (decision D23) +.run+ returns the action's own
  # +Success | Skipped | Failure+ instead, each typed with its +code+ and an
  # +output+ that names what the outcome can carry: a nested class per code
  # that declares an output schema (+AlreadyActiveSkipOutput+,
  # +InvalidFailureOutput+), and a Hash for a code without one. A failure's
  # output also admits every skip schema and +Output+, since a broken one ends
  # the run as +invalid_output+ carrying it.
  #
  #   class CreateInvoice < Actionable::Action
  #     input  { required :amount, :integer }
  #     output { required :invoice, :string }
  #   end
  #
  #   puts Actionable::RBS.generate(CreateInvoice)
  #   # class CreateInvoice < ::Actionable::Action
  #   #   def self.run: (amount: ::Integer) -> Result
  #   #   class Output < ::FieldStruct::Base ... end
  #   #   class Result < ::Actionable::Result ... end
  #   # end
  #
  # The emitted +Result+/+Output+ are generated type aids: at runtime +.run+
  # returns a {Success}/{Failure}/{Skipped} that responds to these via output
  # delegation. Referenced field types appear as qualified names (+::Invoice+) —
  # generate RBS for those (e.g. via +FieldStruct::RBS+) so they resolve.
  module RBS
    BOOL_CLASSES = [TrueClass, FalseClass].freeze
    private_constant :BOOL_CLASSES

    # Generate RBS source for a user action class.
    #
    # @param klass [Class<Actionable::Action>]
    # @return [String] RBS for the action, wrapped in its module nesting
    # @raise [ArgumentError] when +klass+ is not a named {Actionable::Action} subclass
    def self.generate(klass)
      unless klass.is_a?(::Class) && klass < Actionable::Action
        raise ArgumentError, "Actionable::RBS.generate expects an Actionable::Action subclass, got #{klass.inspect}"
      end
      raise ArgumentError, 'cannot generate RBS for an anonymous action' unless klass.name

      wrap_namespace(klass.name, class_block(klass))
    end

    # @param klass [Class<Actionable::Action>]
    # @return [String]
    def self.class_block(klass)
      return typed_class_block(klass) if klass.typed_outcomes?

      simple = klass.name.split('::').last
      aliases = []
      aliases << failure_code_alias(klass) unless klass.declared_failures.empty?
      aliases << skip_code_alias(klass) unless klass.declared_skips.empty?
      body = ["def self.run: #{run_signature(klass)}"]
      body.unshift(*aliases, '') unless aliases.empty?
      if (schema = klass.output_schema)
        body << ''
        body << output_block(schema)
        body << ''
        body << result_block(schema)
      end
      "class #{simple} < ::Actionable::Action\n#{indent(body.join("\n"))}\nend"
    end
    private_class_method :class_block

    # The class block of an action with typed outcomes (decision D23).
    #
    # @param klass [Class<Actionable::Action>]
    # @return [String]
    def self.typed_class_block(klass)
      aliases = []
      aliases << failure_code_alias(klass) unless klass.declared_failures.empty?
      aliases << skip_code_alias(klass) unless klass.declared_skips.empty?
      sections = []
      sections << aliases.join("\n") unless aliases.empty?
      sections << "def self.run: #{run_signature(klass, return_type: "(Success | Skipped | Failure)")}"
      sections << output_block(klass.output_schema) if klass.output_schema
      outcome_schemas(klass).each { |name, schema| sections << output_block(schema, name) }
      sections.concat(outcome_blocks(klass))
      "class #{klass.name.split("::").last} < ::Actionable::Action\n#{indent(sections.join("\n\n"))}\nend"
    end
    private_class_method :typed_class_block

    # The nested output class of every skip, then every failure, code that
    # declares an output schema, named after the code.
    #
    # @param klass [Class<Actionable::Action>]
    # @return [Array<Array(String, Class<FieldStruct::Base>)>] name, schema
    def self.outcome_schemas(klass)
      skips = klass.skip_declarations.keys.filter_map do |code|
        schema = klass.skip_output_schema(code)
        ["#{camelize(code)}SkipOutput", schema] if schema
      end
      failures = klass.failure_declarations.keys.filter_map do |code|
        schema = klass.failure_output_schema(code)
        ["#{camelize(code)}FailureOutput", schema] if schema
      end
      skips + failures
    end
    private_class_method :outcome_schemas

    # The +Success+, +Skipped+ and +Failure+ blocks of a typed action.
    #
    # @param klass [Class<Actionable::Action>]
    # @return [Array<String>]
    def self.outcome_blocks(klass)
      names = outcome_schemas(klass).map(&:first)
      skip_outputs = names.grep(/SkipOutput\z/)
      failure_types = names.grep(/FailureOutput\z/) + skip_outputs + (klass.output_schema ? ['Output'] : [])
      [
        outcome_block(klass, 'Success', success_lines(klass)),
        outcome_block(klass, 'Skipped', ["def code: () -> #{code_type(klass.declared_skips, "skip_code")}",
                                         "def output: () -> #{union(skip_outputs)}"]),
        outcome_block(klass, 'Failure', ["def code: () -> #{code_type(klass.declared_failures, "failure_code")}",
                                         "def output: () -> #{union(failure_types)}"])
      ]
    end
    private_class_method :outcome_blocks

    # @param klass [Class<Actionable::Action>]
    # @return [Array<String>] the +Success+ block's signatures
    def self.success_lines(klass)
      schema = klass.output_schema
      lines = ['def code: () -> :success', "def output: () -> #{schema ? "Output" : HASH_OUTPUT}"]
      schema&.metadata&.each { |field| lines << "def #{field.name}: () -> #{rbs_type(field)}" }
      lines
    end
    private_class_method :success_lines

    # @param declared [Hash] the declared codes
    # @param name [String] the alias naming them
    # @return [String] the alias, or +::Symbol+ when none are declared
    def self.code_type(declared, name)
      declared.empty? ? '::Symbol' : name
    end
    private_class_method :code_type

    HASH_OUTPUT = '::Hash[::Symbol, untyped]'
    private_constant :HASH_OUTPUT

    # @param types [Array<String>] the output classes an outcome can carry
    # @return [String] them and a Hash, as one RBS type
    def self.union(types)
      types.empty? ? HASH_OUTPUT : "(#{(types + [HASH_OUTPUT]).join(" | ")})"
    end
    private_class_method :union

    # @param klass [Class<Actionable::Action>]
    # @param name [String] +Success+, +Skipped+ or +Failure+
    # @param lines [Array<String>] the block's method signatures
    # @return [String] the class block, subclassing the parent action's own
    #   result class when the parent has typed outcomes, else the gem's
    def self.outcome_block(klass, name, lines)
      parent = klass.superclass
      base = parent.typed_outcomes? && parent.name ? "::#{parent.name}::#{name}" : "::Actionable::#{name}"
      "class #{name} < #{base}\n#{indent(lines.join("\n"))}\nend"
    end
    private_class_method :outcome_block

    # @param code [Symbol]
    # @return [String] +:already_active+ as +AlreadyActive+
    def self.camelize(code)
      code.to_s.split('_').map(&:capitalize).join
    end
    private_class_method :camelize

    # @param klass [Class<Actionable::Action>]
    # @param return_type [String] what +.run+ returns
    # @return [String] the +.run+ signature: typed kwargs from the input schema
    #   (or +(*untyped)+ free-form), returning the generated +Result+ when an
    #   output schema is declared, else +::Actionable::Result+.
    def self.run_signature(klass, return_type: klass.output_schema ? 'Result' : '::Actionable::Result')
      schema = klass.input_schema
      params = schema ? schema.metadata.map { |field| run_param(field) }.join(', ') : '*untyped'
      "(#{params}) -> #{return_type}"
    end
    private_class_method :run_signature

    # @param klass [Class<Actionable::Action>] an action that declares failures
    # @return [String] the +failure_code+ alias: a union of the declared codes
    #   and the codes the gem emits itself, as Symbol literal types
    def self.failure_code_alias(klass)
      codes = (klass.declared_failures.keys + Actionable::Action::GEM_FAILURE_CODES).uniq
      "type failure_code = #{codes.map(&:inspect).join(" | ")}"
    end
    private_class_method :failure_code_alias

    # @param klass [Class<Actionable::Action>] an action that declares skips
    # @return [String] the +skip_code+ alias: a union of the declared skip codes
    #   as Symbol literal types
    def self.skip_code_alias(klass)
      "type skip_code = #{klass.declared_skips.keys.map(&:inspect).join(" | ")}"
    end
    private_class_method :skip_code_alias

    # @param field [FieldStruct::Field]
    # @return [String] +name: Type+ (required) or +?name: Type+ (optional). The
    #   +?+ prefix carries optionality, so the type itself is not made nullable.
    def self.run_param(field)
      "#{"?" unless field.required?}#{field.name}: #{type_expr(field.type_instance, field.options)}"
    end
    private_class_method :run_param

    # @param schema [Class<FieldStruct::Base>] the output schema
    # @param name [String] the nested class name
    # @return [String] the nested output class block
    def self.output_block(schema, name = 'Output')
      lines = ["class #{name} < ::FieldStruct::Base"]
      schema.metadata.each do |field|
        lines << "  attr_reader #{field.name}: #{rbs_type(field)}"
        lines << "  def #{field.name}=: (untyped value) -> untyped"
      end
      lines << 'end'
      lines.join("\n")
    end
    private_class_method :output_block

    # @param schema [Class<FieldStruct::Base>] the output schema
    # @return [String] the nested +Result+ class block with output delegation
    def self.result_block(schema)
      lines = ['class Result < ::Actionable::Result', '  def output: () -> Output']
      schema.metadata.each { |field| lines << "  def #{field.name}: () -> #{rbs_type(field)}" }
      lines << 'end'
      lines.join("\n")
    end
    private_class_method :result_block

    # @param field [FieldStruct::Field]
    # @return [String] the field's RBS type, made nullable when optional
    def self.rbs_type(field)
      base = type_expr(field.type_instance, field.options)
      field.required? ? base : "#{base}?"
    end
    private_class_method :rbs_type

    # Map a FieldStruct type (plus options, for arrays) to an RBS type — reusing
    # FieldStruct's +ruby_type+ for the field → Ruby class mapping (D13).
    #
    # @param type_instance [FieldStruct::Types::Base]
    # @param options [Hash{Symbol=>Object}]
    # @return [String]
    def self.type_expr(type_instance, options)
      return "::Array[#{element_expr(options[:of_type])}]" if type_instance.is_a?(FieldStruct::Types::Array)

      ruby_type = type_instance.ruby_type
      classes = ruby_type.is_a?(::Array) ? ruby_type : [ruby_type]
      return 'bool' if classes.sort_by(&:name) == BOOL_CLASSES.sort_by(&:name)

      mapped = classes.map { |klass| class_to_rbs(klass) }.uniq
      mapped.one? ? mapped.first : "(#{mapped.join(" | ")})"
    end
    private_class_method :type_expr

    # @param of_type [Class, FieldStruct::Types::Base, nil] an array's element type
    # @return [String]
    def self.element_expr(of_type)
      return 'untyped' if of_type.nil?

      instance = of_type.is_a?(::Class) ? of_type.new : of_type
      type_expr(instance, {})
    end
    private_class_method :element_expr

    # @param klass [Class] a Ruby class from a +ruby_type+
    # @return [String] qualified RBS name, or +untyped+ for the value type's +::Object+
    def self.class_to_rbs(klass)
      return 'untyped' if klass == ::Object

      "::#{klass.name}"
    end
    private_class_method :class_to_rbs

    # Wrap a class block in the +module … end+ nesting implied by its qualified
    # name, indenting two spaces per level.
    #
    # @param full_name [String]
    # @param inner [String]
    # @return [String] RBS source ending in a trailing newline
    def self.wrap_namespace(full_name, inner)
      block = inner
      full_name.split('::')[0...-1].reverse_each { |mod| block = "module #{mod}\n#{indent(block)}\nend" }
      "#{block}\n"
    end
    private_class_method :wrap_namespace

    # @param text [String]
    # @return [String] +text+ with every non-blank line indented two spaces
    def self.indent(text)
      text.split("\n", -1).map { |line| line.empty? ? line : "  #{line}" }.join("\n")
    end
    private_class_method :indent
  end
end
