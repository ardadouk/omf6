module OmfEc
  class Group
    attr_accessor :name
    attr_accessor :net_context

    def initialize(name)
      self.name = name
    end

    def add_resource(*names, &block)
      names.each do |name|
        OmfEc.comm.subscribe(name) do |m|
          unless m.error?
            if OmfEc.exp.groups.include?(name)
              group(name).resources.membership = self.name
            else
              c = OmfEc.comm.configure_message(self.name) do |m|
                m.property(:membership, self.name)
              end
              c.publish name
              c.on_inform_status do |i|
                info "#{name} added to #{self.name}"
                OmfEc.exp.state << { hrn: name }
                block.call if block
                Experiment.instance.process_events
              end
            end
          end
        end
      end
    end

    def create_resource(name, opts, &block)
      # We create another group topic for new resoruces
      opts = opts.merge(hrn: name)

      # Naming convention of child resource group
      resource_group_name = "#{self.name}_#{opts[:type]}"

      OmfEc.comm.subscribe(resource_group_name, create_if_non_existent: true) do |m|
        unless m.error?
          c = OmfEc.comm.create_message(self.name) do |m|
            m.property(:membership, resource_group_name)
            opts.each_pair do |k, v|
              m.property(k, v)
            end
          end
          c.publish self.name
          c.on_inform_created do |i|
            info "#{opts[:type]} #{i.resource_id} created"
            OmfEc.exp.state << opts.merge(uid: i.resource_id)
            block.call if block
            Experiment.instance.process_events
          end

          rg = OmfEc.comm.get_topic(resource_group_name)
          rg.on_message lambda {|m| m.operation == :inform && m.read_content('inform_type') == 'STATUS' && m.context_id.nil? } do |i|
            r = OmfEc.exp.state.find { |v| v[:uid] == i.read_property(:uid) }
            unless r.nil?
              if i.read_property("status_type") == 'APP_EVENT'
                info "APP_EVENT #{i.read_property('event')} "+
                  "from app #{i.read_property("app")} - msg: #{i.read_property("msg")}"
              end
              i.each_property do |p|
                r[p.attr('key').to_sym] = p.content.ducktype
              end
            end
            Experiment.instance.process_events
          end
        end
      end
    end

    def resources
      GroupContext.new(group: self.name)
    end

    # The following are ODEL 5 methods

    # Create an application for the group and start it
    #
    def exec(name)
      create_resource(name, type: 'application', binary_path: name)
      # FIXME should not assume its ready in 1 second
      after 1.second do
        resources[type: 'application', name: name].state = :run
      end
    end

    # @example
    #   group('actor') do |g|
    #     g.net.w0.ip = '0.0.0.0'
    #     g.net.e0.ip = '0.0.0.1'
    #   end
    def net
      self.net_context ||= NetContext.new(group: self.name)
      self.net_context
      #g.create_resource('wlan0', type: 'wlan')
      #g.resources[name: 'wlan0']
    end
  end
end
