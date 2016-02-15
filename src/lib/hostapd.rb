require "hostapd/version"
require 'fileutils'
require 'forwardable'
require 'ipaddr'
require 'pathname'
require 'timeout'
require 'openssl'
require 'logger'

module Wifi

  def self.wpa_passphrase(ssid, passphrase)
    if [ssid, passphrase].all? {|value| value.to_s.strip.length > 0 }
      OpenSSL::PKCS5.pbkdf2_hmac_sha1(passphrase, ssid, 4096, 32).unpack("H*").first
    end
  end

  module Logging
    extend Forwardable

    @@logger = Logger.new(STDOUT)

    def self.logger=(logger)
      @@logger = logger
    end

    def_delegators :logger, :debug, :info, :warn, :error, :fatal, :unknown

    def log(msg)
      logger.log
    end

    def logger
      @@logger
    end


    def level
      logger.instance_variable_get(:@level)
    end

    def level=(level=Logger::ERROR) # DEBUG=0, INFO=1, WARN=2, ERROR=3, FATAL=4, UNKNOWN=5
      logger.instance_variable_set(:@level, level)
    end
  end

  module Console
    include Logging

    def run(cmd)
      if level == Logger::DEBUG
        debug "run: #{cmd}"
      end
      system "#{cmd} >/dev/null 2>&1"
    end
  end

  class IPAddr
    def netmask
      _to_string(@mask_addr)
    end

    def succ_net
      to_range.last.succ
    end

    def prefixlen
      @mask_addr.to_s(2).count('1')
    end

    def to_cidr
      "#{to_s}/#{prefixlen}"
    end
  end

  class Config
  end
  class Network
  end
  class Hostapd
  end

  class << self
    include Logging

    attr_accessor :config_path

    class Config < Wifi::Config

      def fetch(key, default)
        super
      end

      def read(name)
        path = config_path.join(name.to_s.downcase)
        File.read path if File.readable? path
      end

      def password
        read :password
      end
    end

    class Network < Wifi::Network

      Job = Struct.new :to_s, :start, :stop

      def dnsmasq
        Job.new
      end

      def interface
        interface_name = `ip addr show`.match(/^[0-9: \t]+(wl[0-9a-z]+):/)[1]
        Job.new interface_name
      end

      def hostname
        `hostname -s`.chomp!
      end

      def ssid
        name == 'private' ? hostname : "#{ hostname } (public)"
      end

      def password
        config.password
      end

      def enabled?
        true
      end

    end

    def networks
      debug "fetching networks"

      @networks = []

      private_network_path = File.join config_path
      public_network_path = File.join config_path, 'guest'

      if File.exists? File.join(private_network_path, 'enabled')
        config = Config.new private_network_path
        @networks << Network.new('private', config, config_path: config_path)
      end

      if File.exists? File.join(public_network_path, 'enabled')
        config = Config.new public_network_path
        @networks << Network.new('public', config, config_path: config_path)
      end

      @networks
    end

    def enabled_networks
      networks.select(&:enabled?)
    end

    def hostapd
      Hostapd.new
    end

    def restart
      stop
      start
    end

    def start
      info "found wifis: #{enabled_networks.map(&:name)}"
      if enabled_networks.any?
        hostapd.configure enabled_networks
        # hostapd.start
        # enabled_networks.each(&:start)
      end
    end

    def stop
      networks.each(&:stop)
      hostapd.stop
    end

    def log_files
      ([hostapd] + enabled_networks.map(&:dnsmasq)).map do |e|
        e.service.log_path.join('current').to_s
      end
    end

    def ip_taken?(ip)
      enabled_networks.map { |net| net.ip(false) }.include? ip
    end

    def interface_taken?(interface)
      enabled_networks.map { |net| net.interface(false) }.include? interface
    end

    def read_hostname
      hostname = `hostname -s`.strip
      raise 'Hostname could not be read' unless $?.zero?

      hostname
    end

    def nodename
      @nodename ||= read_hostname
    end

    def config
      @config ||= Config.new(config_path)
    end

    def config_path
      @config_path ||= '/etc/protonet/system/wifi'
    end

    def version
      info "Wifi (version: #{VERSION})"
    end
  end

  VERSION = "1.1.5"

  class Interface
    include Console
    include Comparable
    include Logging

    attr_reader :name, :network, :options

    def initialize(name, network, options={})
      @network = network
      @name = name
      @options = {
        test_interface: 'ip link show %{interface}',
        config_interface: '/sbin/ifconfig %{interface} %{ip} netmask %{netmask}',
        external_interface: 'br0'
      }.merge options
    end

    def available?
      run(options[:test_interface] % {interface: name})
    end

    def wait_for_it(timeout = 10)
      Timeout::timeout(timeout) do
        until available?
          debug "Waiting for Interface #{name}"
          sleep 1.0/4
        end
        true
      end rescue false
    end

    def <=>(other)
      name <=> other.name
    end

    def up
      wait_for_it
      ifconfig
      iptables :create
    end

    def down
      iptables :destroy
    end

    def to_s
      name
    end

    def succ
      self.class.new name.succ, network, options
    end

    private
    def iptables(state)
      debug("Configure Routes for #{name}")
      option = '-D'
      option = '-A' if state == :create

      run("/sbin/iptables #{option} FORWARD -i #{options[:external_interface]} -o #{name} -m state --state ESTABLISHED,RELATED -j ACCEPT")
      run("/sbin/iptables #{option} FORWARD -i #{name} -o #{options[:external_interface]} -j ACCEPT")
      run("/sbin/iptables -t nat #{option} POSTROUTING -o #{options[:external_interface]} -j MASQUERADE")
    end

    def ifconfig
      wait_for_it
      debug("Configure IP/Netmask for #{name}")
      run(options[:config_interface] % {interface: name, ip: network.ip.succ.to_s, netmask: network.ip.netmask})
    end
  end
  class Hostapd
    include Logging

    attr_reader :options

    @@channel_path = '/etc/protonet/wifi/channel'

    DEFAULT_OPTIONS = {
      config_path: '/etc/hostapd/hostapd.conf',
      service_name: 'hostapd',
      service_exec: 'exec /usr/local/bin/hostapd -d %{config_path}',
      ctrl_interface: '/var/run/hostapd',
      driver: 'nl80211',
      hw_mode: 'g',
      ieee80211d: '1',
      ieee80211h: 0, # TODO: enable RADAR detection?
      country_code: 'US',
      wme_enabled: '1',
      wmm_enabled: '1',
      # interface_name: 'wlan0'
      interface_name: 'wlp2s0'
    }

    # default accessor
    DEFAULT_OPTIONS.each do |name, value|
      define_method(name) do
        options[name]
      end
    end

    def initialize(options={})
      @options = DEFAULT_OPTIONS.merge options
    end

    def channel
      File.read(@@channel_path).strip rescue '1'
    end

    def configure(networks)
      debug "hostapd configure"

      return if networks.empty?

      base_config = <<-CONFIG.gsub(/^ */, '')
        ctrl_interface=#{ctrl_interface}
        driver=#{driver}
        hw_mode=#{hw_mode}
        ieee80211n=#{ieee80211n}
        ieee80211d=#{ieee80211d}
        ieee80211h=#{ieee80211h}
        country_code=#{country_code}
        wme_enabled=#{wme_enabled}
        wmm_enabled=#{wmm_enabled}
        channel=#{channel}
        ht_capab=#{ht_capab}
        interface=#{interface_name}
      CONFIG

      # make sure everyone has his interface
      networks.map(&:interface) # dirty hack

      first_network = networks[0]
      other_networks = networks[1..-1]

      ssids_config = []

      first_ssid = "ssid=#{first_network.ssid}\n"
      if passphrase = first_network.password
        first_ssid << <<-END_PASSPHRASE.gsub(/^ */, '')
          macaddr_acl=#{first_network.macaddr_acl}
          auth_algs=#{first_network.auth_algs}
          ignore_broadcast_ssid=#{first_network.ignore_broadcast_ssid}
          wpa=#{first_network.wpa}
          wpa_key_mgmt=#{first_network.wpa_key_mgmt}
          rsn_pairwise=#{first_network.rsn_pairwise}
          wpa_psk=#{first_network.wpa_psk}
        END_PASSPHRASE
      end

      other_ssids = other_networks.map do |network|
        ssid = <<-END.gsub(/^ */, '')
          bss=#{network.interface}
          bssid=#{next_bssid}
          ssid=#{network.ssid}
        END
        if passphrase = network.password
          ssid << <<-END_PASSPHRASE.gsub(/^ */, '')
            macaddr_acl=#{network.macaddr_acl}
            auth_algs=#{network.auth_algs}
            ignore_broadcast_ssid=#{network.ignore_broadcast_ssid}
            wpa=#{network.wpa}
            wpa_key_mgmt=#{network.wpa_key_mgmt}
            rsn_pairwise=#{network.rsn_pairwise}
            wpa_psk=#{network.wpa_psk}
          END_PASSPHRASE
        end
        ssid
      end

      config = [base_config, first_ssid, *other_ssids].join($/)
      config_file do |file|
        file.write config
      end
    end

    def config_file(&block)
      FileUtils.mkdir_p(File.dirname(config_path)) unless configured?
      File.open(config_path, 'w', &block)
    end

    def configured?
      File.exists?(config_path)
    end

    def ht_capab
      Generator::HardwareCapability.new({channel: channel})
    end

    def ieee80211n
      !!`iw phy phy0 info`.match(/HT[248]{1}0/im) ? "1" : "0"
    end

    def mac_address
      if match = `ip addr show #{interface_name}`.match(/link\/ether.*?(([A-F0-9]{2}:){5}[A-F0-9]{2})/im)
        # if match = `ifconfig #{interface_name}`.match(/#{interface_name}.*?(([A-F0-9]{2}:){5}[A-F0-9]{2})/im)
        match[1]
      else
        "00:00:B0:0B:00:00"
      end
    end

    def next_bssid
      @bssid ||= begin
        mac = mac_address.split(':').map(&:hex)
        mac[0] |= 2 # locally administered
        mac[-1] = 0
        mac
      end

      @bssid[-1] += 1
      "%02x:%02x:%02x:%02x:%02x:%02x" % @bssid
    end
  end

  class Network
    include Logging


    DEFAULT_OPTIONS = {
      wifi_available: 'available',
      wifi_enabled: 'enabled',
      first_network: '10.42.0.0/16',
      first_interface: 'wlan0',
      macaddr_acl: '0',
      auth_algs: '1',
      ignore_broadcast_ssid: '0',
      wpa: '2',
      wpa_key_mgmt: 'WPA-PSK',
      rsn_pairwise: 'CCMP'
    }

    # default accessor
    DEFAULT_OPTIONS.each do |name, value|
      define_method(name) do
        options[name]
      end
    end

    attr_reader :name, :config, :options

    def initialize(name, config, options={})
      @name = name
      @config = config
      @options = DEFAULT_OPTIONS.merge options
    end

    def enable
      debug "network(#{name}) enable"
      link
      start
    end

    def disable
      debug "network(#{name}) disable"
      unlink
      stop
    end

    def start
      return stop unless enabled?
      debug "network(#{name}) start"
      interface.down # for cleanup
      interface.up
      dnsmasq.build
      dnsmasq.restart
    end

    def stop
      debug "network(#{name}) stop"
      dnsmasq.stop
      interface.down
    end

    def dnsmasq
      Dnsmasq.new(self)
    end

    def interface(build=true)
      @interface ||= if build
        debug "network(#{name}) build interface"
        # find a line that looks like this and return the interface name only:
        # 2: wlp2s0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc mq state DOWN mode DEFAULT
        interface_name = `ip link show`.match(/^[0-9: \t]+wl[0-9a-z]+/)[0].split(/\s/)[1]
        interface = Interface.new(interface_name, self)
        while Wifi.interface_taken?(interface)
          interface = interface.succ
        end
        debug "network(#{name}) got interface(#{interface.name})"
        interface
      end
    end

    def ip(build=true)
      @ip ||= if build
        debug "network(#{name}) build ip"
        # search for first free net
        ip = IPAddr.new(options[:first_network])
        while Wifi.ip_taken?(ip) do
          ip = ip.succ_net
        end
        debug "network(#{name}) got ip(#{ip.to_s}"
        ip
      end
    end

    def enabled?
      File.exists? enabled_path
    end

    def passphrase
      Wifi.wpa_passphrase ssid, password
    end

    alias_method :wpa_psk, :passphrase

    def ssid
      config.fetch(:name, options[:name])
    end

    def password
      config.fetch(:password)
    end

    private
    def link
      FileUtils.ln_s File.join(Wifi.config_path, options[:wifi_available], name), File.join(Wifi.config_path, options[:wifi_enabled])
    end

    def unlink
      FileUtils.rm enabled_path
    end

    def enabled_path
      File.join(Wifi.config_path, options[:wifi_enabled], name)
    end
  end

  class Dnsmasq
    extend Forwardable
    attr_reader :network, :options

    def_instance_delegators :service, :start, :stop, :restart
    def_instance_delegators :network, :name

    def initialize(network, options={})
      @network = network
      @options = {
        config_path: '/home/protonet/dashboard/shared/config/dnsmasq.d/%{name}',
        service_name: 'dnsmasq_%{name}',
        service_cmd: 'exec /usr/sbin/dnsmasq -C %{config_path} -k -h --log-facility=-'
      }.merge options
    end

    def build
      generate_config
      service.build(start_service_cmd)
    end

    def service
      @service ||= Service.new(service_name)
    end

    def service_name
      options[:service_name] % {name: name}
    end

    def config_path
      options[:config_path] % {name: name}
    end

    def start_service_cmd
      options[:service_cmd] % {config_path: config_path}
    end

    def generate_config
      names = ["protonet", Wifi.nodename.split('.').first].compact

      interface = network.interface.name
      ips = network.ip.to_range.to_a
      network = ips.shift
      gateway = ips.shift
      reserved_ips = ips.shift(8) + ips.pop(5) # server and other static assigned devices
      addresses = names.map do |name|
        "address=/#{name}/#{gateway}"
      end.join($/) # join with system nl-delimiter

      config = <<-END
# DNSMasq Config

interface=#{interface}

      #{addresses}

dhcp-range=#{interface},#{ips.first},#{ips.last},24h

# Gateway
dhcp-option=3,#{gateway}

# DNS
dhcp-option=6,#{gateway}

# IP Forward (no)
dhcp-option=19,0

# Source Routing
dhcp-option=20,0

# 44-47 NetBIOS
dhcp-option=44,0.0.0.0
dhcp-option=45,0.0.0.0
dhcp-option=46,8
dhcp-option=47

dhcp-authoritative

bind-interfaces
except-interface=lo
      END
      File.open(config_path, 'w') do |file|
        file.write(config)
      end
      nil
    end
  end

  module Console
    include Logging

    def run(cmd)
      if level == Logger::DEBUG
        debug "run: #{cmd}"
      end
      system "#{cmd} >/dev/null 2>&1"
    end
  end

  class Config
    attr_reader :base_path, :parent

    def initialize(base_path, parent=nil)
      @base_path = base_path
      @parent = parent
    end

    def fetch(key, default=nil)
      read(key) || default
    end

    alias_method :[], :fetch

    def store(key, value)
      write(key, value)
    end

    alias_method :[]=, :store

    def scoped(scope)
      self.class.new(config_path.join(scope), self)
    end

    alias_method :scope, :scoped

    private
    def read(name)
      File.read(path(name)).strip rescue nil
    end

    def write(name, value)
      File.open(path(name), 'w') do |file|
        file.write(value)
      end rescue nil
    end

    def path(name)
      config_path.join(name.to_s.downcase)
    end

    def config_path
      Pathname.new(base_path)
    end
  end

  module Generator
    class HardwareCapability
      DEFAULT_OPTIONS = {
        interface: 'phy0',
        iw_info: 'iw %{interface} info',
        iw_capabilities_match: /band 1\:[\S\s]+?capabilities\:(?<capabilities>[\S\s]+?)frequencies\:/i,
        channel: "1"
      }

      CAPABILITIES = [
        # CHANNEL WIDTH (aka: CHANNEL BONDING): http://wifijedi.com/2009/01/25/how-stuff-works-channel-bonding/
        ->(info, scope) { "[HT20]" if info.include?("HT20") },
        ->(info, scope) { "[HT40#{scope.channel_width_set}]" if info.include?("HT40") },
        # SHORT GUARD INTERVAL: http://wifijedi.com/2009/02/11/how-stuff-works-short-guard-interval/
        ->(info, scope) { "[SHORT-GI-20]" if info.include?("HT20 SGI") },
        ->(info, scope) { "[SHORT-GI-40]" if info.include?("HT40 SGI") },
        ->(info, scope) { "[DSSS_CCK-40]" if info.include?("DSSS/CCK HT40") },
        # FRAME AGGREGATION: http://en.wikipedia.org/wiki/Frame_aggregation
        ->(info, scope) { "[MAX-AMSDU-3839]" if info.include?("MAX AMSDU LENGTH: 3839") },
        # SPATIAL STREAMS: http://wifijedi.com/2009/02/01/how-stuff-works-spatial-multiplexing/
        ->(info, scope) { "[TX-STBC]" if info.include?("TX STBC") },
        ->(info, scope) { "[RX-STBC1]" if info.include?("RX STBC 1") }
      ]

      attr_reader :options

      DEFAULT_OPTIONS.each do |name, value|
        define_method(name) do
          options[name]
        end
      end

      def initialize(options={})
        @options = DEFAULT_OPTIONS.merge options
      end

      def capabilities
        @capabilities ||= CAPABILITIES.inject("") do |accu, check|
          accu << check.call(iw_capabilities, self).to_s
        end
      end

      def to_s
        capabilities
      end

      def iw_capabilities
        @iw_capabilities ||= iw_info.match(options[:iw_capabilities_match])[:capabilities] #rescue ""
      end

      def iw_info
        `#{options[:iw_info] % {interface: interface} }`.to_s
      end

      def channel_width_set
        channel.to_i < 8 ? "+" : "-"
      end
    end
  end
end
