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
  #   which +.run+ returns.
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
      simple = klass.name.split('::').last
      body = ["def self.run: #{run_signature(klass)}"]
      if (schema = klass.output_schema)
        body << ''
        body << output_block(schema)
        body << ''
        body << result_block(schema)
      end
      "class #{simple} < ::Actionable::Action\n#{indent(body.join("\n"))}\nend"
    end
    private_class_method :class_block

    # @return [String] the +.run+ signature: typed kwargs from the input schema
    #   (or +(*untyped)+ free-form), returning the generated +Result+ when an
    #   output schema is declared, else +::Actionable::Result+.
    def self.run_signature(klass)
      schema = klass.input_schema
      params = schema ? schema.metadata.map { |field| run_param(field) }.join(', ') : '*untyped'
      return_type = klass.output_schema ? 'Result' : '::Actionable::Result'
      "(#{params}) -> #{return_type}"
    end
    private_class_method :run_signature

    # @param field [FieldStruct::Field]
    # @return [String] +name: Type+ (required) or +?name: Type+ (optional). The
    #   +?+ prefix carries optionality, so the type itself is not made nullable.
    def self.run_param(field)
      "#{"?" unless field.required?}#{field.name}: #{type_expr(field.type_instance, field.options)}"
    end
    private_class_method :run_param

    # @param schema [Class<FieldStruct::Base>] the output schema
    # @return [String] the nested +Output+ class block
    def self.output_block(schema)
      lines = ['class Output < ::FieldStruct::Base']
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
