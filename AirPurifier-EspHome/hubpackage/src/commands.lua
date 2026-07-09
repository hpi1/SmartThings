local caps = require('st.capabilities')
local utils = require('st.utils')
local neturl = require('net.url')
local log = require('log')
local json = require('dkjson')
local cosock = require "cosock"
local http = cosock.asyncify "socket.http"
local ltn12 = require('ltn12')
local socket = cosock.socket

local command_handler = {}

local cap_status = caps["partyvoice23922.onvifstatus"]

-- status text

local devstate = {}

function set_status(device, idx, value)
    if devstate[idx] == value then
        return
    end
    devstate[idx] = value

    local text = devstate[0]
    device:emit_component_event(
        device.profile.components.info,
        cap_status.status(
            {value = text}, {visibility = {displayed = false, ephemeral = true }}
        )
    )
    local text = 'Filter used: ' .. devstate[2] .. ' (' .. devstate[3] .. ') - ' .. devstate[1]
    device:emit_component_event(
        device.profile.components.filter,
        cap_status.status(
            {value = text}, {visibility = {displayed = false, ephemeral = true }}
        )
    )
end

-- component events

function pm2str(pm)
    if pm < 12 then
      return 'good'
    elseif pm < 35 then
      return 'moderate'
    elseif pm < 55 then
      return 'slightlyUnhealthy'
    elseif pm < 150 then
      return 'unhealthy'
    elseif pm < 250 then
      return 'veryUnhealthy'
    else
      return 'hazardous'
    end
end

function gen_fan_events(device, data)
    device:set_field('fan_max', data.speed_count)

    local p = math.floor(data.speed_level * 100 / data.speed_count)
    device:emit_event(caps.switchLevel.level(p), { visibility = { displayed = false } })

    if data.state == 'ON' then
      return device:emit_event(caps.switch.switch.on(), { visibility = { displayed = false } })
    else
      return device:emit_event(caps.switch.switch.off(), { visibility = { displayed = false } })
    end

    return device:online()
end

function gen_pm25_events(device, data)
    device:emit_component_event(
        device.profile.components.sensor,
        caps.fineDustSensor.fineDustLevel({value = data.value})
    )
    device:emit_component_event(
        device.profile.components.sensor,
        caps.fineDustHealthConcern.fineDustHealthConcern({value = pm2str(data.value)})
    )
end

-- event stream listener

function parse_event(device, line, ip)
    line = string.sub(line, 6)
    local data = json.decode(line..'}')
    if data then
        -- log.error(' *** PARSED ***  id=' .. data.name_id )
        if data.name_id == 'fan/Fan' then
            gen_fan_events(device, data)
            set_status(device, 0, 'Connected: ' .. ip)
        end
        if data.name_id == 'sensor/PM2.5 Density' then
            gen_pm25_events(device, data)
        end
        if data.name_id == 'text_sensor/Device Fault' then
            set_status(device, 1, data.state)
        end
        if data.name_id == 'sensor/Filter Life Level' then
            set_status(device, 2, data.state)
        end
        if data.name_id == 'sensor/Filter Used Time' then
            set_status(device, 3, data.state)
        end
    end
end

function command_handler.monitor_device_connection(device)

  cosock.socket.sleep(5)

  while true do
    device:offline()

    local ip, port = string.match(device.device_network_id, "([^:]+):([^:]+)")

    devstate[0] = ''
    devstate[1] = ''
    devstate[2] = ''
    devstate[3] = ''
    set_status(device, 0, 'Connecting to ' .. ip)

    local sock = socket.tcp()
    sock:settimeout(30) -- Set a small timeout

    local success, err = sock:connect(ip, port)
    if not success then
        log.error("Connection failed: ", err)
        device:offline()
        return
    end
    log.error('Connected to ' .. ip .. ':' .. port)

    sock:send('GET /events HTTP/1.1\r\nAccept: */*\r\nConnection: keep-alive\r\nHost: ' .. ip .. '\r\n\r\n')

    local retry = 3
    while retry > 0 do

        local line, status, partial = sock:receive("*l") -- Read by line
        if line then
            -- Parse the incoming data and update SmartThings state
            if line:find '^event: state' then
                local line, status, partial = sock:receive("*l") -- Read by line
                if line and line:find '^data:' then
                    parse_event(device, line, ip)
                end
            end
        elseif status == "timeout" then
            -- Expected non-blocking timeout, continue looping
            log.error("Received timeout")
            retry = retry - 1
        elseif status == "closed" then
            log.error("Socket closed by remote device. Reconnecting...")
            sock:close()
            break -- Break loop and trigger a reconnect
        else
            log.error("Event " .. status)
        end
--        cosock.socket.sleep(1)
    end

    sock:close()
    cosock.socket.sleep(10) -- Reconnect later
  end
end

-- (manual) refresh

function refresh_fan(device)
  log.info(' === REFRESH FAN ===')

  local success, data = command_handler.send_lan_command(device.device_network_id, 'GET', 'fan/Fan')
  if success then
    local data = json.decode(table.concat(data)..'}')
    if data then
      gen_fan_events(device, data)
      set_status(device, 0, 'Online')
    end
    return device:online()
  end

  set_status(device, 0, 'Offline')
  return device:offline()
end

function refresh_pm25(device)
  local success, data = command_handler.send_lan_command(
        device.device_network_id, 'GET', 'sensor/PM2.5%20Density')
  if success then
    local data = json.decode(table.concat(data)..'}')
    if data then
      gen_pm25_events(device, data)
    end
  end
end

-- commands

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
  refresh_pm25(device)
end

-- http request

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
