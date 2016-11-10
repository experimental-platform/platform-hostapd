package main

import (
	"io/ioutil"
	"os"
	"path"
	"testing"

	"github.com/stretchr/testify/assert"
)

var expectedNets = []network{
	{
		Name:     "wl_private",
		Password: "foobarpassprivate",
		SSID:     "example-SSID",
	},
	{
		Name:     "wl_public",
		Password: "foobarpasspublic",
		SSID:     "example-SSID (public)",
	},
}

func makeTestCfgDir() (string, error) {
	configPath, err := ioutil.TempDir("", "")
	if err != nil {
		return "", err
	}

	err = ioutil.WriteFile(path.Join(configPath, "box_name"), []byte("example-SSID"), 0644)
	if err != nil {
		os.RemoveAll(configPath)
		return "", err
	}

	err = os.MkdirAll(path.Join(configPath, "system", "wifi"), 0755)
	if err != nil {
		os.RemoveAll(configPath)
		return "", err
	}
	err = os.MkdirAll(path.Join(configPath, "system", "wifi", "guest"), 0755)
	if err != nil {
		os.RemoveAll(configPath)
		return "", err
	}

	err = ioutil.WriteFile(path.Join(configPath, "system", "wifi", "enabled"), nil, 0644)
	if err != nil {
		os.RemoveAll(configPath)
		return "", err
	}
	err = ioutil.WriteFile(path.Join(configPath, "system", "wifi", "password"), []byte("foobarpassprivate"), 0644)
	if err != nil {
		os.RemoveAll(configPath)
		return "", err
	}
	err = ioutil.WriteFile(path.Join(configPath, "system", "wifi", "guest", "enabled"), nil, 0644)
	if err != nil {
		os.RemoveAll(configPath)
		return "", err
	}
	err = ioutil.WriteFile(path.Join(configPath, "system", "wifi", "guest", "password"), []byte("foobarpasspublic"), 0644)
	if err != nil {
		os.RemoveAll(configPath)
		return "", err
	}

	return configPath, nil
}

func TestGetSSID1(t *testing.T) {
	configPath, err := ioutil.TempDir("", "")
	assert.Nil(t, err)
	defer os.RemoveAll(configPath)

	gotSSID := getSSID(configPath)

	assert.Equal(t, "Protonet-default", gotSSID)
}

func TestGetSSID2(t *testing.T) {
	testSSID := "This is a test of SSID trim:   ß"
	trimmedSSID := "This is a test of SSID trim:"

	configPath, err := ioutil.TempDir("", "")
	assert.Nil(t, err)
	defer os.RemoveAll(configPath)

	err = ioutil.WriteFile(path.Join(configPath, "box_name"), []byte(testSSID), 0644)
	assert.Nil(t, err)

	gotSSID := getSSID(configPath)

	assert.Equal(t, trimmedSSID, gotSSID)
}

func TestGetNeededNetworks(t *testing.T) {
	configPath, err := makeTestCfgDir()
	assert.Nil(t, err)
	defer os.RemoveAll(configPath)

	networks, err := getNeededNetworks(configPath)
	assert.Nil(t, err)
	assert.Len(t, networks, 2)

	assert.Equal(t, expectedNets[0], networks[0])
	assert.Equal(t, expectedNets[1], networks[1])
}

func TestGenerateConfigFile(t *testing.T) {
	configPath, err := makeTestCfgDir()
	assert.Nil(t, err)
	defer os.RemoveAll(configPath)

	htcaps := &htCapabilities{
		DSSSCCKHT40:  true,
		HT40:         true,
		HT20SGI:      true,
		HT40SGI:      true,
		MaxAMSDU3839: true,
		RX_LDPC:      true,
		TXSTBC:       true,
		RXSTBC:       1,
	}

	expectedConfigFile := `ctrl_interface=/var/run/hostapd
driver=nl80211
hw_mode=g
ieee80211n=1
ieee80211d=1
ieee80211h=0
country_code=US
wme_enabled=1
wmm_enabled=1
channel=1
ht_capab=[HT40+][SHORT-GI-20][SHORT-GI-40][DSSS_CCK-40][MAX-AMSDU-3839][TX-STBC][RX-STBC1]
interface=wl_private
logger_stdout=-1
logger_stdout_level=2

ssid=example-SSID
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
wpa_psk=7190fee2e787b9d4d2ca4b4946d180e646727d9ca1d9adf664f84f85107de5fa

bss=wl_public
bssid=01:23:45:67:89:AB
ssid=example-SSID (public)
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
wpa_psk=46c0b02efacf5d5d077516a8bed48cbf4ee6e6de88308056c38b098d11a8edb1

`

	cfgFile, err := generateConfigFile(expectedNets, configPath, true, htcaps, "01:23:45:67:89:AB")
	assert.Nil(t, err)
	assert.Equal(t, expectedConfigFile, cfgFile)
}
