local cosock = require "cosock"
local socket = require "cosock.socket"
local http = cosock.asyncify "socket.http"
local ltn12 = require('ltn12')
local mdns = require ('st.mdns')
local log = require('log')
local json = require('dkjson')

local config = require('config')

local function fetch_device_info(url, path)
  log.info('probing device')

  local res = {}
  local _, status = http.request({
    url=url .. path,
    sink=ltn12.sink.table(res)
  })

  log.info ('fan status: ', table.concat(res))

  -- Monkey patch due to issues
  -- on ltn12 lib to fully sink
  -- JSON payload into table. Last
  -- bracket is missing.
  --
  -- Update below when fixed:
  --local raw_data = json.decode(table.concat(res))
  local data = json.decode(table.concat(res)..'}')
  if data and data['id'] then
    log.info('id: ', data.id)

    if data.id == 'fan-fan' then
      return {
        name='Air Purifier',
        vendor='ESPHome',
        location=url
      }
    end
  end
  return nil
end

local function find_device(driver)

  local known_devices = {}
  local device_list = driver:get_devices()
  for _, device in ipairs(device_list) do
    known_devices[device.device_network_id] = true
  end

  local discover_responses = mdns.discover("_http._tcp", "local") or {}
  for _, found in pairs(discover_responses.found) do
    if found.host_info.name:find '^purifier' then
      if found.service_info.name:find '^purifier' then
        local addr = found.host_info.address .. ':' .. found.host_info.port
        log.info('Found device ' .. found.host_info.name .. ' in ' .. addr)

        if not known_devices[addr] then
          local device = fetch_device_info('http://' .. addr, '/fan/Fan')
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
--    model = device.model,
--    vendor_provided_label = device.UDN
  }
  return driver:try_create_device(metadata)
end

local disco = {}

function disco.start(driver, opts, cons)
  local cycle = 0

  while cycle < 4 do
    cycle = cycle + 1
    log.info('Searching for EspHome Air Purifier devices...')

    local device = find_device(driver)
    if device then
      return create_device(driver, device)
    end
  end

end

return disco
