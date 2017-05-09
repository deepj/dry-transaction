require "dry/transaction/step_adapters"
require "dry/transaction/result_matcher"

module Dry
  class Transaction
    class Builder < Module
      attr_reader :container
      attr_reader :step_adapters
      attr_reader :matcher

      attr_reader :class_mod
      attr_reader :instance_mod

      def initialize(container: nil, step_adapters: StepAdapters, matcher: ResultMatcher)
        @container = container
        @step_adapters = step_adapters
        @matcher = matcher

        @class_mod = define_class_mod
        # @instance_mod = InstanceMethods.new
      end

      def included(klass)
        klass.extend(class_mod)
        klass.send(:include, InstanceMethods)
      end

      def define_class_mod
        # Capture local vars to use in closure (FIXME: this doesn't feel nice)
        container = self.container
        step_adapters = self.step_adapters

        Module.new do
          def steps
            @steps ||= []
          end

          step_adapters.keys.each do |adapter_name|
            define_method(adapter_name) do |step_name, with: nil, **options, &block|
              operation = if container
                operation_name = with || step_name
                # TODO: probably need to allow this next line to fail still, given we support local methods for operations
                container[operation_name]
              end

              steps << Step.new(
                step_adapters[adapter_name],
                step_name,
                operation,
                options,
                &block
              )
            end
          end
        end
      end

      # module ClassMethods
      #   def steps
      #     @steps ||= []
      #   end
      # end

      # class ClassMethods < Module
      #   # attr_reader :steps

      #   # def initialize(*)
      #   #   @steps = steps
      #   #   super
      #   # end

      #   # def included(klass)
      #   #   klass.class_eval do
      #   #   end
      #   # end

      #   def steps
      #     @steps ||= []
      #   end
      # end

      module InstanceMethods
        def initialize(**options)
          # TODO: support injecting step operations
          # Should this actually be an instance method? Might be better if we pre-pended an `#initialize` that resolved _all_ steps from the container (if present)
        end

        def call(input)
          self.class.steps.inject(Dry::Monads.Right(input)) { |input, step|
            input.bind { |value|
              step = step.with_operation(method(step.step_name))
              step.(value)
            }
          }
        end

        def respond_to_missing?(name, _include_private = false)
          self.class.steps.any? { |step| step.step_name == name }
        end

        def method_missing(name, *args, &block)
          step = self.class.steps.detect { |step| step.step_name == name }
          super unless step

          if step.operation
            step.operation.(*args, &block)
          else
            raise NotImplementedError, "no operation defined for step +#{step.step_name}+"
          end
        end
      end
    end
  end
end
