local Driver = require('st.driver')
local caps = require('st.capabilities')

-- local imports
local discovery = require('discovery')
local lifecycles = require('lifecycles')
local commands = require('commands')

local cap_status = caps["partyvoice23922.onvifstatus"]
local cap_refresh = caps["partyvoice23922.refresh"]

--------------------
-- Driver definition
local driver =
  Driver(
    'LAN-AirPurifier-EspHome',
    {
      discovery = discovery.start,
      lifecycle_handlers = lifecycles,
      supported_capabilities = {
        caps.switch,
        caps.switchLevel,
--        caps.fanSpeed,
        caps.fineDustSensor,
        caps.fineDustHealthConcern,
        caps.refresh,
        caps["partyvoice23922.onvifstatus"],
        caps["partyvoice23922.refresh"]
      },
      capability_handlers = {
        [caps.refresh.ID] = {
          [caps.refresh.commands.refresh.NAME] = commands.refresh
        },
        [caps.switch.ID] = {
          [caps.switch.commands.on.NAME] = commands.on_off,
          [caps.switch.commands.off.NAME] = commands.on_off
        },
        [caps.switchLevel.ID] = {
          [caps.switchLevel.commands.setLevel.NAME] = commands.set_level
        },
        [cap_refresh.ID] = {
          [cap_refresh.commands.push.NAME] = commands.refresh,
        }
      }
    }
  )

--------------------
-- Initialize Driver
driver:run()
