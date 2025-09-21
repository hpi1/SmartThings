local cosock = require "cosock"
local socket = require "cosock.socket"
local http = cosock.asyncify "socket.http"
local ltn12 = require('ltn12')
local log = require('log')
local xml2lua = require "xml2lua"
local xml_handler = require "xmlhandler.tree"

local config = require('config')
local Driver = require "st.driver"

local function parse_ssdp(data)
  local res = {}
  res.status = data:sub(0, data:find('\r\n'))
  for k, v in data:gmatch('([%w-]+): ([%a+-: /=]+)') do
    res[k:lower()] = v
  end
  return res
end

local function fetch_device_info(url)
  log.info('fetching device metadata')
  local res = {}
  local _, status = http.request({
    url=url,
    sink=ltn12.sink.table(res)
  })

  local xmlres = xml_handler:new()
  local xml_parser = xml2lua.parser(xmlres)
  xml_parser:parse(table.concat(res))

  local meta = xmlres.root.root.device

  if not xmlres.root or not meta then
    log.error('failed to fetch metadata from ' .. url)
    return nil
  end

  -- log.info('device UDN ', meta.UDN)
  log.info('device name ', meta.friendlyName)

  return {
    name=meta.friendlyName,
    vendor=meta.UDN,
    mn=meta.manufacturer,
    model=meta.modelName,
    location=meta.presentationURL
  }
end

local function find_device(driver)
  local known_devices = {}
  local device_list = driver:get_devices()
  for _, device in ipairs(device_list) do
    known_devices[device.device_network_id] = true
    -- log.info('  find_devices(): already known devices: ' .. device.device_network_id);
  end

  local upnp = socket.udp()
  upnp:setsockname('*', 0)
  upnp:setoption('broadcast', true)
  upnp:settimeout(config.MC_TIMEOUT)
  upnp:sendto(config.MSEARCH, config.MC_ADDRESS, config.MC_PORT)

  local res = upnp:receivefrom()
  while res ~= nil do
    local ssdp = parse_ssdp(res)
    if ssdp.server ~= nil then
      if ssdp.server:find 'OpenBk' then
        log.info('Found OpenBK device: ' .. ssdp.location)
        local device = fetch_device_info(ssdp.location)
        if device then
          if not known_devices[device.location] then
            upnp:close()
            return device
          end
          log.info('Skipping known device ' .. device.location)
        end
      end
    end
    -- try next
    res = upnp:receivefrom()
  end

  upnp:close()
  return nil
end

local function create_device(driver, device)
  log.info('creating device for ' .. device.location)
  local metadata = {
    type = config.DEVICE_TYPE,
    device_network_id = device.location,
    label = device.name,
    profile = config.DEVICE_PROFILE,
    manufacturer = device.mn,
    model = device.model,
    vendor_provided_label = device.UDN
  }
  return driver:try_create_device(metadata)
end

local disco = {}

function disco.start(driver, opts, cons)
  local cycle = 0

  while cycle < 4 do
    cycle = cycle + 1
    log.info('Searching for OpenBK devices...')

    local device = find_device(driver)
    if device then
      return create_device(driver, device)
    end
  end

end

return disco
