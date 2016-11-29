package main

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

type testDBusConnectioner struct {
	WorksNthTime int
	triedNTimes  int
}

func (tdc *testDBusConnectioner) RestartUnit(unit string, mode string, c chan<- string) (int, error) {
	go func() {
		tdc.triedNTimes++
		if tdc.triedNTimes < tdc.WorksNthTime {
			c <- "failed"
		} else {
			c <- "done"
		}
	}()
	return 0, nil
}

func TestRestartNetworkD(t *testing.T) {
	newDBusConnection = func() (dbusConnectioner, error) {
		return &testDBusConnectioner{WorksNthTime: 5}, nil
	}

	err := restartNetworkD(6)
	assert.Nil(t, err)

	err = restartNetworkD(4)
	assert.NotNil(t, err)
}
