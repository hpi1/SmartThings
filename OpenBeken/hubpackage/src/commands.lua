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

function refresh_switch(device, data)
  local data = json.decode(table.concat(data)..'}')
  if data then
    if data.POWER == 'ON' then
      return device:emit_event(caps.switch.switch.on(), { visibility = { displayed = false } })
    end
    return device:emit_event(caps.switch.switch.off(), { visibility = { displayed = false } })
  end
end

function command_handler.on_off(_, device, command)
  local on_off = command.command
  log.info('set switch ' .. on_off)

  local success, data = command_handler.send_lan_command(
      device.device_network_id, 'GET', 'cm?cmnd=power%20' .. on_off)
  if success then
    return refresh_switch(device, data)
  end

  log.error('no response from device')
end

function command_handler.refresh(_, device)
  local success, data = command_handler.send_lan_command(device.device_network_id, 'GET', 'cm?cmnd=power')
  if success then
    refresh_switch(device, data)

    local success, data = command_handler.send_lan_command(device.device_network_id, 'GET', 'cm?cmnd=sensors')
    if success then
      local data = json.decode(table.concat(data)..'}')
      if data then
        device:emit_event(cap_status.status({value = 'Ok ' .. data.Time}, { visibility = {displayed = false, ephemeral = true }}))
        local rounded_kwh = tonumber(string.format("%.3f", data.ENERGY.ConsumptionTotal/1000.0))
        device:emit_event(caps.energyMeter.energy({value = rounded_kwh, unit = "kWh" }))
        device:emit_event(caps.powerMeter.power({value = data.ENERGY.Power, unit = "W"}))
        device:emit_event(caps.currentMeasurement.current({value = data.ENERGY.Current, unit = "A"}, { visibility = { displayed = false, ephemeral = true }}))
        device:emit_event(caps.voltageMeasurement.voltage({value = data.ENERGY.Voltage, unit = "V"}, { visibility = { displayed = false, ephemeral = true }}))
        return device:online()
      end
    end
  end

  device:emit_event(cap_status.status({value = 'Offline'}, { visibility = {displayed = false, ephemeral = true }}))
  device:offline()
end

function command_handler.send_lan_command(url, method, path)
  local dest_url = url..path
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
