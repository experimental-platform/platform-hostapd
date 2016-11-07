package main

import (
	"bytes"
	"crypto/sha1"
	"fmt"
	"io/ioutil"
	"net"
	"os"
	"path"
	"strconv"
	"strings"
	"syscall"
	"text/template"
	"time"
	"unicode/utf8"

	log "github.com/Sirupsen/logrus"
	"github.com/docker/libcontainer/netlink"
	flags "github.com/jessevdk/go-flags"
	"golang.org/x/crypto/pbkdf2"
)

type network struct {
	Name     string
	SSID     string
	Password string
}

func getSSID(configPath string) string {
	filename := path.Join(configPath, "box_name")
	data, err := ioutil.ReadFile(filename)
	if err != nil {
		return "Protonet-default"
	}

	return strings.Trim(trimSSIDTo32Bytes(data), " \n\r\t")
}

// trimSSIDTo32Bytes trims an SSID to 32 bytes, making sure no UTF-8 rune is cut
func trimSSIDTo32Bytes(input []byte) string {
	for len(input) > 32 {
		_, lastRuneLen := utf8.DecodeLastRune(input)
		l := len(input)
		input = input[0 : l-lastRuneLen]
	}

	return string(input)
}

// was 'network_config'
func getNeededNetworks(configPath string) ([]network, error) {
	log.Debugln("fetching networks")
	ssid := getSSID(configPath)

	var networks []network

	log.Debugf("Looking for private network at %v", path.Join(configPath, "system", "wifi", "enabled"))
	_, err := os.Stat(path.Join(configPath, "system", "wifi", "enabled"))
	if err == nil {
		log.Debugln("Private network found, configuring...")
		passwdData, err2 := ioutil.ReadFile(path.Join(configPath, "system", "wifi", "password"))
		if err2 != nil {
			return nil, err2
		}

		networks = append(networks,
			network{
				Name:     "wl_private",
				SSID:     ssid,
				Password: strings.Trim(string(passwdData), " \n\r\t"),
			})
	} else {
		if !os.IsNotExist(err) {
			return nil, err
		}
	}

	log.Debugf("Looking for public network at %v\n", path.Join(configPath, "system", "wifi", "guest", "enabled"))
	_, err = os.Stat(path.Join(configPath, "system", "wifi", "guest", "enabled"))
	if err == nil {
		log.Debugln("Public network found, configuring...")
		passwdData, err2 := ioutil.ReadFile(path.Join(configPath, "system", "wifi", "guest", "password"))
		if err2 != nil {
			return nil, err2
		}

		networks = append(networks,
			network{
				Name:     "wl_public",
				SSID:     ssid + " (public)",
				Password: strings.Trim(string(passwdData), " \n\r\t"),
			})
	} else {
		if !os.IsNotExist(err) {
			return nil, err
		}
	}

	return networks, nil
}

func getBSSID(ifName string) (string, error) {
	i, err := net.InterfaceByName(ifName)
	if err != nil {
		return "", err
	}

	mac := i.HardwareAddr

	mac[0] |= 0x02
	mac[5] = 0x01

	return mac.String(), nil
}

func generateConfigFile(networks []network, configPath string) (string, error) {
	log.Debugln("hostapd configure")

	has5GHz, err := has5GHzSupport()
	if err != nil {
		return "", err
	}

	phys, err := getPhysicalInterfaces()
	if err != nil {
		return "", err
	}
	if len(phys) == 0 {
		return "", fmt.Errorf("No WiFi physical interfaces found")
	}

	htcaps, err := getHTCapabilities(phys[0])

	type cfgData struct {
		IEEE80211N bool
		Channel    uint
		HTCap      string
		Name       string
		SSID       string
		Pass       string

		SecondName string
		FirstBSSID string
		SecondSSID string
		SecondPass string
	}

	cfg := cfgData{
		IEEE80211N: has5GHz,
		Channel:    getConfiguredChannel(configPath),
		HTCap:      htcaps[0].AsConfigString(configPath),
		Name:       networks[0].Name,
		SSID:       networks[0].SSID,
		Pass:       wpaPassphrase(networks[0].SSID, networks[0].Password),
	}

	if len(networks) == 2 {
		bssid, err2 := getBSSID(networks[0].Name)
		if err2 != nil {
			return "", err2
		}

		cfg.SecondName = networks[1].Name
		cfg.FirstBSSID = bssid
		cfg.SecondSSID = networks[1].SSID
		cfg.SecondPass = wpaPassphrase(networks[1].SSID, networks[1].Password)
	}

	templateString := `
ctrl_interface=/var/run/hostapd
driver=nl80211
hw_mode=g
ieee80211n={{if .IEEE80211N}}1{{else}}0{{end}}
ieee80211d=1
ieee80211h=0
country_code=US
wme_enabled=1
wmm_enabled=1
channel={{.Channel}}
ht_capab={{.HTCap}}
interface={{.Name}}
logger_stdout=-1
logger_stdout_level=2

ssid={{.SSID}}
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
wpa_psk={{.Pass}}
{{if ne .SecondName ""}}
bss={{.SecondName}}
bssid={{.FirstBSSID}}
ssid={{.SecondSSID}}
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
wpa_psk={{.SecondPass}}
{{end}}
`

	tmpl, err := template.New("cfg").Parse(templateString)
	if err != nil {
		return "", err
	}

	bufferData := make([]byte, 10240)
	buffer := bytes.NewBuffer(bufferData)

	err = tmpl.Execute(buffer, cfg)
	if err != nil {
		return "", err
	}

	return buffer.String(), nil
}

func wpaPassphrase(ssid, passphrase string) string {
	pass := []byte(passphrase)
	salt := []byte(ssid)
	keyData := pbkdf2.Key(pass, salt, 4096, 32, sha1.New)
	return fmt.Sprintf("%x", keyData)
}

func getConfiguredChannel(configPath string) uint {
	filename := path.Join(configPath, "system", "wifi", "channel")
	data, err := ioutil.ReadFile(filename)
	if err != nil {
		return 1
	}

	i, err := strconv.Atoi(string(data))
	if err != nil {
		panic(fmt.Sprintf("Channel %s is not an int", string(data)))
	}

	if i <= 0 {
		panic(fmt.Sprintf("Channel %d is negative", i))
	}

	return uint(i)
}

func renameInterface(from string, to string) error {
	i, err := net.InterfaceByName(from)
	if err != nil {
		return err
	}

	err = netlink.NetworkLinkDown(i)
	if err != nil {
		return fmt.Errorf("netlink.NetworkLinkDown(\"%s\"): %s", i.Name, err.Error())
	}
	err = netlink.NetworkChangeName(i, to)
	if err != nil {
		return fmt.Errorf("netlink.NetworkChangeName(\"%s\", \"%s\"): %s", i.Name, to, err.Error())
	}
	err = netlink.NetworkLinkUp(i)
	if err != nil {
		return fmt.Errorf("netlink.NetworkLinkUp(\"%s\"): %s", to, err.Error())
	}

	return err
}

// was parts of 'interface_name'
func ensureInterfaceExist(name string, sleepTime int) error {
	interfaces, err := getLogicalInterfaces()
	if err != nil {
		return err
	}

	if len(interfaces) == 0 {
		return fmt.Errorf("Found no WiFi interfaces")
	}

	var interfaceIsThere = false
	for _, i := range interfaces {
		if i == name {
			interfaceIsThere = true
			break
		}
	}

	if !interfaceIsThere {
		log.Infof("Interface %s doesn't exist. Renaming %s -> %s", name, interfaces[0], name)
		err = renameInterface(interfaces[0], name)
		if err != nil {
			return err
		}

		time.Sleep(time.Second * time.Duration(sleepTime))
		log.Debug("Restarting systemd-networkd.")
		err = restartNetworkD(5)
		if err != nil {
			return fmt.Errorf("ensureInterfaceExist(): %s", err.Error())
		}
		time.Sleep(time.Second * time.Duration(sleepTime))
	}

	return nil
}

func main() {
	var opts struct {
		ConfigFile string `long:"config-file" required:"true" description:"path to hostapd.conf"`
		Binary     string `long:"hostapd-binary" required:"true" description:"path to hostapd binary"`
		SKVSPath   string `long:"skvs-dir" required:"true" decription:"path to SKVS root directory mountpoint"`
		Debug      bool   `long:"debug" description:"enable debug mode"`
		SleepTime  int    `long:"sleep-time" default:"5" description:"sleep time when retrying a systemd-networkd restart"`
	}

	_, err := flags.Parse(&opts)
	if err != nil {
		os.Exit(1)
	}

	if opts.Debug {
		log.SetLevel(log.DebugLevel)
		log.Debugln("Debug mode enabled.")
	}

	networks, err := getNeededNetworks(opts.SKVSPath)
	if err != nil {
		log.Fatalf("Failed to get network list: %v\n", err.Error())
	}

	if len(networks) == 0 {
		log.Println("No WiFi neworks are enabled. Exitting")
		os.Exit(0)
	}

	if len(networks) != 0 {
		log.Infoln("Found wifi networks:")
		for _, n := range networks {
			log.Infof(" - %s", n.Name)
		}
	}

	err = ensureInterfaceExist(networks[0].Name, opts.SleepTime)
	if err != nil {
		log.Fatal(err)
	}

	cfg, err := generateConfigFile(networks, opts.SKVSPath)
	if err != nil {
		log.Fatalf("Failed to generate config file: %v", err.Error())
	}

	log.Debugf("Generated config file:\n%s", cfg)
	log.Infof("Writing hostapd config to '%s'", opts.ConfigFile)
	err = ioutil.WriteFile(opts.ConfigFile, []byte(cfg), 0644)
	if err != nil {
		log.Fatalf("Failed to save config file: %s", err.Error())
	}

	log.Info("Starting hostapd")
	err = syscall.Exec(opts.Binary, []string{opts.Binary, opts.ConfigFile}, []string{})
	if err != nil {
		log.Fatal(err)
	}
}
