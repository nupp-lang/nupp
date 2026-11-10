local function plan(names, cost, audited, requested)
    local order, present, ordinary = {}, {}, 0
    for index, name in ipairs(names) do
        order[index] = name
        if audited[name] then
            present[name] = true
        else
            ordinary = ordinary + 1
        end
    end
    if #order == 0 then
        return {}
    end
    local hasAudits = next(present) ~= nil
    local count = math.min(requested, #order // 4, ordinary + (hasAudits and 1 or 0))
    if count < 2 then
        return {order}
    end

    local function weight(name)
        return math.max(1, cost[name] or 1)
    end

    table.sort(order, function(a, b)
        local ca, cb = weight(a), weight(b)
        return ca ~= cb and ca > cb or ca == cb and a < b
    end)
    local load, members = {}, {}
    for index = 1, count do
        load[index], members[index] = 0, {}
    end
    for name in pairs(present) do
        load[1] = load[1] + (cost["audit " .. name] or 10)
    end

    local function place(index, name)
        members[index][#members[index] + 1] = name
        load[index] = load[index] + weight(name)
    end

    for _, name in ipairs(order) do
        if audited[name] then
            place(1, name)
        end
    end
    for _, name in ipairs(order) do
        if not audited[name] then
            local least = 1
            for index = 2, count do
                if load[index] < load[least] then
                    least = index
                end
            end
            place(least, name)
        end
    end

    return members
end

return {plan = plan}
