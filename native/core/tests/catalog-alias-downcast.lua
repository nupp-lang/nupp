-- Lua twin of catalog-alias-downcast.nupp, as main generates it: an alias
-- recovered from `any` is checked against its cell's brand, and `_downcast`
-- compares the cell's cleanup policy with the one the call names.
local closed = 0
local BRAND = {}

local function release(value)
    closed = closed + value.id
end

local function manage(value, policy)
    local cell = {state = "live", value = value, policy = policy}
    function cell.close(self)
        if self.state ~= "live" then
            return nil
        end
        self.state = "closed"
        release(self.value)
    end
    function cell.alias(self)
        local alias = {brand = BRAND, cell = self}
        function alias.close(view)
            return view.cell:close()
        end
        function alias._downcast(view, wanted)
            if view.cell.policy ~= wanted then
                return nil, {code = "NUPP2613"}
            end
            return view, nil
        end
        return alias
    end
    return cell
end

local function recoveralias(value)
    if type(value) ~= "table" or value.brand ~= BRAND then
        return nil, {code = "NUPP2614"}
    end
    return value, nil
end

local function recovered()
    local owner = manage({id = 5}, "Handle")
    local erased = owner:alias()
    local alias, problem = recoveralias(erased)
    if not alias or problem ~= nil then
        return 1000
    end
    local handle, wrong = alias:_downcast("Handle")
    local mismatch, mismatchProblem = alias:_downcast("Other")
    local score = (handle ~= nil and 1 or 0) + (wrong == nil and 2 or 0) + (mismatch == nil and 4 or 0)
    if mismatchProblem and mismatchProblem.code == "NUPP2613" then
        score = score + 8
    end
    if handle then
        handle:close()
    end
    owner:close()
    return score
end

local function stranger()
    local _, problem = recoveralias({id = 3})
    return problem and problem.code == "NUPP2614" and 16 or 0
end

return (recovered() + stranger()) * 100 + closed
