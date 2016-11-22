package main

import (
	"syscall"

	"github.com/hkwi/nlgo"
)

func getLogicalInterfaces() ([]string, error) {
	hub, err := nlgo.NewGenlHub()
	if err != nil {
		return nil, err
	}

	family := hub.Family("nl80211")
	resp, err := hub.Sync(family.DumpRequest(nlgo.NL80211_CMD_GET_INTERFACE))
	if err != nil {
		return nil, err
	}

	ifMap := make(map[string]struct{})

	for _, msg := range resp {
		switch msg.Header.Type {
		case syscall.NLMSG_DONE:
			// do nothing
		case syscall.NLMSG_ERROR:
			return nil, nlgo.NlMsgerr(msg.NetlinkMessage)
		case nlgo.GENL_ID_CTRL:
			// do nothing
		default:
			attrs, err := nlgo.Nl80211Policy.Parse(msg.Body())
			if err != nil {
				return nil, err
			}

			ifName := string(attrs.(nlgo.AttrMap).Get(nlgo.NL80211_ATTR_IFNAME).(nlgo.NulString))
			ifMap[ifName] = struct{}{}
		}
	}

	var ifList []string

	for k := range ifMap {
		ifList = append(ifList, k)
	}

	return ifList, nil
}

func getPhysicalInterfaces() ([]string, error) {
	hub, err := nlgo.NewGenlHub()
	if err != nil {
		panic(err)
	}

	family := hub.Family("nl80211")
	resp, err := hub.Sync(family.DumpRequest(nlgo.NL80211_CMD_GET_WIPHY))
	if err != nil {
		panic(err)
	}

	phyMap := make(map[string]struct{})

	for _, msg := range resp {
		switch msg.Header.Type {
		case syscall.NLMSG_DONE:
			// do nothing
		case syscall.NLMSG_ERROR:
			return nil, nlgo.NlMsgerr(msg.NetlinkMessage)
		case nlgo.GENL_ID_CTRL:
			// do nothing
		default:
			attrs, err := nlgo.Nl80211Policy.Parse(msg.Body())
			if err != nil {
				return nil, err
			}

			phyName := string(attrs.(nlgo.AttrMap).Get(nlgo.NL80211_ATTR_WIPHY_NAME).(nlgo.NulString))
			phyMap[phyName] = struct{}{}
		}
	}

	var phyList []string

	for k := range phyMap {
		phyList = append(phyList, k)
	}

	return phyList, nil
}
