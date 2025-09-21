local config = {}
config.DEVICE_PROFILE='OpenBkPower.v1'
config.DEVICE_TYPE='LAN'
config.MC_ADDRESS='239.255.255.250'
config.MC_PORT=1900
config.MC_TIMEOUT=2
config.MSEARCH=table.concat({
  'M-SEARCH * HTTP/1.1',
  'HOST: 239.255.255.250:1900',
  'MAN: "ssdp:discover"',
  'MX: 4',
  'ST: upnp:rootdevice'
}, '\r\n')
return config
