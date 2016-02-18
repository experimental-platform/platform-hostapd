require "hostapd/version"
require 'fileutils'
require 'forwardable'
require 'ipaddr'
require 'pathname'
require 'timeout'
require 'openssl'
require 'logger'

module Wifi

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
      OpenSSL::PKCS5.pbkdf2_hmac_sha1(passphrase, ssid, 4096, 32).unpack("H*").first
    end
  end

  def self.debug msg
    Logger.new(STDOUT).log Logger::Severity::DEBUG, msg
  end

  def self.info msg
    Logger.new(STDOUT).log Logger::Severity::INFO, msg
  end

  def self.network_config(config_path)
    debug 'fetching networks'
    networks = []
    debug 'Looking for private network at ' + File.join(config_path, 'enabled').to_s
    if File.exists? File.join(config_path, 'enabled')
      debug 'Private network found, configuring...'
      networks << {:name => 'private', :path => config_path}
    end
    public_network_path = File.join(config_path, 'guest').to_s
    debug 'Looking for public network at ' + File.join(public_network_path, 'enabled').to_s
    if File.exists? File.join(public_network_path, 'enabled')
      debug 'Public network found, configuring...'
      networks << {:name => 'public', :path => public_network_path}
    end
    networks
  end

  def self.physical_interface
    if result = `iw list`.match(/(^[a-zA-Z0-9]+)\s+([a-zA-Z0-9]+)/)
      result[2]
    else
      'phy0'
    end
  end

  def self.ieee80211n
    !!`iw phy #{physical_interface} info`.match(/HT[248]{1}0/im) ? "1" : "0"
  end

  def self.channel(config_path)
    channel_path = File.join config_path, 'channel'
    File.read(channel_path).strip rescue '1'
  end


  def self.interface_name(networks)
    # this returns a number of interface names.
    # the first one is the hardware name, the others are just names.
    # TODO NEW: check for interface (wl*, private, public, ...)
    # TODO NEW: rename interface to the first active name
    # TODO NEW: use interface name in config for first device
    # TODO NEW: use other name in config for second device
    # `ip link show`.match(/^[0-9: \t]+wl[0-9a-z]+/)[0].split(/\s/)[1]
    %w(wlp2s0 public)
  end

  def self.password_for_network(network)
    path = File.join network[:path], 'password'
    File.read path if File.readable? path
  end


  def self.wpa_psk(network)
    wpa_passphrase ssid(network), password_for_network(network)
  end

  def self.first_bssid(networks)
    iface = interface_name(networks)[0]
    if match = `ip addr show #{iface}`.match(/link\/ether.*?(([A-F0-9]{2}:){5}[A-F0-9]{2})/im)
        mac_address = match[1]
    else
      mac_address = "00:00:B0:0B:00:00"
    end
    mac = mac_address.split(':').map(&:hex)
    mac[0] |= 2 # locally administered
    mac[-1] = 0
    mac[-1] += 1
    "%02x:%02x:%02x:%02x:%02x:%02x" % mac
  end

  def self.ssid(network)
    hostname = `hostname -s`.chomp!
    network[:name] == 'private' ? hostname : "#{ hostname } (public)"
  end

  def self.ht_capab(config_path)
    channel_width_set = channel(config_path).to_i < 8 ? "+" : "-"
    raw = `iw phy #{physical_interface} info`
    iw_caps = raw.match(/band 1\:[\S\s]+?capabilities\:(?<capabilities>[\S\s]+?)frequencies\:/i)[:capabilities]
    result = ""
    # CHANNEL WIDTH (aka: CHANNEL BONDING): http://wifijedi.com/2009/01/25/how-stuff-works-channel-bonding/
    result << "[HT20]" if iw_caps.include?("HT20")
    result << "[HT40#{channel_width_set}]" if iw_caps.include?("HT40")
    # SHORT GUARD INTERVAL: http://wifijedi.com/2009/02/11/how-stuff-works-short-guard-interval/
    result << "[SHORT-GI-20]" if iw_caps.include?("HT20 SGI")
    result << "[SHORT-GI-40]" if iw_caps.include?("HT40 SGI")
    result << "[DSSS_CCK-40]" if iw_caps.include?("DSSS/CCK HT40")
    # FRAME AGGREGATION: http://en.wikipedia.org/wiki/Frame_aggregation
    result << "[MAX-AMSDU-3839]" if iw_caps.include?("MAX AMSDU LENGTH: 3839")
    # SPATIAL STREAMS: http://wifijedi.com/2009/02/01/how-stuff-works-spatial-multiplexing/
    result << "[TX-STBC]" if iw_caps.include?("TX STBC")
    result << "[RX-STBC1]" if iw_caps.include?("RX STBC 1")
    result
  end

  def self.create_config_file(networks, config_path)
    debug "hostapd configure"
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
