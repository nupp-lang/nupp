-- Behavioral oracles shared by native generation and the rollback lowerers.
return {
    records = {
        source = table.concat(
            {
                "local record Item",
                "   value: integer",
                "end",
                "local calls = 0",
                "local function subject(value: any): any",
                "   calls = calls + 1",
                "   return value",
                "end",
                "local function classify(value: Item | string | nil): boolean",
                "   return switch value do",
                "      case is Item -> true",
                "      else -> false",
                "   end",
                "end",
                "local item = new Item(value = 7)",
                "local yes = subject(item) is Item",
                "local no = subject(nil) is Item",
                "return yes, no, calls, classify(item), classify('empty'), classify(nil)",
            },
            "\n"
        ),
        expected = {true, false, 2, true, false, false},
        count = 6
    },
    cleanup = {
        source = table.concat(
            {
                "local h = {}",
                "local total = 0",
                "for index = 1, 3 do",
                "    with installation = require('nupp.suspension').install(h) do",
                "        if index == 2 then continue end",
                "        total = total + index",
                "    end",
                "end",
                "while true do",
                "    with installation = require('nupp.suspension').install(h) do",
                "        break",
                "    end",
                "end",
                "return total, true",
            },
            "\n"
        ),
        expected = {4, true},
        count = 2
    },
    safeReads = {
        source = table.concat(
            {
                "local calls = 0",
                "local function key(): string",
                "   calls = calls + 1",
                "   return 'k'",
                "end",
                "local points: {any} = {{x = 2}, {}, {x = 3}}",
                "local none: any = nil",
                "local total = 0",
                "for index = 1, 3 do",
                "   total = total + (points[index]?.x ?? 0) + (none?.x ?? 0)",
                "end",
                "local absent: any = nil",
                "local missing: any = nil",
                "local byKey = absent?.[key()]",
                "local called = missing?.(key())",
                "return total, calls, byKey, called",
            },
            "\n"
        ),
        expected = {5, 0},
        count = 4
    },
    repeatScope = {
        source = table.concat(
            {
                "local i = 0",
                "local skipped = 0",
                "repeat",
                "    i = i + 1",
                "    local done = i >= 3",
                "    if i == 1 then",
                "        skipped = skipped + 1",
                "        continue",
                "    end",
                "until done",
                "local j = 0",
                "repeat",
                "    j = j + 1",
                "    local last = j == 2",
                "    if last then continue end",
                "until last",
                "return i, skipped, j",
            },
            "\n"
        ),
        expected = {3, 1, 2},
        count = 3
    },
}
