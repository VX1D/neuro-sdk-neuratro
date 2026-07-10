local function once_until(key, epoch)
  if not (G and G.NEURO) then return false end
  local seen = G.NEURO.once_serials
  if type(seen) ~= "table" then seen = {} end
  key = tostring(key)
  if epoch == nil then epoch = "\0nil" end  -- distinguish "never seen" from a nil epoch
  if seen[key] == epoch then return false end
  seen[key] = epoch
  G.NEURO.once_serials = seen
  return true
end

return { once_until = once_until }
