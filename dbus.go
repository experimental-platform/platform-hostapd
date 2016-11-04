package main

import (
	"fmt"

	"github.com/coreos/go-systemd/dbus"
)

func restartNetworkD(maxRetries int) error {

	conn, err := dbus.New()
	if err != nil {
		return err
	}

	c := make(chan string)
	var lastStatus string

	for i := 0; i < maxRetries; i++ {
		if _, err = conn.RestartUnit("systemd-networkd.service", "replace", c); err != nil {
			return err
		}

		lastStatus = <-c
		if lastStatus == "done" {
			return nil
		}
	}

	return fmt.Errorf("Failed to restart dbus - last attemt's status was '%s'", lastStatus)
}
