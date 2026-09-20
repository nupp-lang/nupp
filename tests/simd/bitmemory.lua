-- Float memory is seeded and observed through integer reinterpretation inside
-- the compiled probe. No NaN payload crosses a host floating-number boundary.
-- Mode 98 seeds outer guards; mode 99 observes them without reseeding. Ordinary
-- operations receive only the middle 64-element slice of the 192-element allocation.
local M = {}

local function operations(ty)
    local ops = {
        {'spanLoad', 'words:store(output, 1, s:load(memory, 1))', 'a[i]'},
        {'spanMaskedLoad', 'words:store(output, 1, s:load(memory, 1, selected))', 'chosen[i] and a[i] or zero'},
        {'writeSpanLoad', 'words:store(output, 1, s:load(scratch, 1))', 'b[i]'},
        {'writeSpanMaskedLoad', 'words:store(output, 1, s:load(scratch, 1, selected))', 'chosen[i] and b[i] or zero'},
        {'store', 's:store(scratch, 1, a)', 'a[i]', 'i<=n and a[i] or b[i]'},
        {'maskedStore', 's:store(scratch, 1, a, selected)', 'a[i]', 'i<=n and chosen[i] and a[i] or b[i]'},
        {'fieldLoad', 'words:store(output, 1, s:load(records, 1, "first"))', 'a[i]'},
        {
            'fieldMaskedLoad',
            'words:store(output, 1, s:load(records, 1, "second", selected))',
            'chosen[i] and b[i] or zero'
        },
        {'fieldStore', 's:store(fields, 1, "first", a)', 'a[i]', nil, 'i<=n and a[i] or b[i]'},
        {
            'fieldMaskedStore',
            's:store(fields, 1, "first", a, selected)',
            'a[i]',
            nil,
            'i<=n and chosen[i] and a[i] or b[i]'
        },
    }
    for _, index in ipairs({'int32', 'uint32', 'int64', 'uint64'}) do
        local suffix = index
        ops[
            #ops + 1
        ] = {
            'gather' .. suffix,
            'words:store(output, 1, s:gather(memory, picks' .. suffix .. '))',
            'i>=3 and a[i-1] or zero',
            nil,
            nil,
            index
        }
        ops[
            #ops + 1
        ] = {
            'maskedGather' .. suffix,
            'words:store(output, 1, s:gather(memory, picks' .. suffix .. ', selected))',
            'i>=3 and chosen[i] and a[i-1] or zero',
            nil,
            nil,
            index
        }
        ops[
            #ops + 1
        ] = {
            'scatter' .. suffix,
            's:scatter(scratch, index' .. suffix .. ':iota(0, 1), a, selected)',
            'a[i]',
            'i+1<=n and chosen[i+1] and a[i+1] or b[i]',
            nil,
            index
        }
        ops[
            #ops + 1
        ] = {
            'scatterUnchecked' .. suffix,
            's:scatterUnchecked(scratch, picks' .. suffix .. ', a, selected)',
            'a[i]',
            'i+1<=n and i~=1 and chosen[i+1] and a[i+1] or b[i]',
            nil,
            index
        }
    end

    return ops
end

local function admitted(op, ty)
    return not op[6]
        or (ty == 'float' and op[6]:find('32', 1, true) ~= nil)
        or (ty == 'number' and op[6]:find('64', 1, true) ~= nil)
end

function M.generate(options)
    local files, probes, modules, coverage = {}, {}, {}, {}
    for _, ty in ipairs(options.types) do
        if ty == 'float' or ty == 'number' then
            local storage = ty == 'float' and 'uint32' or 'uint64'
            local wordType = ty == 'float' and 'integer' or 'uint64'
            local ops = operations(ty)
            local batch = options.batchSize or 8
            for at = 1, #options.lanes, batch do
                local module = 'simd_bitmemory_' .. ty .. '_' .. at
                local source = {
                    (
                        'local array=require("nupp.mem.array")\nlocal span=require("nupp.mem.span")\nlocal simd=require("nupp.simd")\nlocal u32=nupp.math.u32\nlocal struct Pair\n    first: %s\n    second: %s\nend\n'
                    ):format(ty, ty)
                }
                local names, exports, calls, lanes = {}, {}, {}, {}
                local signature = (
                    'exclusive output: span.WriteSpan<%s>, exclusive scratch: span.WriteSpan<%s>, borrows memory: span.Span<%s>, exclusive fields: span.WriteSpan<Pair>, borrows records: span.Span<Pair>, borrows input: span.Span<%s>, borrows choices: span.Span<%s>, active: uint32, mode: uint32'
                ):format(storage, ty, ty, storage, storage)
                for pos = at, math.min(at + batch - 1, #options.lanes) do
                    local n = options.lanes[pos]
                    local name = 'memorybits_' .. n
                    local shape = n == 'preferred' and '' or ', ' .. n
                    names[#names + 1], exports[#exports + 1], lanes[#lanes + 1] = name, name .. '=' .. name, n
                    source[
                        #source + 1
                    ] = (
                        '@aot\nlocal function %s(%s): uint32\n    local s=assert(simd.species(array.%s%s))\n    local words=assert(simd.species(array.%s%s))\n    local whole=assert(simd.species(array.%s,64))\n    local wordWhole=assert(simd.species(array.%s,64))\n'
                    ):format(name, signature, ty, shape, storage, shape, ty, storage)
                    source[
                        #source + 1
                    ] = [[    local rawA=words:load(input,1)
    local rawB=wordWhole:load(input,65)
    local allA=whole:reinterpret(wordWhole:load(input,1))
    local allB=whole:reinterpret(rawB)
    if mode==98 then
        whole:store(scratch,1,allA)
        whole:store(scratch,129,allB)
        return s.lanes
    elseif mode==99 then
        wordWhole:store(output,257,wordWhole:reinterpret(whole:load(scratch,1)))
        wordWhole:store(output,321,wordWhole:reinterpret(whole:load(scratch,129)))
        return s.lanes
    elseif mode==0 then
        whole:store(scratch,1,allB)
        whole:store(scratch,65,allA)
        whole:store(scratch,129,allB)
        whole:store(fields,1,"first",allA)
        whole:store(fields,1,"second",allB)
        return s.lanes
    end
    whole:store(scratch,1,allB)
    whole:store(fields,1,"first",allB)
    whole:store(fields,1,"second",allA)
    local selected=s:mask(words:load(choices,1)>0) & s:tail(active)
    words:store(output,1,rawA)
    local a=s:reinterpret(rawA)
]]
                    for _, index in ipairs({'int32', 'uint32', 'int64', 'uint64'}) do
                        if n ~= 'preferred' or admitted({[6] = index}, ty) then
                            source[
                                #source + 1
                            ] = (
                                '    local index%s=assert(simd.species(array.%s%s))\n    local picks%s=index%s:iota(0,1):insert(2,127)\n'
                            ):format(index, index, shape, index, index)
                        end
                    end
                    local first = true
                    for mode, op in ipairs(ops) do
                        if n ~= 'preferred' or admitted(op, ty) then
                            -- Load results are floats: move their words without numeric
                            -- conversion.
                            local code = op[
                                2
                            ]:gsub('words:store%(output, 1, (.*)%)', 'words:store(output, 1, words:reinterpret(%1))')
                            source[
                                #source + 1
                            ] = ('    %s mode==%d then\n        %s\n'):format(first and 'if' or 'elseif', mode, code)
                            first = false
                        end
                    end
                    source[
                        #source + 1
                    ] = [[    end
    wordWhole:store(output,65,wordWhole:reinterpret(whole:load(scratch,1)))
    wordWhole:store(output,129,wordWhole:reinterpret(whole:load(fields,1,"first")))
    wordWhole:store(output,193,wordWhole:reinterpret(whole:load(fields,1,"second")))
    return s.lanes
end
]]
                    calls[#calls + 1] = ('    cases=cases+check(%s,%s)\n'):format(name, tostring(n == 'preferred'))
                end
                source[
                    #source + 1
                ] = (
                    'local type Probe=function(%s): uint32\nlocal function check(probe: Probe, preferred: boolean): number\n    local input=array.scalar(array.%s,128)\n    local choices=array.scalar(array.%s,64)\n    local output=array.scalar(array.%s,384)\n    local scratch=array.scalar(array.%s,192)\n    local memory=array.scalar(array.%s,192)\n    local fields=array.new(new Pair(),64)\n    local records=array.new(new Pair(),64)\n'
                ):format(signature, storage, storage, storage, ty, ty)
                local patterns = ty == 'float'
                    and '{0,0x80000000,0x7f800000,0xff800000,1,0x80000001,0x7f7fffff,0x7fc12345,0x7f812345,0xffc54321,0xff812345}'
                    or '{0ULL,0x8000000000000000ULL,0x7ff0000000000000ULL,0xfff0000000000000ULL,1ULL,0x8000000000000001ULL,0x7fefffffffffffffULL,0x7ff8123456789abcULL,0x7ff0123456789abcULL,0xfff8fedcba987654ULL,0xfff0123456789abcULL}'
                source[
                    #source + 1
                ] = '    local patterns: {'
                    .. wordType
                    .. '}='
                    .. patterns
                    .. '\n    local zero=patterns[1]\n    local cases=0\n    for phase=0,#patterns-1 do\n'
                source[
                    #source + 1
                ] = [[        do
            local writable=input:write()
            local masks=choices:write()
            for i=1,64 do
                writable[u32.wrap(i)]=patterns[(i+phase-1)%#patterns+1]
                writable[u32.wrap(64+i)]=patterns[(i*3+phase)%#patterns+1]
                masks[u32.wrap(i)]=phase%3==0 and 1 or phase%3==1 and 0 or i%2
            end
        end
        local original=input:read()
        local masks=choices:read()
        local writable=output:write()
        local n: integer
        do
            local seed=memory:write()
            local seedFields=records:write()
            n=assert(tonumber(probe(writable,seed,scratch:read(),seedFields,fields:read(),original,masks,0,0))) as integer
        end
        local work=scratch:write()
        local fieldWork=fields:write()
        local readable=memory:read():slice(65,64+n)
        local recordRead=records:read():slice(1,n)
        assert(tonumber(probe(writable,work,readable,fieldWork,recordRead,original,masks,0,98))==n)
]]
                source[
                    #source + 1
                ] = '        local a: {' .. wordType .. '}={}\n        local b: {' .. wordType .. '}={}\n'
                source[
                    #source + 1
                ] = [[        for i=1,64 do a[i]=original[u32.wrap(i)]; b[i]=original[u32.wrap(64+i)] end
        for active=0,n do
            local chosen: {boolean}={}
            for i=1,n do chosen[i]=i<=active and masks[u32.wrap(i)]~=0 end
]]
                for mode, op in ipairs(ops) do
                    source[
                        #source + 1
                    ] = (
                        '            if not preferred or %s then\n                for i=1,384 do writable[u32.wrap(i)]=patterns[8] end\n                do\n                    local target=work:slice(65,128)\n                    assert(tonumber(probe(writable,target,readable,fieldWork,recordRead,original,masks,u32.wrap(active),%d))==n)\n                end\n                assert(tonumber(probe(writable,work,readable,fieldWork,recordRead,original,masks,0,99))==n)\n'
                    ):format(tostring(admitted(op, ty)), mode)
                    local expected = {
                        'i<=n and (' .. op[3] .. ') or patterns[8]',
                        op[4] or 'b[i]',
                        op[5] or 'b[i]',
                        'a[i]',
                        'a[i]',
                        'b[i]'
                    }
                    for slot, expr in ipairs(expected) do
                        source[
                            #source + 1
                        ] = (
                            '                for i=1,64 do\n                    local expected=%s\n                    local actual=writable[u32.wrap(%d+i)]\n                    if actual~=expected then error(%q .. " width=" .. n .. " active=" .. active .. " phase=" .. phase .. " lane=" .. i .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected)) end\n                    cases=cases+1\n                end\n'
                        ):format(expr, (slot - 1) * 64, ty .. '.' .. op[1] .. '.slot' .. slot)
                    end
                    source[#source + 1] = '            end\n'
                end
                source[
                    #source + 1
                ] = '        end\n    end\n    return cases\nend\nlocal function run(): number\n    local cases=0\n'
                    .. table.concat(
                        calls
                    ) .. '    return cases\nend\nreturn {run=run,' .. table.concat(exports, ',') .. '}\n'
                files[module .. '.g.nupp'], probes[module] = table.concat(source), names
                modules[#modules + 1] = module
                coverage[
                    #coverage + 1
                ] = {
                    family = 'bitmemory',
                    element = ty,
                    lanes = lanes,
                    indexTypes = {'int32', 'uint32', 'int64', 'uint64'},
                    preferred = 'same-width indices only',
                    tails = '0..lanes',
                    canaries = 'middle64 logical span, prefix/suffix64 guards, untouched struct field; invalid indices0/127',
                    oracle = 'raw integer-word scalar addresses; independently seeded float and struct spans'
                }
            end
        end
    end
    local top = {'local function run(): number', '    local count=0'}
    for _, module in ipairs(modules) do
        top[#top + 1] = '    count=count+require("' .. module .. '").run()'
    end
    top[#top + 1] = '    return count\nend\nreturn {run=run}\n'
    files['simd_bitmemory.nupp'] = table.concat(top, '\n')

    return {files = files, probes = probes, entry = 'simd_bitmemory', coverage = coverage}
end

return M
