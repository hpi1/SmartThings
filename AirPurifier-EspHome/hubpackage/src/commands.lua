local caps = require('st.capabilities')
local utils = require('st.utils')
local neturl = require('net.url')
local log = require('log')
local json = require('dkjson')
local cosock = require "cosock"
local http = cosock.asyncify "socket.http"
local ltn12 = require('ltn12')

local command_handler = {}

local cap_status = caps["partyvoice23922.onvifstatus"]

function refresh_fan(device)
  log.info(' === REFRESH FAN ===')

  local success, data = command_handler.send_lan_command(device.device_network_id, 'GET', 'fan/Fan')
  if not success then
    return nil
  end

  local data = json.decode(table.concat(data)..'}')
  if data then
    device:set_field('fan_max', data.speed_count)

    local p = math.floor(data.speed_level * 100 / data.speed_count)
    device:emit_event(caps.switchLevel.level(p), { visibility = { displayed = false } })

    if data.state == 'ON' then
      return device:emit_event(caps.switch.switch.on(), { visibility = { displayed = false } })
    else
      return device:emit_event(caps.switch.switch.off(), { visibility = { displayed = false } })
    end
  end
  return nil
end

function command_handler.on_off(_, device, command)
  local on_off = command.command

  log.info('set switch ' .. on_off)
  if on_off == 'ON' or on_off == 'on' then
    on_off = "turn_on"
  else
    on_off = "turn_off"
  end

  local success, data = command_handler.send_lan_command(
        device.device_network_id, 'POST', 'fan/Fan/' .. on_off, '')
  if success then
    refresh_fan(device)
  else
    log.error('set switch: no response from device')
  end

  device.thread:call_with_delay(1, function()
            refresh_fan(device)
        end, "refresh_fan")
end

function command_handler.set_level(_, device, command)
  local cmd = command.command
  local val = command.args.level
  local fan_max = device:get_field('fan_max')
  local level = math.floor(val * fan_max / 100)

  local success, data = command_handler.send_lan_command(
        device.device_network_id, 'POST', 'fan/Fan/turn_on?speed_level=' .. level, '')
  if success then
      refresh_fan(device)
  else
    log.error('set fan: no response from device')
  end

  device.thread:call_with_delay(1, function()
              refresh_fan(device)
              end, "refresh_fan")
end

function command_handler.refresh(_, device)
  refresh_fan(device)

  local success, data = command_handler.send_lan_command(
        device.device_network_id, 'GET', 'sensor/PM2.5%20Density')
  if success then
    local data = json.decode(table.concat(data)..'}')
    if data then
      --device:emit_event(caps.fineDustSensor.fineDustLevel({value = data.value, unit = "µg/m³" }))
      device:emit_component_event(
          device.profile.components.sensor,
          caps.fineDustSensor.fineDustLevel({value = data.value})
      )

      device:emit_component_event(
          device.profile.components.info,
          cap_status.status({value = 'Ok '}, { visibility = {displayed = false, ephemeral = true }})
      )
      device:online()

--    capabilities.airfineDustHealthConcern.fineDustHealthConcern(status) - - 'good' 'unhealthy'

      return device:online()
    end
  end

  device:emit_component_event(
      device.profile.components.info,
      cap_status.status({value = 'Offline '}, { visibility = {displayed = false, ephemeral = true }})
  )
  return device:offline()
end


function command_handler.send_lan_command(url, method, path, sendbody)
  local dest_url = 'http://' .. url..'/'..path
  local res_body = {}
  local sendheaders = {}

  http.TIMEOUT = 5

  if sendbody then
    sendheaders["Content-Length"] = string.len(sendbody)
  else
    sendheaders["Content-Length"] = 0
  end

  local retries = 0
  while retries < 3 do
    local code

    if sendbody then
      _, code = http.request{
        method = method,
        url = dest_url,
        headers = sendheaders,
        source = ltn12.source.string(sendbody),
        sink = ltn12.sink.table(res_body)
       }
    else
      _, code = http.request({
        method = method,
        url = dest_url,
--        headers = sendheaders,
        sink = ltn12.sink.table(res_body)
      })
    end

    if code == 200 then
      return true, res_body
    end
    log.error('HTTP request ', dest_url, ' failed: ', code)
    retries = retries + 1
  end
  return false, nil
end

return command_handler
