require 'active_record/associations/join_dependency/join_part'

module ActiveRecord
  module Associations
    class JoinDependency # :nodoc:
      class JoinAssociation < JoinPart # :nodoc:
        # The reflection of the association represented
        attr_reader :reflection

        # What type of join will be generated, either Arel::InnerJoin (default) or Arel::OuterJoin
        attr_accessor :join_type

        # These implement abstract methods from the superclass
        attr_reader :aliased_prefix

        attr_accessor :tables

        delegate :chain, :to => :reflection

        def initialize(reflection, index, join_type)
          super(reflection.klass)

          @reflection      = reflection
          @join_type       = join_type
          @aliased_prefix  = "t#{ index }"
          @tables          = nil
        end

        def match?(other)
          return true if self == other
          super && reflection == other.reflection
        end

        def join_constraints(parent, tables)
          joins         = []
          tables        = tables.dup

          foreign_table = parent.table
          foreign_klass = parent.base_klass

          scope_chain_iter = reflection.scope_chain.reverse_each

          # The chain starts with the target table, but we want to end with it here (makes
          # more sense in this context), so we reverse
          chain.reverse_each do |reflection|
            table = tables.shift
            klass = reflection.klass

            case reflection.source_macro
            when :belongs_to
              key         = reflection.association_primary_key
              foreign_key = reflection.foreign_key
            else
              key         = reflection.foreign_key
              foreign_key = reflection.active_record_primary_key
            end

            constraint = build_constraint(klass, table, key, foreign_table, foreign_key)

            scope_chain_items = scope_chain_iter.next.map do |item|
              if item.is_a?(Relation)
                item
              else
                ActiveRecord::Relation.create(klass, table).instance_exec(self, &item)
              end
            end

            if reflection.type
              scope_chain_items <<
                ActiveRecord::Relation.create(klass, table)
                  .where(reflection.type => foreign_klass.base_class.name)
            end

            scope_chain_items.concat [klass.send(:build_default_scope)].compact

            rel = scope_chain_items.inject(scope_chain_items.shift) do |left, right|
              left.merge right
            end

            if rel && !rel.arel.constraints.empty?
              constraint = constraint.and rel.arel.constraints
            end

            joins << table.create_join(table, table.create_on(constraint), join_type)

            # The current table in this iteration becomes the foreign table in the next
            foreign_table, foreign_klass = table, klass
          end

          joins
        end

        #  Builds equality condition.
        #
        #  Example:
        #
        #  class Physician < ActiveRecord::Base
        #    has_many :appointments
        #  end
        #
        #  If I execute `Physician.joins(:appointments).to_a` then
        #    reflection    #=> #<ActiveRecord::Reflection::AssociationReflection @macro=:has_many ...>
        #    table         #=> #<Arel::Table @name="appointments" ...>
        #    key           #=>  physician_id
        #    foreign_table #=> #<Arel::Table @name="physicians" ...>
        #    foreign_key   #=> id
        #
        def build_constraint(klass, table, key, foreign_table, foreign_key)
          constraint = table[key].eq(foreign_table[foreign_key])

          if klass.finder_needs_type_condition?
            constraint = table.create_and([
              constraint,
              klass.send(:type_condition, table)
            ])
          end

          constraint
        end

        def table
          tables.last
        end

        def aliased_table_name
          table.table_alias || table.name
        end
      end
    end
  end
end
