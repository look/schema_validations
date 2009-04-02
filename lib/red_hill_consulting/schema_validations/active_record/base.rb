module RedHillConsulting::SchemaValidations::ActiveRecord
  module Base
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def self.extended(base)
        class << base
          alias_method_chain :allocate, :schema_validations
          alias_method_chain :new, :schema_validations
        end
      end

      def inherited(child)
        load_schema_validations unless self == ActiveRecord::Base
        super
      end

      def schema_validations(options = {})
        return unless table_exists?
        
        column_names = []
        if options[:only]
          column_names = options[:only]
          @schema_validations_column_include = true
        elsif options[:except]
          column_names = options[:except]
          @schema_validations_column_include = false
        else
          # if neither only nor except is provided, include all columns
          column_names = content_columns.map(&:name)
          @schema_validations_column_include = true
        end
        
        @schema_validations_options = Array(options[:validate] || [:data_type, :unique, :not_null])

        @schema_validations_column_names = Array(column_names).map(&:to_s)
      end

      def allocate_with_schema_validations
        load_schema_validations
        allocate_without_schema_validations
      end

      def new_with_schema_validations(*args)
        load_schema_validations
        new_without_schema_validations(*args) { |*block_args| yield(*block_args) if block_given? }
      end

      protected

      def load_schema_validations
        # Don't bother if: it's already been loaded; the class is abstract; not a base class; or the table doesn't exist
        return if @schema_validations_loaded || abstract_class? || !base_class? || name.blank? || !table_exists?
        @schema_validations_loaded = true
        load_column_validations
        load_association_validations
      end

      private
      
      def load_column_validations
        content_columns.each do |column|
          next unless validates?(column)

          add_data_type_validations(column) if validates_data_type?
          
          add_not_null_validations(column) if validates_not_null?
          
          add_unique_validations(column) if validates_uniqueness?
        end
      end
      
      
      def add_data_type_validations(column)
        name = column.name.to_sym
        
        if column.type == :integer
          validates_numericality_of name, :allow_nil => true, :only_integer => true
        elsif column.type == :decimal
          max_decimal = (10 ** (column.precision - column.scale)) - (1.0/(10 ** column.scale))

          validates_numericality_of name, :allow_nil => true, :less_than => max_decimal, :greater_than => -max_decimal
        elsif column.number?
          validates_numericality_of name, :allow_nil => true
        elsif column.text? && column.limit
          validates_length_of name, :allow_nil => true, :maximum => column.limit
        end
      end
      
      def add_not_null_validations(column)
        name = column.name.to_sym
        
        if column.required_on
          # Work-around for a "feature" of the way validates_presence_of handles boolean fields
          # See http://dev.rubyonrails.org/ticket/5090 and http://dev.rubyonrails.org/ticket/3334
          if column.type == :boolean
            validates_inclusion_of name, :on => column.required_on, :in => [true, false], :message => I18n.translate('activerecord.errors.messages.blank')
          else
            validates_presence_of name, :on => column.required_on
          end
        end
      end
      
      def add_unique_validations(column)
        name = column.name.to_sym
        
        validates_uniqueness_of name, \
                                :scope => column.unique_scope.map(&:to_sym), \
                                :allow_nil => true, \
                                :case_sensitive => column.case_sensitive?, \
                                :if => "#{name}_changed?".to_sym \
                                if column.unique?
      end
      
      def load_association_validations
        columns = columns_hash
        reflect_on_all_associations(:belongs_to).each do |association|
          column = columns[association.primary_key_name]
          next unless validates?(column)

          # NOT NULL constraints
          module_eval(
            "validates_presence_of :#{column.name}, :on => :#{column.required_on}, :if => lambda { |record| record.#{association.name}.nil? }"
          ) if column.required_on

          # UNIQUE constraints
          validates_uniqueness_of column.name.to_sym, \
                                  :scope => column.unique_scope.map(&:to_sym), \
                                  :allow_nil => true, \
                                  :if => "#{column.name}_changed?".to_sym \
                                  if column.unique?
        end
      end

      def validates?(column)
        column.name !~ /^(((created|updated)_(at|on))|position)$/ &&
          (@schema_validations_column_names.nil? || @schema_validations_column_names.include?(column.name) == @schema_validations_column_include)
      end
      
      def validates_data_type?
        @schema_validations_options.nil? || @schema_validations_options.include?(:data_type)
      end
      
      def validates_uniqueness?
        @schema_validations_options.nil? || @schema_validations_options.include?(:unique)
      end
      
      def validates_not_null?
        @schema_validations_options.nil? || @schema_validations_options.include?(:not_null)
      end
    end
  end
end
