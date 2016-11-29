package main

import (
	"fmt"
	"reflect"
	"syscall"

	"github.com/hkwi/nlgo"
)

func has5GHzSupport() (bool, error) {
	hub, err := newGenHub()
	if err != nil {
		return false, err
	}

	family := hub.Family("nl80211")
	resp, err := hub.Sync(family.DumpRequest(nlgo.NL80211_CMD_GET_WIPHY))
	if err != nil {
		return false, err
	}

	for _, msg := range resp {
		switch msg.Header.Type {
		case syscall.NLMSG_DONE:
			// do nothing
		case syscall.NLMSG_ERROR:
			return false, nlgo.NlMsgerr(msg.NetlinkMessage)
		case nlgo.GENL_ID_CTRL:
			// do nothing
		default:
			if attrs, err := nlgo.Nl80211Policy.Parse(msg.Body()); err != nil {
				return false, err
			} else {
				support := attrs.(nlgo.AttrMap).Get(nlgo.NL80211_ATTR_SUPPORT_5_MHZ)
				if support == nil {
					continue
				}

				return bool(support.(nlgo.Flag)), nil
			}
		}
	}

	return false, nil
}

type htCapabilities struct {
	RX_LDPC      bool
	HT20         bool
	HT40         bool
	HT20SGI      bool
	HT40SGI      bool
	DSSSCCKHT40  bool
	MaxAMSDU3839 bool
	MaxAMSDU7935 bool
	TXSTBC       bool
	RXSTBC       uint8
}

func (c *htCapabilities) AsConfigString(configPath string) string {
	var s string
	if c.HT20 {
		s = s + "[HT20]"
	}
	if c.HT40 {
		if getConfiguredChannel(configPath) < 8 {
			s = s + "[HT40+]"
		} else {
			s = s + "[HT40-]"
		}
	}
	if c.HT20SGI {
		s = s + "[SHORT-GI-20]"
	}
	if c.HT40SGI {
		s = s + "[SHORT-GI-40]"
	}
	if c.DSSSCCKHT40 {
		s = s + "[DSSS_CCK-40]"
	}
	if c.MaxAMSDU3839 {
		s = s + "[MAX-AMSDU-3839]"
	}
	if c.TXSTBC {
		s = s + "[TX-STBC]"
	}
	if c.RXSTBC == 1 {
		s = s + "[RX-STBC1]"
	}

	return s
}

func getBandPolicies(phy string) ([]nlgo.Attr, error) {
	hub, err := newGenHub()
	if err != nil {
		panic(err)
	}

	family := hub.Family("nl80211")
	resp, err := hub.Sync(family.DumpRequest(nlgo.NL80211_CMD_GET_WIPHY))
	if err != nil {
		panic(err)
	}

	for _, msg := range resp {
		switch msg.Header.Type {
		case syscall.NLMSG_DONE:
			// do nothing
		case syscall.NLMSG_ERROR:
			return nil, nlgo.NlMsgerr(msg.NetlinkMessage)
		case nlgo.GENL_ID_CTRL:
			// do nothing
		default:
			if attrs, err := nlgo.Nl80211Policy.Parse(msg.Body()); err != nil {
				return nil, err
			} else {
				phyName := string(attrs.(nlgo.AttrMap).Get(nlgo.NL80211_ATTR_WIPHY_NAME).(nlgo.NulString))
				if phyName != phy {
					continue
				}

				bands := attrs.(nlgo.AttrMap).Get(nlgo.NL80211_ATTR_WIPHY_BANDS)
				if bands == nil {
					continue
				}

				return bands.(nlgo.AttrSlice), nil
			}
		}
	}

	return nil, fmt.Errorf("No bands found for phy '%s'", phy)
}

func getHTCapabilities(phy string) ([]*htCapabilities, error) {
	bands, err := getBandPolicies(phy)
	if err != nil {
		return nil, err
	}

	var output []*htCapabilities
	for _, band := range bands {
		caps, err := getHTCapabilitiesFromBand(band)
		if err != nil {
			return nil, err
		}
		output = append(output, caps)
	}

	return output, nil
}

func getHTCapabilitiesFromBand(b nlgo.Attr) (*htCapabilities, error) {
	aMap, ok := b.Value.(nlgo.AttrMap)
	if !ok {
		return nil, fmt.Errorf("getHTCapabilitiesFromBand: input is not a nlgo.AttrMap but a '%s'", reflect.TypeOf(b).Name())
	}

	if aMap.Policy.Prefix != "BAND" {
		return nil, fmt.Errorf("getHTCapabilitiesFromBand: input is not a 'BAND' but a '%s'", aMap.Policy.Prefix)
	}

	caps := parseHTCapabilities(aMap.Get(nlgo.NL80211_BAND_ATTR_HT_CAPA).(nlgo.U16))
	return caps, nil
}

func parseHTCapabilities(c nlgo.U16) *htCapabilities {
	return &htCapabilities{
		RX_LDPC:      c&0x0001 == 0x0001,
		HT20:         c&0x0002 == 0,
		HT40:         c&0x0002 == 0x0002,
		HT20SGI:      c&0x0020 == 0x0020,
		HT40SGI:      c&0x0040 == 0x0040,
		DSSSCCKHT40:  c&0x1000 == 0x1000,
		MaxAMSDU3839: c&0x0800 == 0,
		MaxAMSDU7935: c&0x0800 == 0x0800,
		TXSTBC:       c&0x0080 == 0x0080,
		RXSTBC:       uint8((c >> 8) & 0x3),
	}
}
