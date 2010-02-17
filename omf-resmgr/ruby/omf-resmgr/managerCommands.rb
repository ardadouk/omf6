#
# Copyright (c) 2006-2009 National ICT Australia (NICTA), Australia
#
# Copyright (c) 2004-2009 WINLAB, Rutgers University, USA
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
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
# = agentCommands.rb
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
#require 'omf-resctl/omf_driver/aironet'
require 'omf-resctl/omf_driver/ethernet'

module AgentCommands

  # Version of the communication protocol between the EC and the NAs
  PROTOCOL_VERSION = "4.2"
  
  OMF_MM_VERSION = OMF::Common::MM_VERSION()

  # TODO:
  # For GEC4 demo we use these Constant values.
  # When we will integrate a virtualization scheme, coupled with a 
  # Resource Manager (RM) and a Resource Controller (RC), we might want to have these
  # config values passed as parameters (i.e. different RC in different sliver might
  # need different configs). This will probably depend on the selected virtualization scheme 
  #
  # Slave Resource Controller (aka NodeAgent)
  SLAVE_RESCTL_ID = "SLAVE-RESOURCE-CTL"
  SLAVE_RESCTL_LISTENIF = "lo" # Slave Agent listens only on localhost interface
  SLAVE_RESCTL_LISTENPORT = 9026
  SLAVE_RESCTL_CMD = "sudo /usr/sbin/omf-resctl-#{OMF_MM_VERSION}"
  SLAVE_RESCTL_LOG = "/etc/omf-resctl-#{OMF_MM_VERSION}/nodeagentSlave_log.xml"
  # Slave Experimet Controller (aka NodeHandler)
  SLAVE_EXPCTL_ID = "SLAVE-EXP-CTL"
  SLAVE_EXPCTL_CMD = "/usr/bin/omf-#{OMF_MM_VERSION} exec"
  SLAVE_EXPCTL_CFG = "/etc/omf-expctl-#{OMF_MM_VERSION}/nodehandlerSlave.yaml"
  # Proxy OML Collection Server
  OML_PROXY_ID = "PROXY-OML-SERVER"
  OML_PROXY_CMD = "/usr/bin/oml2-proxy-server"
  OML_PROXY_LISTENPORT = "8002"
  OML_PROXY_LISTENADDR = "localhost"
  OML_PROXY_CACHE = "/tmp/temp-proxy-cache"
  OML_PROXY_LOG = "/tmp/temp-proxy-log"
  
  # Mapping between OMF's device name and Linux's device name
  DEV_MAPPINGS = {
    'net/e0' => EthernetDevice.new('net/e0', 'exp0'),
    'net/e1' => EthernetDevice.new('net/e1', 'exp1'),
    #'net/w2' => AironetDevice.new('net/w2', 'exp2')
  }

  # Code Version of this NA
  VERSION = "$Revision: 1273 $".split(":")[1].chomp("$").strip
  SYSTEM_ID = :system

  # 
  # Return the Application ID for the OML Proxy Collection Server
  # (This is only set when NA is involved in an experiment that support
  # temporary disconnection of node/resource from the Control Network)
  #
  # [Return] an Application ID (String)
  #
  def AgentCommands.omlProxyID
    return OML_PROXY_ID
  end

  # 
  # Return the Application ID for the 'slave' Experiment Controller (aka 
  # NodeHandler) running on this node/resource.
  # (This is only set when NA is involved in an experiment that support
  # temporary disconnection of node/resource from the Control Network)
  #
  # [Return] an Application ID (String)
  #
  def AgentCommands.slaveExpCtlID
    return SLAVE_EXPCTL_ID
  end

  # Command 'REMOVE_TRAFFICRULES'
  #
  # Remove a traffic rule and the filter attached. It not destroys the main class which hosts the rule
  # - values = values needed to delete a rule an a filter : the Id, and all parameters of the filter
  #
 
  def AgentCommands.REMOVE_TRAFFICRULES(agent , argArray)
    #check if the tool is available (Currently, only TC)
    if (!File.exist?("/sbin/tc"))
      raise "Traffic shaping method not available in 'SET_TRAFFICRULES'"
    else
      ipDst= getArg(argArray, "value of the destination IP")
      portDst=getArg(argArray, "value of the port for filter based on port")
      portRange=getArg(argArray, "Range for filtering by port")
      nbRules = getArg(argArray , "Number of rules")
      portRange = portRange.to_i
      portRange = 65535 - portRange
      portRange = portRange.to_s(16)
      #Rule deletion.
      cmdDelRule ="tc qdisc del dev eth0 parent 1:1#{nbRules} handle #{nbRules}0: ; tc qdisc add dev eth0 parent #{nbRules}0:1 handle #{nbRules}01: "
      MObject.debug "Exec: '#{cmdDelRule}'"
      result=`#{cmdDelRule}`
      #Filter deletion
      if(portDst!="-1")
        cmdFilter= "tc filter del dev eth0 protocol ip parent 1:0 prio 3 u32 match ip protocol 17 0xff match ip dport #{portDst} 0x#{portRange} match ip dst #{ipDst} flowid 1:1#{nbRules}"
      else
        cmdFilter= " tc filter del dev eth0 protocol ip parent 1:0 prio 3 u32 match ip dst #{ipDst} flowid 1:1#{nbRules}"
      end
      MObject.debug "Exec: '#{cmdFilter}'"
      result=`#{cmdFilter}`
    end
  end

    #  Command 'SET_TRAFFICRULES'
    #  Add a traffic shaping rules between the node src and the destination and specify a filter either on @dst either on @dst and destination port.
    #  - values = all the values to set the rules. values =[ipDst,delay,delayvar,delayCor,loss,lossCor,bw,bwBuffer,bwLimit,per,duplication,portDst,portRange,rulesId]
    #

  def AgentCommands.SET_TRAFFICRULES(agent , argArray)
    #check if the tool is available (Currently, only TC)
    if (!File.exist?("/sbin/tc"))
      raise "Traffic shaping method not available in 'SET_TRAFFICRULES'"
    else
      ipDst=getArg(argArray, "@ip dst")
      delay=getArg(argArray, "value of the delay. -1=not set")
      delayVar=getArg(argArray, "Value of the delay variation")
      delayCor=getArg(argArray, "Value of the delay correlation")
      loss=getArg(argArray, "value of the loss")
      lossCor=getArg(argArray, "value of the loss correlation")
      bw=getArg(argArray, "value of the bandwidth")
      bwBuffer=getArg(argArray, "value of the buffer for TBf")
      bwLimit=getArg(argArray, "value of the limit for TBF")
      per=getArg(argArray, "value of the packet error rate")
      duplication=getArg(argArray, "value of the duplication")
      portDst=getArg(argArray, "value of the port for filter based on port")
      portRange=getArg(argArray, "Range for filtering by port")
      protocol=getArg(argArray, "TCP or UDP")
      interface = getArg(argArray, "interface to apply the rules")
      nbRules = getArg(argArray , "Number of rules")
      nbRules = nbRules.to_i
      nbRules = nbRules + 1
      portRange = portRange.to_i
      portRange = 65535 - portRange
      portRange = portRange.to_s(16)
      #values to check that either netem or tbf are in use (no empty rule)
      netem = 0
      tbf = 0
      if (nbRules==2)
        cmdMainPipe = "tc qdisc del dev eth0 root ; tc qdisc add dev eth0 handle 1: root htb ; tc class add dev eth0 parent 1: classid 1:1 htb rate 1000Mbps "
        MObject.debug "Exec: '#{cmdMainPipe}'"
        result=`#{cmdMainPipe}`
      end
      #Creation of netem parameters part
      parameters ="netem "
      puts "delay #{delay}"
      if (delay != "-1")
        netem = 1
        parameters = parameters + "delay #{delay}"
        if (delayVar != "-1")
          parameters = parameters + " #{delayVar}"
          if (delayCor != "-1")
            parameters = parameters + " #{delayCor}"
          end
        end
      end
      if (loss!= "-1")
        netem = 1
        parameters = parameters + " loss #{loss}"
        if (lossCor != "-1")
          parameters = parameters +" #{lossCor}"
        end
      end
      if (per != "-1")
        netem = 1
        parameters = parameters + " corrupt #{per}"
      end
      if (duplication != "-1")
        netem = 1
        parameters = parameters + " duplicate #{duplication}"
end
      #Only tbf in the rule
      if(bw != "-1"  and netem == 0)
        tbf = 1
        parametersTbf = "tbf rate #{bw} buffer #{bwBuffer} limit #{bwLimit}"
          cmdRule = "tc class add dev #{interface} parent 1:1 classid 1:1#{nbRules} htb rate 1000Mbps ; tc qdisc add dev eth0 parent 1:1#{nbRules} handle #{nbRules}0: #{parametersTbf}"
          MObject.debug "Exec: '#{cmdRule}'"
          result=`#{cmdRule}`
      #Bw AND Netem Stuff
      elsif (bw != "-1" and netem == 1)
        tbf = 1
        parametersTbf = "tbf rate #{bw} buffer #{bwBuffer} limit #{bwLimit}"
        cmdRule = "tc class add dev #{interface} parent 1:1 classid 1:1#{nbRules} htb rate 1000Mbps ; tc qdisc add dev eth0 parent 1:1#{nbRules} handle #{nbRules}0: #{parameters} ; tc qdisc add dev eth0 parent #{nbRules}0:1 handle #{nbRules}01: #{parametersTbf}"
        MObject.debug "Exec: '#{cmdRule}'"
        result=`#{cmdRule}`
      elsif (bw == "-1" and netem == 1)
        cmdRule = "tc class add dev #{interface} parent 1:1 classid 1:1#{nbRules} htb rate 1000Mbps ; tc qdisc add dev eth0 parent 1:1#{nbRules} handle #{nbRules}0: #{parameters}"
        MObject.debug "Exec: '#{cmdRule}'"
        result=`#{cmdRule}`
      end
      if(tbf != 0 or netem != 0)
        if(portDst!="-1")
          cmdFilter= "tc filter add dev #{interface} protocol ip parent 1:0 prio 3 u32 match ip protocol #{protocol} 0xff match ip dport #{portDst} 0x#{portRange} match ip dst #{ipDst} flowid 1:1#{nbRules}"
        else
          cmdFilter= " tc filter add dev #{interface} protocol ip parent 1:0 prio 3 u32 match ip dst #{ipDst} flowid 1:1#{nbRules}"
        end
      end
      MObject.debug "Exec: '#{cmdFilter}'"
      result=`#{cmdFilter}`
      agent.okReply(:SET_TRAFFICRULES)
    end
  end

  #
  # Command 'SET_MACTABLE'
  #
  # Add a given MAC address to the MAC filtering table of 
  # this node. Any frames from this MAC address will be dropped
  #
  # - agent = the instance of this NA
  # - cmdToUse = which filtering tool to use, supported options are 'iptable' or 'ebtable' or 'mackill'
  # - mac = MAC address to block
  #
  def AgentCommands.SET_MACTABLE(agent, argArray)
    # retrieve arguments
    cmdToUse = getArg(argArray, "MAC Filtering Command to Use")
    macToBlock = getArg(argArray, "MAC Address to Block")
    # Current madwifi change first octet from 00 to 06 when using 'wlanconfig create' at Winlab
    # Fix that by blocking it as well.
    macToBlockBis = "06:"+macToBlock.slice(3..-1)
    # retrieve command line to execute in order to block this MAC addr.
    case cmdToUse
      when "iptable"
	cmd = "iptables -A INPUT -m mac --mac-source #{macToBlock} -j DROP ; iptables -A INPUT -m mac --mac-source #{macToBlockBis} -j DROP"
        cmd2 = ''
      when "ebtable"
	cmd = "ebtables -A INPUT --source #{macToBlock} -j DROP ; ebtables -A INPUT --source #{macToBlockBis} -j DROP"
        cmd2 = ''
      when "mackill"
	cmd = "echo - #{macToBlock} > /proc/net/mackill ; echo - #{macToBlockBis} > /proc/net/mackill" 
        cmd2 = "sudo chmod 666 /proc/net/mackill ; echo \"-#{macToBlock}\">/proc/net/mackill ; echo \"-#{macToBlockBis}\">/proc/net/mackill"
      else 
        MObject.error "SET_MACTABLE - Unknown command to use: #{cmdToUse}"
	agent.errorReply(:SET_MACTABLE, agent.agentName, "Unsupported command: #{cmdToUse}")
	return
    end
    # execute the command...
    MObject.debug "Exec: '#{cmd}'"
    result=`#{cmd}`
    # check if all went well
    if ! $?.success?
      # if not, and if an alternate method was set, try again with the alternate one
      if (cmd2 != '')
        MObject.error "SET_MACTABLE - Trying again using alternate cmd: #{cmd2}"
        MObject.debug "Exec: '#{cmd2}'"
        result=`#{cmd2}`
      end
      # check if all went well - Report error only for original cmd
      if ! $?.success?
        MObject.error "SET_MACTABLE - Error executing cmd: #{cmd}"
        agent.errorReply(:SET_MACTABLE, agent.agentName, "Executing cmd: '#{cmd}'")
	return
      end
    end
    agent.okReply(:SET_MACTABLE)
  end

  #
  # Command 'ALIAS'
  #
  # Set additional alias names for this node
  #
  # - agent = the instance of this NA
  # - cmdObject = a Command Object holding all the information required to 
  #               execute this command 
  #
  def AgentCommands.ALIAS(agent, cmdObject)
    aliasArray = cmdObject.name.split(' ')
    aliasArray.each{ |n|
      agent.addAlias(n)
    }
    agent.enrollReply(cmdObject.name)
  end

  #
  # Command 'YOUARE'
  # 
  # Initial enroll message received from the EC
  #
  # - agent = the instance of this NA
  # - cmdObject = a Command Object holding all the information required to 
  #               execute this command
  #
  def AgentCommands.ENROLL(agent, cmdObject)

    # Check if we are already 'enrolled' or not
    if agent.enrolled
      MObject.debug "Resource Controller already enrolled! - ignoring this ENROLL command!"
      return
    end
    # Check if the desired image is installed on that node, 
    # if yes or if a desired image is not required, then continue
    # if not, then ignore this YOUARE
    desiredImage = cmdObject.image
    if (desiredImage != agent.imageName() && desiredImage != '*')
      MObject.debug "Requested Image: '#{desiredImage}' - Current Image: '#{NodeAgent.instance.imageName()}'"
      agent.wrongImageReply()
      return
    end
    # All is good, enroll this Resource Controller
    agent.enrolled = true
    agent.enrollReply()
  end

  #
  # Command 'SET_DISCONNECT'
  # 
  # Activate the 'Disconnection Mode' for this NA. In this mode, this NA will assume
  # the role of a 'master' NA. It will fetch a copy of the experiment description from
  # the main 'master' EC. Then it will execute a Proxy OML server, a 'slave' NA and
  # a 'slave' EC. Finally, it will monitor the 'slave' EC, and upon its termination, 
  # it will initiate the final measurement collection (OML proxy to OML server), and
  # the end of the experiment.
  #
  # - agent = the instance of this NA
  # - argArray = an array with the following parameters: the experiment ID, the URL
  #              from where to get the experiment description, the address of the 
  #              OML Server, the port of the OML server
  #
  def AgentCommands.SET_DISCONNECT(agent, argArray)
    agent.allowDisconnection = true
    MObject.debug "Disconnection Support Enabled."
    
    # Fetch the Experiment ID from the EC
    expID = getArg(argArray, "Experiment ID")

    # Fetch the Experiment Description from the EC
    ts = DateTime.now.strftime("%F-%T").split(%r{[:-]}).join('_')
    urlED = getArg(argArray, "URL for Experiment Description")
    fileName = "/tmp/exp_#{ts}.rb"
    MObject.debug("Fetching Experiment Description at '#{urlED}'")
    if (! system("wget -m -nd -q -O #{fileName} #{urlED}"))
      raise "Couldn't fetch Experiment Description at:' #{urlED}'"
    end
    MObject.debug("Experiment Description saved at: '#{fileName}'")

    # Fetch the addr:port of the OML Collection Server from the EC
    addrMasterOML = getArg(argArray, "Address of Master OML Server")
    portMasterOML = getArg(argArray, "Port of Master OML Server")

    # Now Start a Proxy OML Server
    cmd = "#{OML_PROXY_CMD} --listen #{OML_PROXY_LISTENPORT} \
                            --dstport #{portMasterOML} \
                            --dstaddress #{addrMasterOML}\
                            --resultfile #{OML_PROXY_CACHE} \
                            --logfile #{OML_PROXY_LOG}"
    MObject.debug("Starting OML Proxy Server with: '#{cmd}'")
    ExecApp.new(OML_PROXY_ID, agent, cmd)

    # Now Start a Slave NodeAgent with its communication module in 'TCP Server' mode
    # Example: sudo /usr/sbin/omf-resctl --server-port 9026 --local-if lo --log ./nodeagentSlave_log.xml
    cmd = "#{SLAVE_RESCTL_CMD}  --server-port #{SLAVE_RESCTL_LISTENPORT} \
                                --local-if #{SLAVE_RESCTL_LISTENIF} \
                                --log #{SLAVE_RESCTL_LOG}"
    MObject.debug("Starting Slave Resouce Controller (NA) with: '#{cmd}'")
    ExecApp.new(SLAVE_RESCTL_ID, agent, cmd)
    
    # Now Start a Slave NodeHandler with its communication module in 'TCP Client' mode
    cmd = "#{SLAVE_EXPCTL_CMD} --config #{SLAVE_EXPCTL_CFG} \
                               --slave-mode #{expID} \
                               --slave-mode-omlport #{OML_PROXY_LISTENPORT} \
                               --slave-mode-omladdr #{OML_PROXY_LISTENADDR} \
                               --slave-mode-xcoord #{agent.x} \
                               --slave-mode-ycoord #{agent.y} \
                               #{fileName}"
    MObject.debug("Starting Slave Experiment Controller (EC) with: '#{cmd}'")
    ExecApp.new(SLAVE_EXPCTL_ID, agent, cmd)
    
  end

  #
  # Command 'EXECUTE'
  #
  # Execute a program on the machine running this NA
  #
  # - agent = the instance of this NA
  # - cmdObject = a Command Object holding all the information required to 
  #               execute this command 
  #
  def AgentCommands.EXECUTE(agent, cmdObject)
    id = cmdObject.appID

    # Dump the XML description of the OML configuration into a file, if any
    if (xmlDoc = cmdObject.omlConfig) != nil
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
    fullCmdLine = "env -i #{cmdObject.env} OML_CONFIG=#{configPath} #{cmdObject.path} #{cmdObject.cmdLineArgs}"
    MObject.debug "Executing: '#{fullCmdLine}'"
    ExecApp.new(id, agent, fullCmdLine)
  end

  #
  # Command 'KILL'
  #
  # Send a signal to a process running on this node
  #
  # - agent = the instance of this NA
  # - cmdObject = a Command Object holding all the information required to 
  #               execute this command
  #
  def AgentCommands.KILL(agent, cmdObject)
    id = cmdObject.appID
    signal = cmdObject.value
    ExecApp[id].kill(signal)
  end

  #
  # Command 'EXIT'
  #
  # Terminate an application running on this node
  # First try to send the message 'exit' on the app's STDIN
  # If no succes, then send a Kill signal to the process
  #
  # - agent = the instance of this NA
  # - cmdObject = a Command Object holding all the information required to 
  #               execute this command
  #
  def AgentCommands.EXIT(agent, cmdObject)
    id = cmdObject.appID
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

  #
  # Command 'STDIN'
  #
  # Send a line of text to the STDIN of a process
  #
  # - agent = the instance of this NA
  # - cmdObject = a Command Object holding all the information required to 
  #               execute this command
  #
  def AgentCommands.STDIN(agent, cmdObject)
    begin
      id = cmdObject.appID
      line = cmdObject.value
      ExecApp[id].stdin(line)
    rescue Exception => err
      raise Exception.new("- Error while writing to standard-IN of application '#{id}' \
(likely caused by a a call to 'sendMessage' or an update to a dynamic property)") 
    end
  end

  #
  # Command 'PM_INSTALL'
  #
  # Poor man's installer. Fetch a tar file and
  # extract it into a specified directory
  #
  # - agent = the instance of this NA
  # - cmdObject = a Command Object holding all the information required to 
  #               execute this command
  #
  def AgentCommands.PM_INSTALL(agent, cmdObject)
    id = cmdObject.appID
    url = cmdObject.image
    installRoot = cmdObject.path

    MObject.debug "Installing '#{url}' into '#{installRoot}'"
    cmd = "cd /tmp;wget -m -nd -q #{url};"
    file = url.split('/')[-1]
    cmd += "tar -C #{installRoot} -xf #{file}; rm #{file}"
    ExecApp.new(id, agent, cmd)
  end

  #
  # Command 'APT_INSTALL'
  #
  # Execute apt-get command on node
  #
  # - agent = the instance of this NA
  # - cmdObject = a Command Object holding all the information required to 
  #               execute this command
  #
  def AgentCommands.APT_INSTALL(agent, cmdObject)
    id = cmdObject.appID
    pkgName = cmdObject.package
    cmd = "DEBIAN_FRONTEND='noninteractive' apt-get install --reinstall -qq #{pkgName}"
    ExecApp.new(id, agent, cmd)
  end

  #
  # Command 'RPM_INSTALL'
  #
  # Execute yum command on node
  #
  # - agent = the instance of this NA
  # - cmdObject = a Command Object holding all the information required to 
  #               execute this command
  #
  def AgentCommands.RPM_INSTALL(agent, cmdObject)
    id = cmdObject.appID
    pkgName = cmdObject.package
    cmd = "/usr/bin/yum -y install #{pkgName}"
    ExecApp.new(id, agent, cmd)
  end

  #
  # Command 'RESET'
  #
  # Reset this node agent
  #
  # - agent = the instance of this NA
  # - cmdObject = a Command Object holding all the information required to 
  #               execute this command
  #
  def AgentCommands.RESET(agent, cmdObject)
    agent.reset
  end


  #
  # Command 'RESTART'
  #
  # Restart this node agent
  #
  # - agent = the instance of this NA
  # - cmdObject = a Command Object holding all the information required to 
  #               execute this command
  #
  def AgentCommands.RESTART(agent, cmdObject)
    agent.communicator.quit
    ExecApp.killAll
    system("/etc/init.d/omf-resctl-#{OMF_MM_VERSION} restart")
    # will be killed by now :(
  end

  #
  # Command 'REBOOT'
  # 
  # Reboot this node
  #
  # - agent = the instance of this NA
  # - cmdObject = a Command Object holding all the information required to 
  #               execute this command
  #
  def AgentCommands.REBOOT(agent, cmdObject)
    agent.send(:STATUS, SYSTEM_ID, "REBOOTING")
    agent.communicator.quit
    cmd = `sudo /sbin/reboot`
    if !$?.success?
      # In case 'sudo' is not installed but we do have root rights (e.g. PXE image)
      cmd = `/sbin/reboot`
    end
  end

  #
  # Command 'MODPROBE'
  #
  # Load a kernel module on this node
  #
  # - agent = the instance of this NA
  # - cmdObject = a Command Object holding all the information required to 
  #               execute this command
  #
  def AgentCommands.MODPROBE(agent, cmdObject)
    moduleName = cmdObject.appID
    id = "module/#{moduleName}"
    ExecApp.new(id, agent, "/sbin/modprobe #{argArray.join(' ')} #{moduleName}")
  end

  #
  # Command 'CONFIGURE'
  #
  # Configure a system parameter on this node
  #
  # - agent = the instance of this NA
  # - cmdObject = a Command Object holding all the information required to 
  #               execute this command
  #
  def AgentCommands.CONFIGURE(agent, cmdObject)
    path = cmdObject.path
    value = cmdObject.value

    if (type, id, prop = path.split("/")).length != 3
      raise "Expected path '#{path}' to contain three levels"
    end
    device = DEV_MAPPINGS["#{type}/#{id}"]
    if (device == nil)
      raise "Unknown resource '#{type}/#{id}' in 'configure'"
    end

    result = device.configure(prop, value)
    if result[:success]
      agent.okReply(result[:msg], cmdObject)
    else
      agent.errorReply(result[:msg], cmdObject) 
    end
  end

  #
  # Command 'LOAD_IMAGE'
  #
  # Load a specified disk image onto this node through frisbee
  #
  # - agent = the instance of this NA
  # - cmdObject = a Command Object holding all the information required to 
  #               execute this command
  #
  def AgentCommands.LOAD_IMAGE(agent, cmdObject)
    mcAddress = cmdObject.address
    mcPort = cmdObject.port
    disk = cmdObject.disk

    MObject.info "AgentCommands", "Frisbee image from ", mcAddress, ":", mcPort
    ip = agent.localAddr
    cmd = "frisbee -i #{ip} -m #{mcAddress} -p #{mcPort} #{disk}"
    MObject.debug "AgentCommands", "Frisbee command: ", cmd
    ExecApp.new('builtin:load_image', agent, cmd, true)
  end

  #
  # Command 'SAVE_IMAGE'
  #
  # Save the image of this node with frisbee and send
  # it to the image server.
  #
  # - agent = the instance of this NA
  # - cmdObject = a Command Object holding all the information required to 
  #               execute this command
  #
  def AgentCommands.SAVE_IMAGE(agent, cmdObject)
    imgHost = cmdObject.address
    imgPort = cmdObject.port
    disk = cmdObject.disk
    
    cmd = "imagezip #{disk} - | nc -q 0 #{imgHost} #{imgPort}"
    MObject.debug "AgentCommands", "Image save command: #{cmd}"
    ExecApp.new('builtin:save_image', agent, cmd, true)
  end

  #
  # Command 'PM_INSTALL'
  #
  # Poor man's installer. Fetch a tar file and
  # extract it into a specified directory
  #
  # - agent = the instance of this NA
  # - cmdObject = a Command Object holding all the information required to 
  #               execute this command
  #
  def AgentCommands.LOAD_DATA(agent, cmdObject)
    id = cmdObject.appID
    url = cmdObject.image
    installRoot = cmdObject.path

    MObject.debug "Loading '#{url}' into '#{installRoot}'"
    cmd = "cd /tmp;wget -m -nd -q #{url};"
    file = url.split('/')[-1]
    cmd += "tar -C #{installRoot} -xf #{file}; rm #{file}"
    ExecApp.new(id, agent, cmd)
  end


  # 
  # Remove the first element from 'argArray' and
  # return it. If it is nil, raise exception
  # with 'exepString' providing MObject.information about the
  # missing argument
  #
  # - argArray = Array of arguments
  # - exepString = MObject.information about argument, used for exception
  # 
  # [Return] First element in 'argArray' or raise exception if nil
  # [Raise] Exception if arg is nil
  #
  #def AgentCommands.getArg(argArray, exepString)
  #  arg = argArray.delete_at(0)
  #  if (arg == nil)
  #    raise exepString
  #  end
  #  return arg
  #end

  #
  # Remove the first element from 'argArray' and
  # return it. If it is nil, return 'default'
  #
  # - argArray = Array of arguments
  # - default = Default value if arg in argArray is nil
  #
  # [Return] First element in 'argArray' or 'default' if nil
  #
  #def AgentCommands.getArgDefault(argArray, default = nil)
  #  arg = argArray.delete_at(0)
  #  if (arg == nil)
  #    arg = default
  #  end
  #  return arg
  #end

end