module GmailBritta
  class FilterSet
    def initialize(opts={})
      @filters = []
      @me = opts[:me] || 'me'
      @logger = opts[:logger] || allocate_logger
      @author = opts[:author] || {}
      @author[:name] ||= "Andreas Fuchs"
      @author[:email] ||= "asf@boinkor.net"
    end

    # Currently defined filters
    # @see Delegate#filter
    # @see GmailBritta::Filter#otherwise
    # @see GmailBritta::Filter#also
    # @see GmailBritta::Filter#archive_unless_directed
    attr_accessor :filters

    attr_accessor :labels

    # The list of emails that belong to the user running this {FilterSet} definition
    # @see GmailBritta.filterset
    attr_accessor :me

    # The logger currently being used for debug output
    # @see GmailBritta.filterset
    attr_accessor :logger

    # Run the block that defines the filters in {Delegate}'s `instance_eval`. This method will typically only be called by {GmailBritta.filterset}.
    # @api private
    # @yield the filter definition block in {Delegate}'s instance_eval.
    def rules(&block)
      Delegate.new(self, :logger => @logger).perform(&block)
    end

    # Generate ATOM XML for the defined filter set and return it as a String.
    # @return [String] the generated XML, ready for importing into Gmail.
    def generate
      engine = Haml::Engine.new(<<-ATOM)
!!! XML
%feed{:xmlns => 'http://www.w3.org/2005/Atom', 'xmlns:apps' => 'http://schemas.google.com/apps/2006'}
  %title Mail Filters
  %id tag:mail.google.com,2008:filters:
  %updated #{Time.now.utc.iso8601}
  %author
    %name #{@author[:name]}
    %email #{@author[:email]}
  - filters.each do |filter|
    != filter.generate_xml
ATOM
      engine.render(self)
    end

    # A class whose sole purpose it is to be the `self` in a {FilterSet} definition block.
    class Delegate

      # @api private
      def initialize(britta, options={})
        @britta = britta
        @log = options[:logger]
        @filter = nil
      end

      # Create, register and return a new {Filter} without any merged conditions
      # @yield [] the {Filter} definition block, with the new {Filter} instance as `self`.
      # @return [Filtere] the new filter.
      def filter(&block)
        GmailBritta::Filter.new(@britta, :log => @log).perform(&block)
      end

      def labels(labels)
        @britta.labels = labels
      end

      # Evaluate the {FilterSet} definition block with the {Delegate} object as `self`
      # @api private
      # @note this method will typically only be called by {FilterSet#rules}
      # @yield [ ] that filterset definition block
      def perform(&block)
        instance_eval(&block)
      end
    end

    def to_json
      result = {
        version: "v1alpha3",
        author: {
          name: "YOUR NAME HERE (auto imported)",
          email: "your-email@gmail.com"
        }
      }
      labels = @labels
      rules = []

      filters.each do |filter|
        rule = filter.to_hash
        if rule[:actions] and rule[:actions]["labels"]
          labels += rule[:actions]["labels"]
        end
        rules << rule
      end

      unless labels.empty?
        result[:labels] =
          labels
          .sort
          .uniq
          .map do |name|
            {:name => name}
          end
      end

      unless rules.empty?
        result[:rules] = rules
      end

      JSON.pretty_generate(result)
    end

    private
    def allocate_logger
      logger = Logger.new(STDERR)
      logger.level = Logger::WARN
      logger
    end
  end
end
