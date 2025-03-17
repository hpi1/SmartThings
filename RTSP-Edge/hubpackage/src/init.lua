--[[

  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
  except in compliance with the License. You may obtain a copy of the License at:

      http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software distributed under the
  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
  either express or implied. See the License for the specific language governing permissions
  and limitations under the License.


  DESCRIPTION

--]]

local cosock = require "cosock"
local socket = require "cosock.socket"
local caps   = require "st.capabilities"
local Driver = require "st.driver"
local log    = require "log"

local thisDriver = {}

local function create_device(driver)

  log.info("Creating device")

  local devices = driver:get_devices()

  local MFG_NAME = 'ph'
  local MODEL = 'RTSP Stream'
  local VEND_LABEL = 'RTSP Stream #' .. tostring(#devices + 1)
  local ID = 'RtspStreamV1' .. tostring(socket.gettime())
  local PROFILE ='rtsp-stream-uninit.v1'

  local create_device_msg = {
                              type = "LAN",
                              device_network_id = ID,
                              label = VEND_LABEL,
                              profile = PROFILE,
                              manufacturer = MFG_NAME,
                              model = MODEL,
                              vendor_provided_label = VEND_LABEL,
                            }

  assert (driver:try_create_device(create_device_msg), "failed to create device")

end

-----------------------------------------------------------------------
--                    COMMAND HANDLERS
-----------------------------------------------------------------------

local function handle_refresh(_, device, command)

end

------------------------------------------------------------------------
--                REQUIRED EDGE DRIVER HANDLERS
------------------------------------------------------------------------


local function device_doconfigure (_, device)
end


local function device_removed(driver, device)
end


local function handler_driverchanged(driver, device, event, args)
  device:online()
end

local function shutdown_handler(driver, event)
end


local function discovery_handler(driver, _, should_continue)

  -- create uninitialized device if no unitialized devices exist
  local device_list = driver:get_devices()
  for _, device in ipairs(device_list) do
    if device.preferences.deviceurl:find('192.168.n.n') then
      log.info(' uninitialized device found')
      return
    end
  end

  log.info('no uninitialized devices found')
  create_device(driver)
end

local function handle_stream(driver, device, command)

  log.debug('Streaming handler invoked with command', command.command)

  if command.command == 'startStream' then
    local live_video = {
       ['InHomeURL'] = device.preferences.deviceurl,
       ['OutHomeURL'] = ''
    }

    if live_video.InHomeURL:find('192.168.n.n') then
      log.debug ('Not configured: ', live_video.InHomeURL)
      device:try_update_metadata({profile='rtsp-stream-uninit.v1'})
      live_video.InHomeURL = ''
    else
      log.debug ('Providing stream URL to SmartThings:', live_video.InHomeURL)
    end
    device:emit_event(caps.videoStream.stream(live_video, { visibility = { displayed = false } }))
  end
end

local function device_init(driver, device)

  log.debug(device.id .. ": " .. device.device_network_id .. " initializing")

  local devprofile = 'rtsp-stream.v1'
  if device.preferences.deviceurl:find('192.168.n.n') then
    log.debug ('device not configured')
    devprofile = 'rtsp-stream-uninit.v1'
  end
  device:try_update_metadata({profile=devprofile})

  device:emit_event(caps.healthCheck.healthStatus('online'))
  device:emit_event(caps.motionSensor.motion('inactive'))
  device:online()

  handle_stream(driver, device, {command='startStream'})
end

local function device_added (driver, device)
  log.info(device.id .. ": " .. device.device_network_id .. "> ADDED")
  device:online()
end

local function handler_infochanged (driver, device, event, args)

  log.debug ('Info changed handler invoked')

  if args.old_st_store.preferences then
    if args.old_st_store.preferences.deviceurl ~= device.preferences.deviceurl then
      log.info ('URL changed to: ', device.preferences.deviceurl)
      device_init(driver, device)
    end
  else
    log.warn ('Old preferences missing')
  end

end


thisDriver = Driver("thisDriver", {
  discovery = discovery_handler,
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    driverSwitched = handler_driverchanged,
    infoChanged = handler_infochanged,
    doConfigure = device_doconfigure,
    removed = device_removed
  },
  driver_lifecycle = shutdown_handler,
  capability_handlers = {
    [caps.videoStream.ID] = {
      [caps.videoStream.commands.startStream.NAME] = handle_stream,
      [caps.videoStream.commands.stopStream.NAME] = handle_stream,
    },
    [caps.refresh.ID] = {
      [caps.refresh.commands.refresh.NAME] = handle_refresh,
    },
  }
})

log.info ('RTSP Stream v1.0 Started')

thisDriver:run()
