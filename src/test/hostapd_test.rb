require 'test_helper'

ROOT = File.expand_path '..', __FILE__
ENV['PATH'] = "#{ File.join ROOT, 'fixtures', 'bin' }:#{ ENV['PATH'] }"


Wifi::Logging.logger = Logger.new File.join(ROOT, 'test.log')

# noinspection RubyInstanceMethodNamingConvention
class HostapdTest < Minitest::Test

  ETC = File.join ROOT, 'fixtures', 'etc'
  attr_reader :config_path, :hostapd_config_path

  # TODO add tests for every line in hostapd.conf

  def setup
    @config_path = File.join ETC, %w[ protonet system wifi ]
    Wifi.config_path = config_path
    @hostapd_config_path = File.join ETC, 'hostapd', 'hostapd.conf'
    Wifi::Hostapd::DEFAULT_OPTIONS[:config_path] = hostapd_config_path
    File.unlink @hostapd_config_path if File.exists? @hostapd_config_path
  end

  def config
    File.read(hostapd_config_path).split /\n/
  end

  def read_hostname
    `hostname -s`.chomp!
  end

  def set_hostname(hostname = read_hostname)
    Wifi.instance_variable_set :@nodename, hostname
    @hostname = hostname
  end

  alias_method :reset_hostname, :set_hostname

  def hostname
    @hostname ||= read_hostname
  end

  def with_hostname(hostname)
    set_hostname hostname
    yield
  ensure
    set_hostname
  end

  def with_channel(channel)
    old_channel = Wifi::Hostapd::DEFAULT_OPTIONS[:channel]
    Wifi::Hostapd::DEFAULT_OPTIONS[:channel] = channel
    yield channel
  ensure
    Wifi::Hostapd::DEFAULT_OPTIONS[:channel] = old_channel
  end

  def public_disabled
    path = File.join ETC, %w[ protonet system wifi guest enabled ]
    File.unlink path

    yield
  ensure
    File.open(path, File::CREAT|File::RDWR) { |f| f << 'true' }
  end

  def private_disabled
    path = File.join ETC, %w[ protonet system wifi enabled ]
    File.unlink path

    yield
  ensure
    File.open(path, File::CREAT|File::RDWR) { |f| f << 'true' }
  end

  def test_that_it_has_a_version_number
    refute_nil ::Hostapd::VERSION
  end

  def test_start_generates_config_and_starts_hostapd
    Wifi.start
    config
  end

  def test_channel_is_configured
    with_channel rand(16) do |channel|
      Wifi.start
      assert_includes config, "channel=#{channel}"
    end
  end

  def test_private_wpa_can_be_set
    password = 'secretprivate'
    psk = '5eb4f89bf08336deffb335fd755875795ea581df4ca2ea7265bfa9d57420c504'

    with_hostname('pfannkuchenpfanne') { Wifi.start }

    assert_includes config, "wpa_psk=#{psk}"
  end

  def test_public_wpa_can_be_set
    password = 'secretpublic'
    psk = 'f3774c9dca0a46f1c11b7991e09673aafb4b1d3de5b818a9118c7fae1840aa30'

    with_hostname('pfannkuchenpfanne') { Wifi.start }

    assert_includes config, "wpa_psk=#{psk}"
  end

  def test_private_ssid_is_taken_from_hostname
    Wifi.start
    assert_includes config, "ssid=#{ hostname }"
  end

  def test_public_ssid_is_generated_from_private_ssid_and_suffix
    Wifi.start
    assert_includes config, "ssid=#{ hostname } (public)"
  end

  def test_bssid_is_set_when_public_and_private_are_enabled
    # see fixtures/bin/ip-addr-show.out
    Wifi.start
    assert_includes config, "bssid=02:0e:8e:64:2a:01"
  end

  def test_ctrl_interfaces_points_to_socket
    # Ubuntu always uses '/var/run/hostapd'
    Wifi.start
    assert_includes config, "ctrl_interface=/var/run/hostapd"
  end

  def test_country_code_is_us
    # Apparently we're not allowed to change that.
    Wifi.start
    assert_includes config, "country_code=US"
  end

  def test_bssid_is_not_set_when_less_than_two_networks_are_enabled
    public_disabled { Wifi.start }
    line = config.grep(/^bssid/).first
    assert_nil line
  end

  def test_private_network_can_be_disabled
    private_disabled { Wifi.start }
    refute_includes config, "ssid=#{hostname}"
    assert_includes config, "ssid=#{hostname} (public)"
  end

  def test_public_network_can_be_disabled
    public_disabled { Wifi.start }
    assert_includes config, "ssid=#{hostname}"
    refute_includes config, "ssid=#{hostname} (public)"
  end

  def test_driver_can_be_configured
    driver = 'nl80211'
    old_driver = Wifi::Hostapd::DEFAULT_OPTIONS[:driver]
    Wifi::Hostapd::DEFAULT_OPTIONS[:driver] = driver

    Wifi.start

    assert_includes config, "driver=#{driver}"
  ensure
    Wifi::Hostapd::DEFAULT_OPTIONS[:driver] = old_driver
  end

  def test_interface_can_be_changed
    interface = 'wlan0'
    old_interface = Wifi::Hostapd::DEFAULT_OPTIONS[:interface_name]
    Wifi::Hostapd::DEFAULT_OPTIONS[:interface_name] = interface

    Wifi.start

    assert_includes config, "interface=#{interface}"
  ensure
    Wifi::Hostapd::DEFAULT_OPTIONS[:interface_name] = old_interface
  end

  def test_hw_capabilities_are_read_from_iw_info
    # see fixtures/bin/iw-info.out
    Wifi.start
    assert_includes config, "ht_capab=[HT20][HT40+][SHORT-GI-20][SHORT-GI-40][DSSS_CCK-40][TX-STBC][RX-STBC1]"
  end

  def test_ieee80211n_set_true_from_iw_info
    # see fixtures/bin/iw-info-true.out
    ENV['MOCK_IW_80211N'] = "TRUE"
    Wifi.start
    assert_includes config, "ieee80211n=1"
  end

  def test_ieee80211n_set_false_from_iw_info
    ENV['MOCK_IW_80211N'] = "FALSE"
    # see fixtures/bin/iw-info-false.out
    Wifi.start
    assert_includes config, "ieee80211n=0"
  ensure
    ENV.delete('MOCK_IW_80211N')
  end

  def test_wmm_enabled_set_true
    # this is just the default switch, advanced config
    # depends on hardware features
    Wifi.start
    assert_includes config, "wmm_enabled=1"
  end

  def test_wme_enabled_set_true
    # no idea what this does, maybe disable it?
    Wifi.start
    assert_includes config, "wmm_enabled=1"
  end


  def test_hwmode_set_to_g
    # we can use #11b, 11g, and 11a respectively:
    # b is slow, a is 5GHz only and g the only sane solution
    # (ng and na are no valid options, see https://dev.openwrt.org/ticket/17541)
    Wifi.start
    assert_includes config, "hw_mode=g"
  end

  def test_ieee80211d_set_true
    # must be enabled to a) announce power and channel settings and
    # b) to enable ieee80211d (RADAR detection and DFS support)
    Wifi.start
    assert_includes config, "ieee80211d=1"
  end

  def test_ieee80211h_set_true
    # enables RADAR detection and DFS support
    Wifi.start
    assert_includes config, "ieee80211h=0"
  end

  def test_ht40_is_positive_when_channel_is_smaller_than_8
    1.upto 7 do |channel|
      with_channel(channel) { Wifi.start }
      assert_includes config, "ht_capab=[HT20][HT40+][SHORT-GI-20][SHORT-GI-40][DSSS_CCK-40][TX-STBC][RX-STBC1]"
    end
  end

  def test_ht40_is_negative_when_channel_is_greater_than_7
    8.upto 15 do |channel|
      with_channel(channel) { Wifi.start }
      assert_includes config, "ht_capab=[HT20][HT40-][SHORT-GI-20][SHORT-GI-40][DSSS_CCK-40][TX-STBC][RX-STBC1]"
    end
  end

  ["private", "public"].each do |section|
    define_method("test_#{section}_macaddr_acl_is_0") do
      self.method("#{section}_disabled").call { Wifi.start }
      assert_includes config, 'macaddr_acl=0'
    end

    define_method("test_#{section}_auth_algs_is_1") do
      self.method("#{section}_disabled").call { Wifi.start }
      assert_includes config, 'auth_algs=1'
    end

    define_method("test_#{section}_ignore_broadcast_ssid_is_0") do
      self.method("#{section}_disabled").call { Wifi.start }
      assert_includes config, 'ignore_broadcast_ssid=0'
    end

    define_method("test_#{section}_wpa_2") do
      self.method("#{section}_disabled").call { Wifi.start }
      assert_includes config, 'wpa=2'
    end

    define_method("test_#{section}_wpa_key_mgmt_is_WPA-PSK") do
      self.method("#{section}_disabled").call { Wifi.start }
      assert_includes config, 'wpa_key_mgmt=WPA-PSK'
    end

    define_method("test_#{section}_rsn_pairwise_is_CCMP") do
      self.method("#{section}_disabled").call { Wifi.start }
      assert_includes config, 'rsn_pairwise=CCMP'
    end

  end

  def test_bss_is_not_set_when_less_than_two_networks_are_enabled
    public_disabled { Wifi.start }
    line = config.grep(/^bss=/).first
    assert_nil line
  end

  def test_bss_is_set_when_two_networks_are_enabled
    Wifi.start
    assert_includes config, 'bss=wlp2s0'
  end

end