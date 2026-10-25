local M = {}

function M.new(clock)
  local quiet_until, last = 0, nil
  local throttle = {}
  function throttle.print(line)
    local now = clock()
    if now <= quiet_until and line == last then return end
    print(line)
    quiet_until, last = now + 5, line
  end
  function throttle.reset() quiet_until, last = 0, nil end
  return throttle
end

return M
