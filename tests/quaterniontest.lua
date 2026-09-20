-- The rotation half of `nupp.math`, checked against references that are not the
-- implementation written a second time.
--
-- Three kinds of case earn their place here. A rotation whose answer is known by
-- hand -- a quarter turn sending one axis onto the next -- pins the handedness and
-- the storage order, which a round trip cannot: an implementation turning the wrong
-- way round still inverts and still composes. A cross-check between two operations
-- reaching the same result by different arithmetic, `rotate` against `basis`, catches
-- the expansions drifting apart. And the degenerate inputs are checked for being
-- answered at all, because the contract is that they are total.

local mathRuntime = require("nupp.compiler.runtime.math")

local M = {}

local namespace = {}
mathRuntime.install(namespace)
local quat = namespace.quat

-- Half a right angle's sine and cosine, which is every quarter turn's pair.
local HALF = math.sqrt(0.5)

-- A NaN compares false against every bound, so a tolerance check alone accepts one
-- silently. Every case here is reachable by a division by a vanishing sine, so the
-- not-a-number is tested for rather than left to a comparison that cannot see it.
local function assertNear(got, want, label, tolerance)
    tolerance = tolerance or 1e-12
    if got ~= got then
        error(("%s:\n  want: %.17g\n  got:  not a number"):format(label or "mismatch", want), 2)
    end
    if math.abs(got - want) > tolerance then
        error(("%s:\n  want: %.17g\n  got:  %.17g"):format(label or "mismatch", want, got), 2)
    end
end

local function assertRotation(label, tolerance, got, want)
    for index = 1, 4 do
        assertNear(got[index], want[index], ("%s component %d"):format(label, index), tolerance)
    end
end

local function rotationOf(x, y, z, w)
    return {x, y, z, w}
end

function M.identityTurnsNothing()
    local x, y, z, w = quat.identity()
    assertRotation("identity", nil, rotationOf(x, y, z, w), {0, 0, 0, 1})

    local vx, vy, vz = quat.rotate(x, y, z, w, 1.5, -2.5, 3.5)
    assertNear(vx, 1.5, "identity leaves x")
    assertNear(vy, -2.5, "identity leaves y")
    assertNear(vz, 3.5, "identity leaves z")
end

function M.multiplicationFollowsTheHamiltonTable()
    -- `i * j = k` and `j * i = -k`. The table is what fixes the component order and
    -- the sign convention, and it is checked before anything built on top of it.
    local x, y, z, w = quat.multiply(1, 0, 0, 0, 0, 1, 0, 0)
    assertRotation("i times j", nil, rotationOf(x, y, z, w), {0, 0, 1, 0})

    x, y, z, w = quat.multiply(0, 1, 0, 0, 1, 0, 0, 0)
    assertRotation("j times i", nil, rotationOf(x, y, z, w), {0, 0, -1, 0})

    x, y, z, w = quat.multiply(0, 0, 1, 0, 1, 0, 0, 0)
    assertRotation("k times i", nil, rotationOf(x, y, z, w), {0, 1, 0, 0})

    -- Every imaginary unit squares to minus one.
    for _, unit in ipairs({{1, 0, 0}, {0, 1, 0}, {0, 0, 1}}) do
        x, y, z, w = quat.multiply(unit[1], unit[2], unit[3], 0, unit[1], unit[2], unit[3], 0)
        assertRotation("a unit squared", nil, rotationOf(x, y, z, w), {0, 0, 0, -1})
    end
end

function M.aQuarterTurnCarriesOneAxisOntoTheNext()
    -- Right-handed, so a positive turn about z sends x onto y. An implementation
    -- turning the other way round passes every round trip and fails here.
    local x, y, z = quat.rotate(0, 0, HALF, HALF, 1, 0, 0)
    assertNear(x, 0, "a quarter turn about z leaves no x")
    assertNear(y, 1, "a quarter turn about z reaches y")
    assertNear(z, 0, "a quarter turn about z leaves no z")

    x, y, z = quat.rotate(HALF, 0, 0, HALF, 0, 1, 0)
    assertNear(x, 0, "a quarter turn about x leaves no x")
    assertNear(y, 0, "a quarter turn about x leaves no y")
    assertNear(z, 1, "a quarter turn about x reaches z")

    x, y, z = quat.rotate(0, HALF, 0, HALF, 0, 0, 1)
    assertNear(x, 1, "a quarter turn about y reaches x")
    assertNear(y, 0, "a quarter turn about y leaves no y")
    assertNear(z, 0, "a quarter turn about y leaves no z")
end

function M.theBasisIsColumnMajor()
    -- The same quarter turn as a matrix. Column-major means the first three answers
    -- are where x lands, which is the y axis, and not the first row.
    local m00, m10, m20, m01, m11, m21, m02, m12, m22 = quat.basis(0, 0, HALF, HALF)
    assertNear(m00, 0, "first column x")
    assertNear(m10, 1, "first column y")
    assertNear(m20, 0, "first column z")
    assertNear(m01, -1, "second column x")
    assertNear(m11, 0, "second column y")
    assertNear(m21, 0, "second column z")
    assertNear(m02, 0, "third column x")
    assertNear(m12, 0, "third column y")
    assertNear(m22, 1, "third column z")
end

function M.rotatingAgreesWithTheBasis()
    -- Two expansions of the same rotation reached by different arithmetic: turning a
    -- vector directly, and multiplying it by the matrix. Neither is the other's
    -- formula, so this is what catches one of them drifting.
    local qx, qy, qz, qw = quat.normalize(0.3, -0.7, 0.2, 0.9)
    local m00, m10, m20, m01, m11, m21, m02, m12, m22 = quat.basis(qx, qy, qz, qw)
    for _, vector in ipairs({{1.7, -0.4, 2.3}, {0, 0, 0}, {-5.5, 12.25, 0.125}}) do
        local vx, vy, vz = vector[1], vector[2], vector[3]
        local rx, ry, rz = quat.rotate(qx, qy, qz, qw, vx, vy, vz)
        assertNear(rx, m00 * vx + m01 * vy + m02 * vz, "turned x matches the matrix")
        assertNear(ry, m10 * vx + m11 * vy + m12 * vz, "turned y matches the matrix")
        assertNear(rz, m20 * vx + m21 * vy + m22 * vz, "turned z matches the matrix")
    end
end

function M.rotationPreservesLengthAndAngle()
    -- A rotation is what it is because it leaves these alone.
    local qx, qy, qz, qw = quat.normalize(-1.25, 0.5, 2.0, 0.75)
    local ax, ay, az = 1.0, -2.0, 0.5
    local bx, by, bz = 3.0, 0.25, -1.5
    local rax, ray, raz = quat.rotate(qx, qy, qz, qw, ax, ay, az)
    local rbx, rby, rbz = quat.rotate(qx, qy, qz, qw, bx, by, bz)
    assertNear(
        math.sqrt(rax * rax + ray * ray + raz * raz),
        math.sqrt(ax * ax + ay * ay + az * az),
        "a turned vector keeps its length"
    )
    assertNear(rax * rbx + ray * rby + raz * rbz, ax * bx + ay * by + az * bz, "turning keeps the angle between two")
end

function M.compositionAppliesTheSecondFirst()
    -- `multiply(a, b)` has to mean the same as turning by `b` and then by `a`, which
    -- is the order a column-major matrix product means.
    local ax, ay, az, aw = quat.fromAxisAngle(0, 0, 1, math.pi / 2)
    local bx, by, bz, bw = quat.fromAxisAngle(1, 0, 0, math.pi / 2)
    local cx, cy, cz, cw = quat.multiply(ax, ay, az, aw, bx, by, bz, bw)
    for _, vector in ipairs({{0, 0, 1}, {1, 2, 3}, {-0.5, 0.25, 4.0}}) do
        local sx, sy, sz = quat.rotate(bx, by, bz, bw, vector[1], vector[2], vector[3])
        sx, sy, sz = quat.rotate(ax, ay, az, aw, sx, sy, sz)
        local tx, ty, tz = quat.rotate(cx, cy, cz, cw, vector[1], vector[2], vector[3])
        assertNear(tx, sx, "composed x matches turning twice")
        assertNear(ty, sy, "composed y matches turning twice")
        assertNear(tz, sz, "composed z matches turning twice")
    end
end

function M.inverseUndoesAndConjugateAgreesOnUnits()
    local qx, qy, qz, qw = quat.normalize(0.3, -0.7, 0.2, 0.9)
    local ix, iy, iz, iw = quat.inverse(qx, qy, qz, qw)
    local x, y, z, w = quat.multiply(qx, qy, qz, qw, ix, iy, iz, iw)
    assertRotation("a rotation times its inverse", nil, rotationOf(x, y, z, w), {0, 0, 0, 1})

    -- For a unit rotation the cheap conjugate is the inverse; away from one it is not,
    -- which is the whole reason both exist.
    local cx, cy, cz, cw = quat.conjugate(qx, qy, qz, qw)
    assertRotation("the conjugate of a unit rotation", nil, rotationOf(cx, cy, cz, cw), {ix, iy, iz, iw})

    local dx, dy, dz, dw = quat.inverse(2 * qx, 2 * qy, 2 * qz, 2 * qw)
    x, y, z, w = quat.multiply(2 * qx, 2 * qy, 2 * qz, 2 * qw, dx, dy, dz, dw)
    assertRotation("a scaled rotation times its inverse", nil, rotationOf(x, y, z, w), {0, 0, 0, 1})
end

function M.axisAngleRoundTrips()
    for _, angle in ipairs({0.0, 0.5, 1.1, math.pi / 2, 3.0}) do
        local x, y, z, w = quat.fromAxisAngle(0, 1, 0, angle)
        local axisX, axisY, axisZ, recovered = quat.toAxisAngle(x, y, z, w)
        if angle == 0.0 then
            -- The identity has no axis to recover, so a real one is named rather than
            -- a zero vector the caller would have to guard.
            assertNear(axisX, 1, "the identity names the x axis")
            assertNear(recovered, 0, "the identity has no turn")
        else
            assertNear(axisX, 0, "the axis keeps its x")
            assertNear(axisY, 1, "the axis keeps its y")
            assertNear(axisZ, 0, "the axis keeps its z")
            assertNear(recovered, angle, "the angle round trips")
        end
    end

    -- An axis that did not arrive as a unit vector is normalized here.
    local x, y, z, w = quat.fromAxisAngle(0, 5, 0, 1.0)
    local unitX, unitY, unitZ, unitW = quat.fromAxisAngle(0, 1, 0, 1.0)
    assertRotation("a long axis matches its unit", nil, rotationOf(x, y, z, w), {unitX, unitY, unitZ, unitW})

    -- `q` and `-q` are the same rotation reached the two opposite ways, and which one
    -- arrived is kept rather than folded away.
    local negatedAxisX, _, _, negatedAngle = quat.toAxisAngle(-unitX, -unitY, -unitZ, -unitW)
    assertNear(negatedAngle, 2 * math.pi - 1.0, "the negated spelling turns the long way")
    assertNear(negatedAxisX, 0, "the negated spelling keeps an x-free axis")

    local identityAxisX, identityAxisY, identityAxisZ, identityAngle = quat.toAxisAngle(0, 0, 0, -1)
    assertNear(identityAxisX, 1, "negative identity names the x axis")
    assertNear(identityAxisY, 0, "negative identity has no y axis component")
    assertNear(identityAxisZ, 0, "negative identity has no z axis component")
    assertNear(identityAngle, 2 * math.pi, "negative identity keeps the full turn")
end

function M.fromToCarriesOneDirectionOntoAnother()
    local cases = {{{1, 0, 0}, {0, 1, 0}}, {{0, 0, 3}, {0, 4, 0}}, {{1, 1, 1}, {-1, 2, 0.5}}, {{2, 0, 0}, {2, 0, 0}},}
    for _, case in ipairs(cases) do
        local from, to = case[1], case[2]
        local x, y, z, w = quat.fromTo(from[1], from[2], from[3], to[1], to[2], to[3])
        local rx, ry, rz = quat.rotate(x, y, z, w, from[1], from[2], from[3])
        local fromLength = math.sqrt(from[1] * from[1] + from[2] * from[2] + from[3] * from[3])
        local toLength = math.sqrt(to[1] * to[1] + to[2] * to[2] + to[3] * to[3])
        local scale = fromLength / toLength
        assertNear(rx, to[1] * scale, "the turned direction reaches x", 1e-11)
        assertNear(ry, to[2] * scale, "the turned direction reaches y", 1e-11)
        assertNear(rz, to[3] * scale, "the turned direction reaches z", 1e-11)
    end
end

function M.fromToHandlesOpposedDirections()
    -- Opposed directions have no shortest rotation, so the requirement is only that
    -- some half turn across them is answered -- and that it is a real rotation rather
    -- than a zero or a NaN, which is what a cross product alone would give.
    for _, direction in ipairs({{1, 0, 0}, {0, 1, 0}, {0, 0, 1}, {1, 1, 0}, {-2, 3, -4}}) do
        local x, y, z, w = quat.fromTo(
            direction[1],
            direction[2],
            direction[3],
            -direction[1],
            -direction[2],
            -direction[3]
        )
        assertNear(quat.length(x, y, z, w), 1, "the opposed turn is a unit rotation", 1e-12)
        local rx, ry, rz = quat.rotate(x, y, z, w, direction[1], direction[2], direction[3])
        assertNear(rx, -direction[1], "the opposed turn reverses x", 1e-11)
        assertNear(ry, -direction[2], "the opposed turn reverses y", 1e-11)
        assertNear(rz, -direction[3], "the opposed turn reverses z", 1e-11)
    end
end

function M.fromToDoesNotSnapNearOpposedDirections()
    for _, angle in ipairs({0.001, 1e-9}) do
        local bx, by = -math.cos(angle), math.sin(angle)
        local x, y, z, w = quat.fromTo(1, 0, 0, bx, by, 0)
        local rx, ry, rz = quat.rotate(x, y, z, w, 1, 0, 0)
        assertNear(rx, bx, "a near-opposed turn reaches x", 1e-12)
        assertNear(ry, by, "a near-opposed turn reaches y", 1e-12)
        assertNear(rz, 0, "a near-opposed turn reaches z", 1e-12)
    end
end

function M.interpolationReachesTheHalfAngle()
    -- Constant angular speed means the midpoint of a turn is the half turn, which is
    -- computed here from the angle rather than from the endpoints.
    local ax, ay, az, aw = quat.fromAxisAngle(0, 0, 1, 0)
    local bx, by, bz, bw = quat.fromAxisAngle(0, 0, 1, math.pi / 2)
    for _, t in ipairs({0.25, 0.5, 0.75}) do
        local x, y, z, w = quat.slerp(ax, ay, az, aw, bx, by, bz, bw, t)
        local ex, ey, ez, ew = quat.fromAxisAngle(0, 0, 1, t * math.pi / 2)
        assertRotation("the spherical midpoint", 1e-12, rotationOf(x, y, z, w), {ex, ey, ez, ew})
    end
end

function M.interpolationKeepsItsEndpointHemisphere()
    local ax, ay, az, aw = quat.identity()
    local bx, by, bz, bw = quat.fromAxisAngle(0, 0, 1, math.pi / 2)
    bx, by, bz, bw = -bx, -by, -bz, -bw
    for _, name in ipairs({"slerp", "nlerp"}) do
        local blend = quat[name]
        local x, y, z, w = blend(ax, ay, az, aw, bx, by, bz, bw, 0)
        assertRotation(name .. " at zero", nil, rotationOf(x, y, z, w), {ax, ay, az, aw})

        local nearX, nearY, nearZ, nearW = blend(ax, ay, az, aw, bx, by, bz, bw, 1 - 1e-9)
        x, y, z, w = blend(ax, ay, az, aw, bx, by, bz, bw, 1)
        assertRotation(name .. " keeps the short endpoint", 1e-12, rotationOf(x, y, z, w), {-bx, -by, -bz, -bw})
        assert(
            quat.dot(nearX, nearY, nearZ, nearW, x, y, z, w) > 0,
            name .. " must not flip component signs at the endpoint"
        )
    end
end

function M.interpolationTakesTheShortWayAround()
    -- A negated endpoint is the same rotation, so both spellings have to interpolate
    -- through the same rotations rather than one of them going the long way.
    local ax, ay, az, aw = quat.fromAxisAngle(0, 0, 1, 0)
    local bx, by, bz, bw = quat.fromAxisAngle(0, 0, 1, math.pi / 3)
    for _, name in ipairs({"slerp", "nlerp"}) do
        local blend = quat[name]
        local x, y, z, w = blend(ax, ay, az, aw, bx, by, bz, bw, 0.5)
        local nx, ny, nz, nw = blend(ax, ay, az, aw, -bx, -by, -bz, -bw, 0.5)
        -- Same rotation, either spelling of it.
        local agrees = math.abs(nx - x) < 1e-12 and math.abs(nw - w) < 1e-12
        local agreesNegated = math.abs(nx + x) < 1e-12 and math.abs(nw + w) < 1e-12
        assert(agrees or agreesNegated, name .. " went the long way round a negated endpoint")
        local turned = select(2, quat.rotate(x, y, z, w, 1, 0, 0))
        local negatedTurned = select(2, quat.rotate(nx, ny, nz, nw, 1, 0, 0))
        assertNear(negatedTurned, turned, name .. " turns a vector the same either way", 1e-12)
        assertNear(z, math.sin(math.pi / 12), name .. " reaches half the turn", 1e-12)
    end
end

function M.interpolationSurvivesNearlyParallelEndpoints()
    -- Where the arc vanishes the spherical form divides by a sine going to zero, so it
    -- hands over to the linear one. The handover has to be continuous and has to stay
    -- a unit rotation, which is what a division by nearly nothing would lose.
    local ax, ay, az, aw = quat.fromAxisAngle(0, 0, 1, 0)
    for _, angle in ipairs({1e-3, 1e-6, 1e-9, 1e-12, 0.0}) do
        local bx, by, bz, bw = quat.fromAxisAngle(0, 0, 1, angle)
        local x, y, z, w = quat.slerp(ax, ay, az, aw, bx, by, bz, bw, 0.5)
        assertNear(quat.length(x, y, z, w), 1, "a vanishing arc stays a unit rotation", 1e-12)
        assertNear(z, math.sin(angle / 4), "a vanishing arc still reaches its midpoint", 1e-9)
    end

    -- Identical endpoints are the limit of that, and must not answer a NaN.
    local x, y, z, w = quat.slerp(ax, ay, az, aw, ax, ay, az, aw, 0.5)
    assertRotation("identical endpoints", nil, rotationOf(x, y, z, w), {ax, ay, az, aw})
end

function M.interpolationStaysAUnitRotation()
    local ax, ay, az, aw = quat.normalize(0.3, -0.7, 0.2, 0.9)
    local bx, by, bz, bw = quat.normalize(-0.1, 0.4, 0.8, 0.2)
    for step = 0, 10 do
        local t = step / 10
        for _, name in ipairs({"slerp", "nlerp"}) do
            local x, y, z, w = quat[name](ax, ay, az, aw, bx, by, bz, bw, t)
            assertNear(quat.length(x, y, z, w), 1, name .. " stays a unit rotation at " .. t, 1e-12)
        end
    end
end

function M.matrixWritesSixteenColumnMajorNumbers()
    local out = {}
    quat.toMatrix(0, 0, HALF, HALF, out, 1)
    local want = {0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}
    for index = 1, 16 do
        assertNear(out[index], want[index], "the matrix entry at " .. index)
    end

    -- `offset` indexes the first number written rather than counting before it, and
    -- nothing outside the sixteen is touched.
    local shifted = {}
    for index = 1, 40 do
        shifted[index] = -1
    end
    quat.toMatrix(0, 0, HALF, HALF, shifted, 17)
    for index = 1, 16 do
        assertNear(shifted[index], -1, "the numbers before the offset are left alone")
        assertNear(shifted[16 + index], want[index], "the shifted matrix entry at " .. index)
    end
    for index = 33, 40 do
        assertNear(shifted[index], -1, "the numbers after the sixteen are left alone")
    end
end

function M.theMatrixAgreesWithTheBasis()
    local qx, qy, qz, qw = quat.normalize(0.3, -0.7, 0.2, 0.9)
    local m00, m10, m20, m01, m11, m21, m02, m12, m22 = quat.basis(qx, qy, qz, qw)
    local out = {}
    quat.toMatrix(qx, qy, qz, qw, out, 1)
    local expected = {m00, m10, m20, 0, m01, m11, m21, 0, m02, m12, m22, 0, 0, 0, 0, 1}
    for index = 1, 16 do
        assertNear(out[index], expected[index], "the four-by-four entry at " .. index)
    end
end

function M.degenerateInputsAreAnswered()
    -- Every one of these is a total answer rather than an error or a NaN, so a caller
    -- reading rotations out of a file does not have to guard each call. A caller that
    -- wants to reject bad data reads `length` and decides for itself.
    local x, y, z, w = quat.normalize(0, 0, 0, 0)
    assertRotation("normalizing zero", nil, rotationOf(x, y, z, w), {0, 0, 0, 1})

    x, y, z, w = quat.inverse(0, 0, 0, 0)
    assertRotation("inverting zero", nil, rotationOf(x, y, z, w), {0, 0, 0, 1})

    x, y, z, w = quat.fromAxisAngle(0, 0, 0, 1.0)
    assertRotation("a zero axis", nil, rotationOf(x, y, z, w), {0, 0, 0, 1})

    x, y, z, w = quat.fromTo(0, 0, 0, 1, 0, 0)
    assertRotation("a zero starting direction", nil, rotationOf(x, y, z, w), {0, 0, 0, 1})

    x, y, z, w = quat.fromTo(1, 0, 0, 0, 0, 0)
    assertRotation("a zero target direction", nil, rotationOf(x, y, z, w), {0, 0, 0, 1})

    x, y, z, w = quat.toAxisAngle(0, 0, 0, 1)
    assertRotation("the identity's axis and angle", nil, rotationOf(x, y, z, w), {1, 0, 0, 0})
end

function M.normalizationKeepsTheSign()
    -- `q` and `-q` are the same rotation, and normalizing does not quietly pick one of
    -- them: `slerp` reads that sign to choose the short way, so losing it here would
    -- silently change which way an interpolation turned.
    local x, y, z, w = quat.normalize(-0.6, 0, 0, -0.8)
    assertNear(w, -0.8, "a negative scalar part stays negative")
    assertNear(x, -0.6, "a negative vector part stays negative")
    assertNear(quat.length(x, y, z, w), 1, "the normalized rotation is a unit one")
end

function M.componentwiseArithmeticIntegratesAngularVelocity()
    -- The reason `add` and `scale` are here: a rigid body's orientation is stepped by
    -- adding half the angular velocity times the step, as a rotation with no scalar
    -- part, and renormalizing. A quarter turn per second stepped over a second in a
    -- thousand pieces has to land on a quarter turn.
    local x, y, z, w = quat.identity()
    local rate = math.pi / 2
    local steps = 1000
    local dt = 1.0 / steps
    for _ = 1, steps do
        local dx, dy, dz, dw = quat.multiply(0, 0, rate, 0, x, y, z, w)
        dx, dy, dz, dw = quat.scale(dx, dy, dz, dw, 0.5 * dt)
        x, y, z, w = quat.normalize(quat.add(x, y, z, w, dx, dy, dz, dw))
    end
    local ex, ey, ez, ew = quat.fromAxisAngle(0, 0, 1, rate)
    assertRotation("the integrated orientation", 1e-6, rotationOf(x, y, z, w), {ex, ey, ez, ew})

    local sx, sy, sz, sw = quat.subtract(1, 2, 3, 4, 0.5, 1.5, 2.5, 3.5)
    assertRotation("componentwise subtraction", nil, rotationOf(sx, sy, sz, sw), {0.5, 0.5, 0.5, 0.5})
end

function M.dotAndLengthDescribeTheSameRotation()
    local ax, ay, az, aw = quat.fromAxisAngle(0, 0, 1, 0)
    local bx, by, bz, bw = quat.fromAxisAngle(0, 0, 1, math.pi / 3)
    -- The dot product of two unit rotations is the cosine of half the angle between
    -- them, which is the identity `slerp` is built on.
    assertNear(quat.dot(ax, ay, az, aw, bx, by, bz, bw), math.cos(math.pi / 6), "the dot product is the half angle")
    assertNear(quat.lengthSquared(1, 2, 3, 4), 30, "the squared length")
    assertNear(quat.length(0, 0, 0, 0), 0, "a zero rotation has no length")
    assertNear(quat.length(HALF, 0, 0, HALF), 1, "a quarter turn is a unit rotation")
end

return M
