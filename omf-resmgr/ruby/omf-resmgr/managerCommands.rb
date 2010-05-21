#
# Copyright (c) 2006-2009 National ICT Australia (NICTA), Australia
#
# Copyright (c) 2004-2009 WINLAB, Rutgers University, USA
#
# # Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
#
# = ManagerCommands.rb
#
# == Description
#
# This module contains all the commands understood by an agent
# Any change to the sematics of the commands, or the addition
# of new ones should be reflected in a change of the
# PROTOCOL_VERSION.
#

require 'omf-common/mobject'
require 'omf-common/execApp'

module ManagerCommands

  OMF_MM_VERSION = OMF::Common::MM_VERSION()
  
  MAX_CONTAINERS = 100
  @containerIDs = Array.new

  #
  # Command 'CREATE_SLIVER'
  #
  # Create a Sliver on this resource for a given Slice 
  #
  #
  def ManagerCommands.CREATE_SLIVER(controller, communicator, command)
    sliceName = command.slicename
    resourceName = command.resname
    sliverType = command.slivertype
    commAddress = command.commaddr 
    commUser = command.commuser 
    commPassword = command.commpwd
    ctid = 0
    sliver = ""
    
    # Create the sliver ...
    if ResourceManager.instance.config[:manager][:sliver] != nil
      1.upto(MAX_CONTAINERS + 1) { |n|
        break if (ctid != 0)
        if (n == MAX_CONTAINERS + 1)
          MObject.debug("Cannot create more than #{MAX_CONTAINERS} containers. Aborting.")
          return
        end
        if (@containerIDs[n] == nil)
          ctid = n
          sliver = "#{resourceName}_#{n}"
          @containerIDs[n] = sliver
        end
      }
      
      begin
        # TODO: Create pubsub node "/OMF/#{slice}/resources/#{sliver}"
        
        #sliverCmd = ResourceManager.instance.config[:manager][:sliver][sliverType.to_sym] 
        sliverCmd = 'echo 1 > /proc/sys/net/ipv4/ip_forward; vzctl create %CTID% --ostemplate omf-5.3; 
                    vzctl start %CTID%; vzctl set %CTID% --ipadd 10.0.%CTID%.30; 
                    vzctl set %CTID% --nameserver 10.0.0.200; vzctl exec %CTID% ifconfig venet0:0 10.0.%CTID%.30; 
                    vzctl exec %CTID% omf-resctl-5.3 --name %SLIVER_NAME% --slice %SLICE_NAME% &'
        sliverCmd = sliverCmd.gsub(/%CTID%/, "#{ctid}")
        sliverCmd = sliverCmd.gsub(/%SLIVER_NAME%/, sliver)                    
        sliverCmd = sliverCmd.gsub(/%SLICE_NAME%/, sliceName)
        sliverCmd = sliverCmd.gsub(/%RESOURCE_NAME%/, resourceName)
        sliverCmd = sliverCmd.gsub(/%PUBSUB_ADDRESS%/, commAddress)
        sliverCmd = sliverCmd.gsub(/%PUBSUB_USER%/, commUser) if commUser != nil
        sliverCmd = sliverCmd.gsub(/%PUBSUB_PASSWORD%/, commPassword) if commPassword != nil
        MObject.debug("Creating a sliver (type: '#{sliverType}') with cmd: '#{sliverCmd}'") 
        ExecApp.new(sliver, controller, sliverCmd)
        msg = "Created Sliver for slice '#{sliceName}' on '#{resourceName}'"
      rescue Exception => ex
        msg = "Failed creating Sliver for slice '#{sliceName}' on '#{resourceName}' (error: '#{ex}')"
      end
      MObject.debug(msg)
    else
      MObject.debug("Missing :sliver section in config file. Don't know how to create a sliver...")
    end
  end

  #
  # Command 'DELETE_SLIVER'
  #
  # Delete a Sliver on this resource for a given Slice 
  #
  #
  def ManagerCommands.DELETE_SLIVER(controller, communicator, command)
      sliceName = command.slicename
      resourceName = command.resname
      sliverType = command.slivertype
      ctid = @containerIDs.index resourceName
      
      if (ctid = nil)
        MObject.debug("Cannot determine container ID of sliver '#{resourceName}'. Aborting.")
        return
      end

      # Delete the sliver ...
      if ResourceManager.instance.config[:manager][:sliver] != nil
        begin
          #sliverCmd = ResourceManager.instance.config[:manager][:sliver][sliverType.to_sym]           
          sliverCmd = 'vzctl stop %CTID%; vzctl destroy %CTID%'
          sliverCmd = sliverCmd.gsub(/%CTID%/, ctid)
          MObject.debug("Deleting a sliver (type: '#{sliverType}') with cmd: '#{sliverCmd}'") 
          ExecApp.new(resourceName, controller, sliverCmd)
          msg = "Deleted Sliver for slice '#{sliceName}' on '#{resourceName}'"
        rescue Exception => ex
          msg = "Failed deleting Sliver for slice '#{sliceName}' on '#{resourceName}' (error: '#{ex}')"
        end
        MObject.debug(msg)
      else
        MObject.debug("Missing :sliver section in config file. Don't know how to delete a sliver...")
      end
    end

  #
  # Command 'EXECUTE'
  #
  # Execute a program on the machine running this NA
  #
  #
  def ManagerCommands.EXECUTE(controller, communicator, command)
    id = command.appID

    # Dump the XML description of the OML configuration into a file, if any
    if (xmlDoc = command.omlConfig) != nil
      configPath = nil
      xmlDoc.each_element("omlc") { |omlc|
        configPath = "/tmp/#{omlc.attributes['exp_id']}-#{id}.xml"
      }
      f = File.new(configPath, "w+")
      xmlDoc.each_element {|el|
        f << el.to_s
      }
      f.close
    end

    # Set the full command line and execute it
    fullCmdLine = "env -i #{command.env} OML_CONFIG=#{configPath} #{command.path} #{command.cmdLineArgs}"
    MObject.debug "Executing: '#{fullCmdLine}'"
    ExecApp.new(id, controller, fullCmdLine)
  end

  #
  # Command 'KILL'
  #
  # Send a signal to a process running on this node
  #
  #
  def ManagerCommands.KILL(controller, communicator, command)
    id = command.appID
    signal = command.value
    ExecApp[id].kill(signal)
  end

  #
  # Command 'EXIT'
  #
  # Terminate an application running on this node
  # First try to send the message 'exit' on the app's STDIN
  # If no succes, then send a Kill signal to the process
  #
  #
  def ManagerCommands.EXIT(controller, communicator, command)
    id = command.appID
    begin
      # First try sending 'exit' on the app's STDIN
      MObject.debug("Sending 'exit' message to STDIN of application: #{id}")
      ExecApp[id].stdin('exit')
      # If apps still exists after 4sec...
      sleep 4
      if ExecApp[id] != nil
        MObject.debug("Sending 'kill' signal to application: #{id}")
        ExecApp[id].kill('KILL')
      end
    rescue Exception => err
      raise Exception.new("- Error while terminating application '#{id}' - #{err}")
    end
  end

end

# creating a sliver using OpenVZ:
# 
# echo 1 > /proc/sys/net/ipv4/ip_forward
# vzctl create 1 --ostemplate omf-5.3
# vzctl start 1
# vzctl set 1 --ipadd 10.0.1.30
# vzctl set 1 --nameserver 10.0.0.200
# vzctl exec 1 omf-resctl-5.3 --name omf.nicta.node30_1 --slice omf.nicta.slice1 &
# 
# destroy sliver:
# vzctl stop 1
# vzctl destroy 1


# echo 1 > /proc/sys/net/ipv4/ip_forward; vzctl create 1 --ostemplate omf-5.3; vzctl start 1; vzctl set 1 --ipadd 10.0.1.30; vzctl set 1 --nameserver 10.0.0.200; vzctl exec 1 omf-resctl-5.3 --name omf.nicta.node30_1 --slice omf.nicta.slice1 &

