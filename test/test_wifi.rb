require 'minitest/autorun'
require "minitest/reporters"

ROOT = File.expand_path '..', __FILE__
ENV['PATH'] = "#{ File.join ROOT, 'fixtures', 'bin' }:#{ ENV['PATH'] }"

Minitest::Reporters.use!

require 'wifi'
Wifi::Logging.logger = Logger.new File.join(ROOT, 'test.log');

class TestWifi < Minitest::Test

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

  def test_start_generates_config_and_starts_hostapd
    Wifi.start
    config
  end

  def test_channel_is_configured
    channel = rand 16

    old_channel = Wifi::Hostapd::DEFAULT_OPTIONS[:channel]
    Wifi::Hostapd::DEFAULT_OPTIONS[:channel] = channel

    Wifi.start

    assert_includes config, "channel=#{channel}"
  ensure
    Wifi::Hostapd::DEFAULT_OPTIONS[:channel] = old_channel
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
    driver = 'testdriver'
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

end
