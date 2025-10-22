local M = {}

-- Cache for statusline data
local cache = {
   status = nil,
   last_check = 0,
}

-- Get direnv status for statusline integration
--- @param config table Direnv configuration
--- @return string status_string
M.statusline = function(config)
   local statusline_config = config.integrations and config.integrations.statusline or config.statusline
   
   if not statusline_config or not statusline_config.enabled then
      return ""
   end

   if cache.status == 0 then
      return statusline_config.icon .. " active"
   elseif cache.status == 1 then
      return statusline_config.icon .. " pending"
   elseif cache.status == 2 then
      return statusline_config.icon .. " blocked"
   else
      return ""
   end
end

-- Update the cached status from the main module
--- @param status number|nil The direnv status
M.update_status = function(status)
   cache.status = status
end

-- Refresh the statusline cache
M.refresh = function()
   cache.last_check = 0
end

return M