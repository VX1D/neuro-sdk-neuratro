
local SchemaValidate = require("util.schema_validate")

local checks = 0
local function claim(cond, detail)
  checks = checks + 1
  assert(cond, detail)
end

local scalar_items = {
  type = "array",
  items = { type = "integer" },
  uniqueItems = true,
}
local ok_scalar, scalar_err = SchemaValidate.validate_value(scalar_items, { 1, 2, 3 }, "indices")
claim(ok_scalar == true, scalar_err)
local ok_duplicate = SchemaValidate.validate_value(scalar_items, { 1, 1 }, "indices")
claim(ok_duplicate == false, "duplicate scalar items must still be rejected")

local object_items = {
  type = "array",
  items = { type = "object", properties = { id = { type = "integer" } } },
  uniqueItems = true,
}
local ok_object, object_err = SchemaValidate.validate_value(object_items, { { id = 1 }, { id = 1 } }, "items")
claim(ok_object == false, "uniqueItems with object items must not pass unchecked")
claim(object_err:find("non%-scalar", 1, false) ~= nil, object_err)

print("schema-validate-unique: PASS, " .. checks .. " checks")
