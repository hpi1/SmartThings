local commands = require('commands')
local log = require('log')

local lifecycle_handler = {}

local function setup_refresh(device)
  device.thread:call_on_schedule(
    device.preferences.refreshfreq,
    function ()
      return commands.refresh(nil, device)
    end)
end

function lifecycle_handler.init(driver, device)
  log.debug('driver init')
  setup_refresh(device)
end

function lifecycle_handler.added(driver, device)
  log.debug('device added')
  commands.refresh(nil, device)
end

function lifecycle_handler.removed(_, device)
  log.debug('device removed')

  for timer in pairs(device.thread.timers) do
    device.thread:cancel_timer(timer)
  end
end

function lifecycle_handler.infoChanged (driver, device, event, args)

  log.debug('info changed')

  if args.old_st_store.preferences then
    if args.old_st_store.preferences.refreshfreq ~= device.preferences.refreshfreq then
      log.info ('Refresh fequency changed to: ', device.preferences.refreshfreq)

      for timer in pairs(device.thread.timers) do
        device.thread:cancel_timer(timer)
      end

      setup_refresh(device)

    end
  else
    log.warn ('Old preferences missing')
  end
end

return lifecycle_handler
