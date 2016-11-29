package main

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestHas5GHz(t *testing.T) {
	has, err := has5GHzSupport()
	assert.Nil(t, err)
	assert.True(t, has)
}

func TestGetHTCapabilities(t *testing.T) {
	expectedCaps := htCapabilities{
		RX_LDPC:      true,
		HT20:         false,
		HT40:         true,
		HT20SGI:      true,
		HT40SGI:      true,
		DSSSCCKHT40:  true,
		MaxAMSDU3839: true,
		MaxAMSDU7935: false,
		TXSTBC:       true,
		RXSTBC:       1,
	}

	caps, err := getHTCapabilities("phy0")
	assert.Nil(t, err)
	assert.Len(t, caps, 2)
	assert.Equal(t, expectedCaps, *caps[0])
	assert.Equal(t, expectedCaps, *caps[1])
}
