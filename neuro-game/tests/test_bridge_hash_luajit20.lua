local real = require("bit")
local strict = setmetatable({
  bxor = function(...)
    for i = 1, select("#", ...) do
      assert(type((select(i, ...))) == "number", "bad argument to 'bxor' (number expected, got cdata)")
    end
    return real.bxor(...)
  end,
}, { __index = real })
package.loaded.bit = strict
require("core.bridge")
package.loaded.bit = real
dofile("tests/test_outbox_rotation_fence.lua")
