package main

import (
	"fmt"
	"reflect"
	"syscall"

	"github.com/hkwi/nlgo"
)

func getFreqsFromNl80211Policy(b nlgo.NlaValue) ([]uint32, error) {
	aMap, ok := b.(nlgo.AttrMap)
	if !ok {
		return nil, fmt.Errorf("getFreqsFromNl80211Policy: input is not a nlgo.AttrMap but a '%s'", reflect.TypeOf(b).Name())
	}

	if aMap.Policy.Prefix != "NL80211_ATTR" {
		return nil, fmt.Errorf("getFreqsFromNl80211Policy: input is not a 'NL80211_ATTR' but a '%s'", aMap.Policy.Prefix)
	}

	bands := aMap.Get(nlgo.NL80211_ATTR_WIPHY_BANDS)
	if bands == nil {
		return []uint32{}, nil
	}

	var values []uint32
	for _, band := range bands.(nlgo.AttrSlice) {
		freqs, err := getFreqsFromBand(band)
		if err != nil {
			panic(err)
		}

		values = append(values, freqs...)
	}

	return values, nil
}

func getFreqsFromBand(b nlgo.Attr) ([]uint32, error) {
	aMap, ok := b.Value.(nlgo.AttrMap)
	if !ok {
		return nil, fmt.Errorf("getFreqsFromBand: input is not a nlgo.AttrMap but a '%s'", reflect.TypeOf(b).Name())
	}

	if aMap.Policy.Prefix != "BAND" {
		return nil, fmt.Errorf("getFreqFromFreq: input is not a 'BAND' but a '%s'", aMap.Policy.Prefix)
	}

	var values []uint32
	freqs := aMap.Get(nlgo.NL80211_BAND_ATTR_FREQS)
	for _, f := range freqs.(nlgo.AttrSlice) {
		num, err := getFreqFromFreq(f)
		if err != nil {
			return nil, err
		}

		values = append(values, num)
	}

	return values, nil
}

func getFreqFromFreq(f nlgo.Attr) (uint32, error) {
	aMap, ok := f.Value.(nlgo.AttrMap)
	if !ok {
		return 0, fmt.Errorf("getFreqFromFreq: input is not a nlgo.AttrMap but a '%s'", reflect.TypeOf(f).Name())
	}

	if aMap.Policy.Prefix != "FREQUENCY_ATTR" {
		return 0, fmt.Errorf("getFreqFromFreq: input is not a 'FREQUENCY_ATTR' but a '%s'", aMap.Policy.Prefix)
	}

	return uint32(aMap.Get(nlgo.NL80211_FREQUENCY_ATTR_FREQ).(nlgo.U32)), nil
}

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
