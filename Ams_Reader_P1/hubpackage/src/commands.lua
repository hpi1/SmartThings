local caps = require('st.capabilities')
local log = require('log')
local json = require('dkjson')
local cosock = require "cosock"
local http = cosock.asyncify "socket.http"
local ltn12 = require('ltn12')

local command_handler = {}

local cap_price = caps["gardengarden49042.kwhprice"]
local cap_status = caps["partyvoice23922.onvifstatus"]

------------------
-- Refresh command
function command_handler.refresh(_, device)

  log.info('refresh')

  local success, data = command_handler.send_lan_command(
      device.device_network_id, 'GET', 'data.json')

  if success then
    -- Monkey patch due to issues
    -- on ltn12 lib to fully sink
    -- JSON payload into table. Last
    -- bracket is missing.
    --
    -- Update below when fixed:
    --local raw_data = json.decode(table.concat(data))
    local data = json.decode(table.concat(data)..'}')
    if data then
      log.info('export: ', data.e)
      log.info('import: ', data.i)

      local han_status = 'HAN disconnected'
      if data.hm == 0 then han_status = 'Initializing' end
      if data.hm == 1 then han_status = 'Online' end
      if data.hm == 2 then han_status = 'Delayed data' end
      device:emit_event(cap_status.status(han_status))

      -- data.i = import, data.e = export, data.w = import - export
      device:emit_event(caps.powerMeter.power(data.w), { visibility = { displayed = false } })
      device:emit_event(caps.energyMeter.energy({value = data.ic, unit = "kWh" }, { visibility = { displayed = false } }))

      device:emit_component_event(device.profile.components.phase1,
          caps.powerMeter.power(data.l1.p - data.l1.q, { visibility = { displayed = false } }));
      device:emit_component_event(device.profile.components.phase2,
          caps.powerMeter.power(data.l2.p - data.l1.q, { visibility = { displayed = false } }));
      device:emit_component_event(device.profile.components.phase3,
          caps.powerMeter.power(data.l3.p - data.l1.q, { visibility = { displayed = false } }));
      device:emit_component_event(device.profile.components.phase1,
          caps.voltageMeasurement.voltage(data.l1.u, { visibility = { displayed = false } }));
      device:emit_component_event(device.profile.components.phase2,
          caps.voltageMeasurement.voltage(data.l2.u, { visibility = { displayed = false } }));
      device:emit_component_event(device.profile.components.phase3,
          caps.voltageMeasurement.voltage(data.l3.u, { visibility = { displayed = false } }));

      device:online()
    else
      device:offline()
    end

    -- update current price
    local price = '(unknown)'
    local success, data = command_handler.send_lan_command(
        device.device_network_id, 'GET', 'energyprice.json')

    if success then
      local data = json.decode(table.concat(data)..'}')
      if data and data['00'] then
        price = data['00']*100.0
      end
    end
    device:emit_event(cap_price.price({value=price, unit='c/kWh'}))

    return
  end

  log.info('failed to refresh device state')
  device:emit_component_event(device.profile.components.info, cap_status.status('Disconnected'))
  device:offline()
end

------------------------
-- Send LAN HTTP Request
function command_handler.send_lan_command(url, method, path)
  local dest_url = 'http://' .. url..'/'..path
  local res_body = {}

  http.TIMEOUT = 5

  local retries = 0
  while retries < 3 do

    local _, code = http.request({
      method=method,
      url=dest_url,
      sink=ltn12.sink.table(res_body)
    })

    if code == 200 then
      return true, res_body
    end
    log.error('HTTP request ', dest_url, ' failed: ', code)
    retries = retries + 1
  end
  return false, nil
end

return command_handler
