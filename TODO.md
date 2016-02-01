# TODOs

### Missing Tests:

- STATIC `ctrl_interface` should point to socket
- DYNAMIC `hw_mode` should always switch to highest possible bandwidth
- DYNAMIC `ieee80211n` should be detected correctly and set to 0/1
- DYNAMIC `ieee80211d` should be detected correctly and set to 0/1
- STATIC `country_code` should be set to US
- STATIC `wme_enabled` should be 1
- STATIC `wmm_enabled` should be 1

- per section (private, public):
  - STATIC `mad_addr_acl` should be 0
  - STATIC `auth_algs` should be 1
  - STATIC `ignore_broadcast_ssid` should be 0
  - STATIC `wpa` should be set to 2
  - STATIC `wpa_key_mgmt` should be set to WPA-PSK
  - STATIC `rsn_pairwise` should be set to CCMP
  - DYNAMIC `bss` should be set to `interface`

### Broken Tests
- `driver` should be set to nl80211
- `channel` should be read from file

### Clean-Up
- `password` should be read from file
- `interface` should be configurable
- `Dnsmasq` should be removed
- `Config` should be specialized
- `Network#enabled?` should be removed
- `Hostapd#ieee80211n` should be implemented
- `Interface` class should be castrated
- `Network` class should be castrated
- 2nd definition of `Console` class should be removed
- Refactor the rest...
