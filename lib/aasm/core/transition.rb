module AASM::Core
  class Transition
    include DslHelper

    attr_reader :from, :to, :event, :opts, :failures
    alias_method :options, :opts

    def initialize(event, opts, &block)
      add_options_from_dsl(opts, [:on_transition, :guard, :after], &block) if block

      @event = event
      @from = opts[:from]
      @to = opts[:to]
      @guards = Array(opts[:guards]) + Array(opts[:guard]) + Array(opts[:if])
      @unless = Array(opts[:unless]) #TODO: This could use a better name
      @failures = []

      if opts[:on_transition]
        warn '[DEPRECATION] :on_transition is deprecated, use :after instead'
        opts[:after] = Array(opts[:after]) + Array(opts[:on_transition])
      end
      @after = Array(opts[:after])
      @after = @after[0] if @after.size == 1

      @opts = opts
    end

    def allowed?(obj, *args)
      invoke_callbacks_compatible_with_guard(@guards, obj, args, :guard => true) &&
      invoke_callbacks_compatible_with_guard(@unless, obj, args, :unless => true)
    end

    def execute(obj, *args)
      invoke_callbacks_compatible_with_guard(event.state_machine.global_callbacks[:after_all_transitions], obj, args)
      invoke_callbacks_compatible_with_guard(@after, obj, args)
    end

    def ==(obj)
      @from == obj.from && @to == obj.to
    end

    def from?(value)
      @from == value
    end

    private

    def invoke_callbacks_compatible_with_guard(code, record, args, options={})
      if record.respond_to?(:aasm)
        record.aasm(event.state_machine.name).from_state = @from if record.aasm(event.state_machine.name).respond_to?(:from_state=)
        record.aasm(event.state_machine.name).to_state = @to if record.aasm(event.state_machine.name).respond_to?(:to_state=)
      end

      case code
      when Symbol, String
        result = (record.__send__(:method, code.to_sym).arity == 0 ? record.__send__(code) : result = record.__send__(code, *args))
        failures << code unless result
        result
      when Proc
        if code.respond_to?(:parameters)
          # In Ruby's Proc, the 'arity' method is not a good condidate to know if
          # we should pass the arguments or not, since its does return 0 even in
          # presence of optional parameters.
          result = (code.parameters.size == 0 ? record.instance_exec(&code) : record.instance_exec(*args, &code))
        else
          # In RubyMotion's Proc, the parameter method does not exists, however its
          # 'arity' method works just like the one from Method, only returning 0 when
          # there is no parameters whatsoever, optional or not.
          result = (code.arity == 0 ? record.instance_exec(&code) : record.instance_exec(*args, &code))
        end

        failures << code.source_location.join('#') unless result
        result
      when Array
        if options[:guard]
          # invoke guard callbacks
          code.all? {|a| invoke_callbacks_compatible_with_guard(a, record, args)}
        elsif options[:unless]
          # invoke unless callbacks
          code.all? {|a| !invoke_callbacks_compatible_with_guard(a, record, args)}
        else
          # invoke after callbacks
          code.map {|a| invoke_callbacks_compatible_with_guard(a, record, args)}
        end
      else
        true
      end
    end

  end
end # AASM
