require 'hostapd/version'
require 'fileutils'
require 'forwardable'
require 'ipaddr'
require 'pathname'
require 'timeout'
require 'openssl'
require 'logger'
require 'contracts'

module Wifi
  include Contracts

  Contract String, String => Maybe[Bool]

  def self.start(config_path, hostapd_path)
    networks = network_config config_path
    if networks.any?
      info "found wifis: #{networks.map { |h| h[:name] }}"
      config_data = create_config_file networks, config_path
      write_file hostapd_path, config_data
      # only for debugging purposes:
      if File.directory? config_path
        FileUtils.cp hostapd_path, File.join(config_path, 'hostapd.conf.backup')
      end
      true
    end
  end

  private

  def self.wpa_passphrase(ssid, passphrase)
    if [ssid, passphrase].all? { |value| value.to_s.strip.length > 0 }
      OpenSSL::PKCS5.pbkdf2_hmac_sha1(passphrase, ssid, 4096, 32).unpack('H*').first
    end
  end

  def self.debug(msg)
    Logger.new(STDOUT).log Logger::Severity::DEBUG, msg
  end

  def self.info(msg)
    Logger.new(STDOUT).log Logger::Severity::INFO, msg
  end

  Contract String => Array

  def self.network_config(config_path)
    debug 'fetching networks'
    networks = []
    config_root = File.join(config_path, '..', '..')
    debug 'Looking for private network at ' + File.join(config_path, 'enabled').to_s
    if File.exists? File.join(config_path, 'enabled')
      debug 'Private network found, configuring...'
      networks << {:name => 'wl_private', :path => config_path, :config_root => config_root}
    end
    public_network_path = File.join(config_path, 'guest').to_s
    debug 'Looking for public network at ' + File.join(public_network_path, 'enabled').to_s
    if File.exists? File.join(public_network_path, 'enabled')
      debug 'Public network found, configuring...'
      networks << {:name => 'wl_public', :path => public_network_path, :config_root => config_root}
    end
    networks
  end

  Contract nil => String

  def self.physical_interface
    result = `iw list`.match(/(^[a-zA-Z0-9]+)\s+([a-zA-Z0-9]+)/)
    if result and result.length > 2
      result[2]
    else
      'phy0'
    end
  end

  def self.ieee80211n
    !!`iw phy #{physical_interface} info`.match(/HT[248]{1}0/im) ? '1' : '0'
  end

  Contract String => String

  def self.channel(config_path)
    channel_path = File.join config_path, 'channel'
    File.read(channel_path).strip rescue '1'
  end

  Contract String, String => Maybe[String]

  def self.set_interface_name(interface, name)
    output = `ip link set dev #{interface} down 2>&1`
    raise "Tearing down #{interface} didn't work: #{output}" unless $?.success?
    output = `ip link set dev #{interface} name #{name} 2>&1`
    raise "Renaming #{interface} to #{name} didn't work: #{output}" unless $?.success?
    output = `ip link set dev #{name} up 2>&1`
    raise "Starting #{name} didn't work: #{output}" unless $?.success?
    output
  end

  Contract Array => Array

  def self.interface_name(networks)
    # the first one is the hardware name, the others are just useful names.
    interfaces = `ip link show`.each_line.map do |line|
      m = line.match(/(^[0-9]+:\s+)(wl[0-9a-z_\-]+)/)
      m[2] if m and m.length >= 3
    end.compact
    first_network_name = networks[0][:name]
    # interface name should be wl_public or wl_private for
    # the corresponding systemd network units to work
    unless interfaces.include? first_network_name
      debug "Setting interface #{interfaces[0]} to #{first_network_name}"
      set_interface_name interfaces[0], first_network_name
    end
    sleep ENV.fetch('SLEEP_TIME', 5).to_i
    debug 'Restarting systemd-networkd.'
    output = `systemctl restart systemd-networkd`
    raise "Restarting networkd didn't work: #{output}" unless $?.success?
    sleep ENV.fetch('SLEEP_TIME', 5).to_i
    [first_network_name] + networks[1..-1].map { |e| e[:name] }
  end

  Contract Hash => String

  def self.password_for_network(network)
    path = File.join network[:path], 'password'
    File.read(path).strip if File.readable? path
  end

  Contract Hash => String

  def self.wpa_psk(network)
    wpa_passphrase ssid(network), password_for_network(network)
  end

  Contract Array => String

  def self.first_bssid(networks)
    iface = interface_name(networks)[0]
    match = `ip addr show #{iface}`.match(/link\/ether.*?(([A-F0-9]{2}:){5}[A-F0-9]{2})/im)
    if match and match.length > 1
      mac_address = match[1]
    else
      mac_address = '00:00:B0:0B:00:00'
    end
    mac = mac_address.split(':').map(&:hex)
    mac[0] |= 2 # locally administered
    mac[-1] = 0
    mac[-1] += 1
    '%02x:%02x:%02x:%02x:%02x:%02x' % mac
  end

  Contract Hash => String

  def self.ssid(network)
    # on initial setup the wifi uses a statically set name instead of the hostname.
    # this works only for the private wifi and can be set in `hostname_path`.
    hostname_path = File.join(network[:path], 'hostname')
    box_name_path = File.join(network[:config_root], 'box_name')
    if File.exists? box_name_path
      hostname = File.read box_name_path
    elsif network[:name] == 'wl_private' and File.exists? hostname_path
      hostname = File.read hostname_path
    else
      hostname = 'Protonet'
    end
    hostname = hostname.strip
    network[:name] == 'wl_private' ? hostname : "#{ hostname } (public)"
  end

  Contract String, String => String

  def self.ht_capab(config_path)
    channel_width_set = channel(config_path).to_i < 8 ? '+' : '-'
    raw = `iw phy #{physical_interface} info`
    iw_caps = raw.match(/band 1:[\S\s]+?capabilities:(?<capabilities>[\S\s]+?)frequencies:/i)[:capabilities]
    result = ''
    # CHANNEL WIDTH (aka: CHANNEL BONDING): http://wifijedi.com/2009/01/25/how-stuff-works-channel-bonding/
    result << '[HT20]' if iw_caps.include?('HT20')
    result << "[HT40#{channel_width_set}]" if iw_caps.include?('HT40')
    # SHORT GUARD INTERVAL: http://wifijedi.com/2009/02/11/how-stuff-works-short-guard-interval/
    result << '[SHORT-GI-20]' if iw_caps.include?('HT20 SGI')
    result << '[SHORT-GI-40]' if iw_caps.include?('HT40 SGI')
    result << '[DSSS_CCK-40]' if iw_caps.include?('DSSS/CCK HT40')
    # FRAME AGGREGATION: http://en.wikipedia.org/wiki/Frame_aggregation
    result << '[MAX-AMSDU-3839]' if iw_caps.include?('MAX AMSDU LENGTH: 3839')
    # SPATIAL STREAMS: http://wifijedi.com/2009/02/01/how-stuff-works-spatial-multiplexing/
    result << '[TX-STBC]' if iw_caps.include?('TX STBC')
    result << '[RX-STBC1]' if iw_caps.include?('RX STBC 1')
    result
  end

  Contract Array, String => String

  def self.create_config_file(networks, config_path)
    debug 'hostapd configure'
    first_network = networks[0]
    config = <<-CONFIG.gsub(/^ */, '')
        ctrl_interface=/var/run/hostapd
        driver=nl80211
        hw_mode=g
        ieee80211n=#{ieee80211n}
        ieee80211d=1
        ieee80211h=0
        country_code=US
        wme_enabled=1
        wmm_enabled=1
        channel=#{channel(config_path)}
        ht_capab=#{ht_capab(config_path)}
        interface=#{interface_name(networks)[0]}
        logger_stdout=-1
        logger_stdout_level=2

        ssid=#{ssid(first_network)}
        macaddr_acl=0
        auth_algs=1
        ignore_broadcast_ssid=0
        wpa=2
        wpa_key_mgmt=WPA-PSK
        rsn_pairwise=CCMP
        wpa_psk=#{wpa_psk(first_network)}

    CONFIG
    if networks.length == 2
      second_network = networks[1]
      config << <<-END.gsub(/^ */, '')
        bss=#{interface_name(networks)[1]}
        bssid=#{first_bssid(networks)}
        ssid=#{ssid(second_network)}
        macaddr_acl=0
        auth_algs=1
        ignore_broadcast_ssid=0
        wpa=2
        wpa_key_mgmt=WPA-PSK
        rsn_pairwise=CCMP
        wpa_psk=#{wpa_psk(second_network)}
      END
    end
    config
  end

  def self.write_file(filename, data)
    File.open(filename, 'w') do |file|
      file.write(data)
    end
  end
end
