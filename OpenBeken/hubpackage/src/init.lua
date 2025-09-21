local Driver = require('st.driver')
local caps = require('st.capabilities')

local discovery = require('discovery')
local lifecycles = require('lifecycles')
local commands = require('commands')

local driver =
  Driver(
    'LAN-OpenBkPlug',
    {
      discovery = discovery.start,
      lifecycle_handlers = lifecycles,
      supported_capabilities = {
        caps.switch,
        caps.powerMeter,
        caps.energyMeter,
        caps.voltageMeasurement,
        caps.currentMeasurement,
        caps.powerConsumptionReport,
        caps.refresh,
        caps["partyvoice23922.onvifstatus"]
      },
      capability_handlers = {
        [caps.switch.ID] = {
          [caps.switch.commands.on.NAME] = commands.on_off,
          [caps.switch.commands.off.NAME] = commands.on_off
        },
        [caps.refresh.ID] = {
          [caps.refresh.commands.refresh.NAME] = commands.refresh
        }
      }
    }
  )

-- Initialize Driver
driver:run()
