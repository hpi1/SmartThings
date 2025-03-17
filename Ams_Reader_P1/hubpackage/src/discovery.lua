local cosock = require "cosock"
local socket = require "cosock.socket"
local http = cosock.asyncify "socket.http"
local ltn12 = require('ltn12')
local mdns = require ('st.mdns')
local log = require('log')
local xml2lua = require "xml2lua"
local xml_handler = require "xmlhandler.tree"

local config = require('config')


local function fetch_device_info(url, path)
  log.info('fetching device metadata')
  local res = {}
  local _, status = http.request({
    url=url .. path,
    sink=ltn12.sink.table(res)
  })

  -- log.info ('', table.concat(res))

  local xmlres = xml_handler:new()
  local xml_parser = xml2lua.parser(xmlres)
  xml_parser:parse(table.concat(res))

  -- device metadata
  local meta = xmlres.root.root.device

  if not xmlres.root or not meta then
    log.error('failed to fetch metadata from ' .. url)
    return nil
  end

  log.info('device UDN ', meta.UDN)

  return {
    name=meta.friendlyName,
    vendor=meta.UDN,
    mn=meta.manufacturer,
    model=meta.modelName,
    location=url
  }
end

local function find_device()

  local known_devices = {}
  local device_list = driver:get_devices()
  for _, device in ipairs(device_list) do
    known_devices[device.device_network_id] = true
  end

  local discover_responses = mdns.discover("_http._tcp", "local") or {}
  -- +;wlp1s0;IPv4;ams-78d4;_http._tcp;local
  -- log.info('mdns: ', discover_responses)
  for idx, found in ipairs(discover_responses.found) do

--  if found ~= nil and found.service_info.service_type == "_http._tcp"
--      and not net_utils.validate_ipv4_string(found.host_info.address) then

    if found.host_info.name:find '^ams-' then
      -- log.info(' Found AMS in MDNS host name')
      if found.service_info.name:find '^ams-' then
        -- log.debug('found ams in service info name')
        local addr = found.host_info.address .. ':' .. found.host_info.port
        log.info('Found device ' .. found.host_info.name .. ' in ' .. addr)
        log.info('    service info name: ', found.service_info.name)
        log.info('    service info type: ', found.service_info.service_type)

        if not known_devices[addr] then
          local device = fetch_device_info('http://' .. addr, '/ssdp/schema.xml')
          if device then
            device.location = addr
            -- name = found.host_info.name
            return device
          end
        end
      end
    end
  end
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
    log.info('Searching for AmsReader devices...')

    local device = find_device()
    if device then
      return create_device(driver, device)
    end
  end

end

return disco
