-- Lua twin of catalog-own-manage.nupp, as main generates it: the value is
-- handed to the ownership runtime with a function running its cleanup, and the
-- cell is closed by hand or as its owner's scope ends.
local closed = 0

local function release(value)
    closed = closed + value.id
end

local function manage(value)
    local cell = {state = "live", value = value}
    function cell.close(self)
        if self.state ~= "live" then
            return nil
        end
        self.state = "closed"
        release(self.value)
    end
    function cell.alias(self)
        return {cell = self}
    end
    return cell
end

local function explicit()
    local owner = manage({id = 5})
    local alias = owner:alias()
    local before = closed
    owner:close()
    return before * 10 + closed + (alias ~= nil and 0 or 1000)
end

local function scoped()
    local owner = manage({id = 7})
    local _ = owner:alias()
    owner:close()
end

local first = explicit()
scoped()

return first * 100 + closed
