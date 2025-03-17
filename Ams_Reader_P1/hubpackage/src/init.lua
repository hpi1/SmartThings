local Driver = require('st.driver')
local caps = require('st.capabilities')

-- local imports
local discovery = require('discovery')
local lifecycles = require('lifecycles')
local commands = require('commands')

--------------------
-- Driver definition
local driver =
  Driver(
    'LAN-AmsReader-P1',
    {
      discovery = discovery.start,
      lifecycle_handlers = lifecycles,
      supported_capabilities = {
        caps.powerMeter,
        caps.energyMeter,
        caps.powerConsumptionReport,
        caps.refresh,
        caps["gardengarden49042.kwhprice"]
      },
      capability_handlers = {
        [caps.refresh.ID] = {
          [caps.refresh.commands.refresh.NAME] = commands.refresh
        }
      }
    }
  )

--------------------
-- Initialize Driver
driver:run()
