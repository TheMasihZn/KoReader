--[[--
Physics for the simulation apps. Pure Lua, no UI, so it can be tested alone.

  Physlab.pendulum.new{ n = 3, lengths = {1,1,1}, masses = {1,1,1}, g = 9.81, angles = {...} }
  p:step(dt)            -- one RK4 step
  p:positions()         -- {{x1,y1},...}  (pivot at 0,0, y up)
  p:energy()            -- total energy (conserved: a check on the numbers)
  p:formulas()          -- LaTeX lines describing this very frame

  Physlab.slits.new{ slits = 2, wavelength = 500e-9, separation = 20e-6, width = 5e-6, distance = 1.0 }
  s:intensity(y)        -- relative intensity on the screen at height y (metres)
  s:addPhotons(k)       -- k more photons, each landing where the intensity says (chance)
  s.counts / s.total    -- the histogram that builds up
  s:entropy()           -- Shannon entropy of the histogram so far (bits)
  s:formulas()          -- LaTeX lines for this frame
]]

local Physlab = {}

---------------------------------------------------------------------------
-- N pendulums (point masses on rigid rods), exact Lagrangian equations
---------------------------------------------------------------------------

local Pendulum = {}
Pendulum.__index = Pendulum
Physlab.pendulum = {}

function Physlab.pendulum.new(o)
    local n = o.n or 2
    local p = setmetatable({ n = n, g = o.g or 9.81, t = 0, steps = 0, l = {}, m = {}, th = {}, w = {} }, Pendulum)
    for i = 1, n do
        p.l[i] = (o.lengths and o.lengths[i]) or 1
        p.m[i] = (o.masses and o.masses[i]) or 1
        p.th[i] = (o.angles and o.angles[i]) or (math.pi / 2 + 0.01 * i)
        p.w[i] = (o.speeds and o.speeds[i]) or 0
    end
    return p
end

-- Solve A x = b by Gaussian elimination with partial pivoting.
local function solve(A, b, n)
    for c = 1, n do
        local piv = c
        for r = c + 1, n do if math.abs(A[r][c]) > math.abs(A[piv][c]) then piv = r end end
        A[c], A[piv] = A[piv], A[c]
        b[c], b[piv] = b[piv], b[c]
        for r = c + 1, n do
            local f = A[r][c] / A[c][c]
            for k = c, n do A[r][k] = A[r][k] - f * A[c][k] end
            b[r] = b[r] - f * b[c]
        end
    end
    local x = {}
    for r = n, 1, -1 do
        local s = b[r]
        for k = r + 1, n do s = s - A[r][k] * x[k] end
        x[r] = s / A[r][r]
    end
    return x
end

-- Accelerations for angles th and speeds w.
function Pendulum:accel(th, w)
    local n = self.n
    local tail = {} -- tail[i] = m_i + ... + m_n
    local acc = 0
    for i = n, 1, -1 do acc = acc + self.m[i] tail[i] = acc end
    local A, b = {}, {}
    for i = 1, n do
        A[i] = {}
        local rhs = -self.g * self.l[i] * tail[i] * math.sin(th[i])
        for j = 1, n do
            local mm = tail[math.max(i, j)]
            A[i][j] = mm * self.l[i] * self.l[j] * math.cos(th[i] - th[j])
            rhs = rhs - mm * self.l[i] * self.l[j] * math.sin(th[i] - th[j]) * w[j] * w[j]
        end
        b[i] = rhs
    end
    return solve(A, b, n)
end

function Pendulum:step(dt)
    local n = self.n
    local function f(th, w) return w, self:accel(th, w) end
    local function add(a, b, k) local r = {} for i = 1, n do r[i] = a[i] + b[i] * k end return r end
    local th, w = self.th, self.w
    local k1t, k1w = f(th, w)
    local k2t, k2w = f(add(th, k1t, dt / 2), add(w, k1w, dt / 2))
    local k3t, k3w = f(add(th, k2t, dt / 2), add(w, k2w, dt / 2))
    local k4t, k4w = f(add(th, k3t, dt), add(w, k3w, dt))
    for i = 1, n do
        self.th[i] = th[i] + dt / 6 * (k1t[i] + 2 * k2t[i] + 2 * k3t[i] + k4t[i])
        self.w[i] = w[i] + dt / 6 * (k1w[i] + 2 * k2w[i] + 2 * k3w[i] + k4w[i])
    end
    self.t = self.t + dt
    self.steps = self.steps + 1
end

--- Positions of the masses; theta is measured from straight down.
function Pendulum:positions()
    local out, x, y = {}, 0, 0
    for i = 1, self.n do
        x = x + self.l[i] * math.sin(self.th[i])
        y = y - self.l[i] * math.cos(self.th[i])
        out[i] = { x, y }
    end
    return out
end

function Pendulum:energy()
    local n, T, V = self.n, 0, 0
    local vx, vy, y = {}, {}, 0
    local cx, cy = 0, 0
    for i = 1, n do
        cx = cx + self.l[i] * math.cos(self.th[i]) * self.w[i]
        cy = cy + self.l[i] * math.sin(self.th[i]) * self.w[i]
        y = y - self.l[i] * math.cos(self.th[i])
        T = T + 0.5 * self.m[i] * (cx * cx + cy * cy)
        V = V + self.m[i] * self.g * y
    end
    return T + V
end

function Pendulum:formulas()
    local f = {
        string.format("t = %.2f\\,\\mathrm{s}, \\quad E = %.4f\\,\\mathrm{J}", self.t, self:energy()),
        "\\sum_j M_{ij}\\ddot{\\theta}_j = -\\sum_j M_{ij}' \\dot{\\theta}_j^2 - g\\,l_i\\,\\mu_i \\sin\\theta_i",
    }
    for i = 1, math.min(self.n, 4) do
        f[#f + 1] = string.format("\\theta_%d = %.3f, \\quad \\dot{\\theta}_%d = %.3f", i, self.th[i], i, self.w[i])
    end
    return f
end

---------------------------------------------------------------------------
-- Photons through one or two slits (Fraunhofer, far field)
---------------------------------------------------------------------------

local Slits = {}
Slits.__index = Slits
Physlab.slits = {}

function Physlab.slits.new(o)
    local s = setmetatable({
        slits = o.slits or 2, wavelength = o.wavelength or 500e-9, separation = o.separation or 20e-6,
        width = o.width or 5e-6, distance = o.distance or 1.0, half = o.half or 0.05,
        bins = o.bins or 120, counts = {}, total = 0, frames = 0, seed = o.seed or 12345,
    }, Slits)
    for i = 1, s.bins do s.counts[i] = 0 end
    s:_peak()
    return s
end

local function sinc(x) if math.abs(x) < 1e-9 then return 1 end return math.sin(x) / x end

--- Relative intensity at height y on the screen (1 at the centre).
function Slits:intensity(y)
    local sin_t = y / math.sqrt(y * y + self.distance * self.distance)
    local beta = math.pi * self.width * sin_t / self.wavelength
    local single = sinc(beta) ^ 2
    if self.slits == 1 then return single end
    local delta = math.pi * self.separation * sin_t / self.wavelength
    return single * math.cos(delta) ^ 2
end

function Slits:_peak() self.peak = 1 end -- both formulas are 1 at the centre

-- A small deterministic random generator, so a run can be replayed.
function Slits:_rand()
    self.seed = (self.seed * 1103515245 + 12345) % 2147483648
    return self.seed / 2147483648
end

--- Each photon lands where chance and the intensity say (rejection sampling).
function Slits:addPhotons(k)
    for _i = 1, k do
        for _try = 1, 200 do
            local y = (self:_rand() * 2 - 1) * self.half
            if self:_rand() <= self:intensity(y) / self.peak then
                local bin = math.min(self.bins, math.floor((y + self.half) / (2 * self.half) * self.bins) + 1)
                self.counts[bin] = self.counts[bin] + 1
                self.total = self.total + 1
                break
            end
        end
    end
    self.frames = self.frames + 1
end

function Slits:reset()
    for i = 1, self.bins do self.counts[i] = 0 end
    self.total, self.frames = 0, 0
end

--- Shannon entropy (bits) of where the photons landed so far.
function Slits:entropy()
    if self.total == 0 then return 0 end
    local h = 0
    for i = 1, self.bins do
        local c = self.counts[i]
        if c > 0 then
            local p = c / self.total
            h = h - p * math.log(p) / math.log(2)
        end
    end
    return h
end

--- Distance between bright fringes on the screen (two slits): lambda * L / d.
function Slits:fringeSpacing()
    return self.wavelength * self.distance / self.separation
end

function Slits:formulas()
    local f = {
        string.format("\\text{frame } %d,\\; N = %d\\ \\text{photons}", self.frames, self.total),
        self.slits == 2
            and "I(y)\\propto \\mathrm{sinc}^2\\!\\left(\\frac{\\pi a y}{\\lambda L}\\right)\\cos^2\\!\\left(\\frac{\\pi d y}{\\lambda L}\\right)"
            or "I(y)\\propto \\mathrm{sinc}^2\\!\\left(\\frac{\\pi a y}{\\lambda L}\\right)",
        string.format("\\lambda = %.0f\\,\\mathrm{nm},\\; a = %.1f\\,\\mu\\mathrm{m},\\; L = %.2f\\,\\mathrm{m}", self.wavelength * 1e9, self.width * 1e6, self.distance),
    }
    if self.slits == 2 then
        f[#f + 1] = string.format("d = %.1f\\,\\mu\\mathrm{m},\\quad \\Delta y = \\frac{\\lambda L}{d} = %.2f\\,\\mathrm{mm}", self.separation * 1e6, self:fringeSpacing() * 1e3)
    end
    f[#f + 1] = string.format("H = -\\sum_k p_k \\log_2 p_k = %.3f\\ \\mathrm{bits}", self:entropy())
    return f
end

return Physlab
