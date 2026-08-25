
local Episode = {}

local pack_owner = nil

function Episode.claim_pack(token) pack_owner = token end

function Episode.pack_on_screen()
  if pack_owner == nil then return nil end
  return pack_owner ~= false
end

function Episode.reset()
  pack_owner = nil
end

return Episode
