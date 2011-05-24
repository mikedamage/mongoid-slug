require 'slug/builder'

module Mongoid

  # The slug module helps you generate a URL slug or permalink based on one or
  # more fields in a Mongoid model.
  #
  #    class Person
  #      include Mongoid::Document
  #      include Mongoid::Slug
  #
  #      field :name
  #      slug :name
  #    end
  #
  module Slug
    extend ActiveSupport::Concern

    included do
      cattr_accessor :slug_builder
    end

    module ClassMethods

      # Sets one ore more fields as source of slug.
      #
      # Takes a list of fields to slug and an optional options hash.
      #
      # The options hash respects the following members:
      #
      # * `:as`, which specifies name of the field that stores the slug.
      # Defaults to `slug`.
      #
      # * `:scope`, which specifies a reference association to scope the slug
      # by. Embedded documents are by default scoped by their parent.
      #
      # * `:permanent`, which specifies whether the slug should be immutable
      # once created. Defaults to `false`.
      #
      # * `:index`, which specifies whether an index should be defined for the
      # slug. Defaults to `false` and has no effect if the document is em-
      # bedded.
      #
      # Alternatively, this method can be given a block to build a custom slug
      # out of the specified fields.
      #
      # The block takes a single argument, the document itself, and should
      # return a string that will serve as the base of the slug.
      #
      # Here, for instance, we slug an array field.
      #
      #     class Person
      #      include Mongoid::Document
      #      include Mongoid::Slug
      #
      #      field :names, :type => Array
      #      slug :names do |doc|
      #        doc.names.join(' ')
      #      end
      #
      def slug(*fields, &block)
        options = fields.extract_options!

        self.slug_builder = Builder.new(self).tap do |b|
          b.scope = options[:scope]
          b.name = options[:as] || :slug
          b.fields = fields.map(&:to_s)
          b.rule =
            if block_given?
              block
            else
              lambda { |doc| fields.map { |f| doc.read_attribute(f) }.join }
            end
        end

        field slug_name

        if options[:index]
          index(slug_name, :unique => !slug_scope)
        end

        if options[:permanent]
          before_create :generate_slug
        else
          before_save :generate_slug
        end

        # Build a finder based on the slug name.
        #
        # Defaults to `find_by_slug`.
        instance_eval <<-CODE
          def self.find_by_#{slug_name}(slug)
            where(slug_name => slug).first
          end

          def self.find_by_#{slug_name}!(slug)
            where(slug_name => slug).first ||
              raise(Mongoid::Errors::DocumentNotFound.new(self.class, slug))
          end
        CODE
      end
    end

    # Regenerates slug.
    #
    # Should come in handy when generating slugs for an existing collection.
    def slug!
      generate_slug!
      save
    end

    # Returns the slug.
    def to_param
      read_attribute(slug_builder.name)
    end

    private

    def generate_slug
      generate_slug! if new_record? || slugged_fields_changed?
    end

    def generate_slug!
      write_attribute(slug_name, slug_builder.build)
    end

    def slugged_fields_changed?
      slug_builder.fields.any? { |f| attribute_changed?(f) }
    end
  end
end
