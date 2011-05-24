require 'stringex'

module Mongoid
  module Slug
    class Builder
      # A list of fields to slug.
      attr_accessor :fields

      # The name of the field that stores the slug.
      attr_accessor :name

      # A proc that builds the base of the slug.
      attr_accessor :rule


      # A reference association to scope the slug by.
      attr_accessor :scope

      def initialize(doc)
        @doc = doc
      end

      def base
        rule.call(self).to_url
      end

      # Returns a unique slug.
      #
      # It will append a counter if the slug has already been used by another
      # document.
      def slug
        base + counter_or_nil
      end

      def counter_or_nil
        if last_duplicate_slug
          "-#{$1.to_i + 1}"
        end.to_s
      end

      def last_duplicate_slug
        unique.only(slug_name).
          where(slug_name => pattern, :_id.ne => _id).
          map { |doc| doc.try(:read_attribute, slug_name) }.
          sort_by { |doc| slug_pattern_for(slug).match(doc)[1].to_i }.
          last
      end

      # A regular expression that matches the slug, with an optional counter
      # appended with a dash.
      #
      # If slugged field is indexed, MongoDB will utilize that index to match
      # the pattern.
      def pattern
        /^#{Regexp.escape(@slug)}(?:-(\d+))?$/
      end

      def unique
        if scope
          metadata = @doc.class.reflect_on_association(scope)
          parent = @doc.send(metadata.name)

          # Make sure doc is actually associated with something, and that some
          # referenced docs have been persisted to the parent
          #
          # TODO: we need better reflection for reference associations, like
          # association_name instead of forcing collection_name here -- maybe
          # in the forthcoming Mongoid refactorings?
          inverse = metadata.inverse_of || @doc.collection_name
          parent.respond_to?(inverse) ? parent.send(inverse) : self.class
        elsif @doc.embedded?
          parent_metadata = @doc.reflect_on_all_associations(:embedded_in).first
          @doc._parent.send(parent_metadata.inverse_of || @doc.metadata.name)
        else
          appropriate_class = @doc.class
          while (appropriate_class.superclass.include?(Mongoid::Document))
            appropriate_class = appropriate_class.superclass
          end
          appropriate_class
        end
      end
    end
  end
end
