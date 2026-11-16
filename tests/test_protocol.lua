local T = ...
local ns = T.pureNs()
local P = ns.Protocol

T.describe("Protocol", function()
  T.it("round-trips an envelope", function()
    local env = P.Decode(P.Encode("PROF", { m = "Ran Fred", p = { ["171"] = { ts = 5 } } }))
    T.eq(env.t, "PROF")
    T.eq(env.d.m, "Ran Fred")
    T.eq(env.d.p["171"].ts, 5)
  end)

  T.it("reassembles parts in any order", function()
    local recipes = {}
    for i = 1, 600 do recipes[i] = 100000 + i * 7 end
    local payload = P.Encode("PROF", { r = recipes })
    local parts = P.Chunk("ab1", payload)
    T.truthy(#parts > 2, "expected several parts")
    for _, part in ipairs(parts) do T.truthy(#part <= 250, "part too long") end
    local asm = P.NewAssembler()
    local result
    for i = #parts, 1, -1 do result = P.AddPart(asm, "Ran Fred", parts[i], 0) or result end
    T.eq(result, payload)
    T.eq(#P.Decode(result).d.r, 600)
  end)

  T.it("slices name keys the same way everywhere, a slice of n splitting into two of 2n", function()
    T.eq(P.SliceOf("ran-fred", 1), 0)
    local a = P.SliceOf("ran-fred", 4)
    T.eq(P.SliceOf("ran-fred", 4), a) -- the same every time
    T.truthy(a >= 0 and a < 4)
    local counts = {}
    for i = 1, 2000 do
      local key = "member" .. i .. "-realm"
      local small, big = P.SliceOf(key, 8), P.SliceOf(key, 16)
      T.truthy(big == small or big == small + 8, key)
      counts[small] = (counts[small] or 0) + 1
    end
    for s = 0, 7 do T.truthy((counts[s] or 0) > 150, "slices are about even: " .. tostring(counts[s])) end
    local map = { ["ran-fred"] = 1, ["au-tsch"] = 2, ["makira-farron"] = 3 }
    T.eq(P.SliceMap(map, nil), map)
    local union = {}
    for s = 0, 3 do
      for key, v in pairs(P.SliceMap(map, { s, 4 })) do
        T.eq(union[key], nil)
        union[key] = v
      end
    end
    T.eq(union, map)
  end)

  T.it("takes only slices that make sense", function()
    T.eq(P.ValidSlice({ 3, 8 }), { 3, 8 })
    T.eq(P.ValidSlice({ 0, 2 }), { 0, 2 })
    T.eq(P.ValidSlice(nil), nil)
    T.eq(P.ValidSlice({ 0, 1 }), nil)    -- one slice is the whole
    T.eq(P.ValidSlice({ 8, 8 }), nil)
    T.eq(P.ValidSlice({ -1, 8 }), nil)
    T.eq(P.ValidSlice({ 1, 6 }), nil)    -- no power of two
    T.eq(P.ValidSlice({ 1.5, 8 }), nil)
    T.eq(P.ValidSlice({ 0, 512 }), nil)
    T.eq(P.ValidSlice("1/8"), nil)
  end)

  T.it("counts the parts of a payload as Chunk makes them", function()
    for _, size in ipairs({ 1, 200, 233, 234, 235, 5000, 14000 }) do
      local payload = string.rep("x", size)
      T.truthy(math.abs(P.PartCount(payload) - #P.Chunk("1a2b3", payload)) <= 1, tostring(size))
    end
  end)

  T.it("refuses newer versions and garbage", function()
    local lib = P.Deflate()
    local newer = lib:EncodeForWoWAddonChannel(lib:CompressDeflate(ns.json.encode({ p = 2, t = "X", d = {} })))
    local _, err = P.Decode(newer)
    T.eq(err, "newer")
    local _, err2 = P.Decode("not a message")
    T.eq(err2, "malformed")
    local _, err3 = P.AddPart(P.NewAssembler(), "x", "~a:5/2:zz", 0)
    T.eq(err3, "malformed")
  end)

  T.it("carries the addon version", function()
    T.eq(P.Decode(P.Encode("HI", {}, "0.3.0")).v, "0.3.0")
    T.eq(P.Decode(P.Encode("HI", {})).v, nil)
    T.eq(P.CompareVersions("0.2.0", "0.3.0"), -1)
    T.eq(P.CompareVersions("0.10.0", "0.9.1"), 1)
    T.eq(P.CompareVersions("v0.3", "0.3.0"), 0)
    T.eq(P.CompareVersions("dev", "0.3.0"), nil)
  end)

  T.it("knows the newest release that is newer than the own one", function()
    T.eq(P.NewerVersion("1.1.2", nil, "1.1.3"), "1.1.3")
    T.eq(P.NewerVersion("1.1.2", "1.1.3", "1.2.0"), "1.2.0")
    T.eq(P.NewerVersion("1.1.2", "1.2.0", "1.1.3"), "1.2.0") -- an older one seen later changes nothing
    T.eq(P.NewerVersion("1.1.2", "1.1.3", nil), "1.1.3")     -- remembered while its member is offline
    T.eq(P.NewerVersion("1.2.0", "1.1.3", nil), nil)         -- updated since
    T.eq(P.NewerVersion("1.1.2", nil, "1.1.2"), nil)
    T.eq(P.NewerVersion("1.1.2", nil, "dev"), nil)
    T.eq(P.NewerVersion("1.1.2", nil, "1.1.3-4-gabc123"), nil) -- a packager build is no release
    T.eq(P.NewerVersion("1.1.2", nil, ""), nil)
    T.eq(P.NewerVersion("dev", nil, "9.9.9"), nil)             -- a development copy is never outdated
  end)

  T.it("limits messages per sender", function()
    local limiter = P.NewLimiter(3, 10)
    for _ = 1, 3 do T.eq(P.Allow(limiter, "A", 0), true) end
    T.eq(P.Allow(limiter, "A", 1), false)
    T.eq(P.Allow(limiter, "B", 1), true)
    T.eq(P.Allow(limiter, "A", 11), true)
  end)
end)
