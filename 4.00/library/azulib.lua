--[[ Azurite v3 — dense in-game UI library (Linoria/Evenesce style) ]]
function missing(t, f, fallback)
	if type(f) == t then return f end
	return fallback
end

cloneref = missing("function", cloneref, function(...) return ... end)
gethui = missing("function", gethui or get_hidden_gui)
protect_gui = missing("function", (syn and syn.protect_gui) or protect_gui)

local Services = setmetatable({}, {
	__index = function(self, name)
		local success, cache = pcall(function()
			return cloneref(game:GetService(name))
		end)
		if success then
			rawset(self, name, cache)
			return cache
		end
		error("Invalid Service: " .. tostring(name))
	end
})

local Players = Services.Players
local TweenService = Services.TweenService
local UserInputService = Services.UserInputService
local RunService = Services.RunService
local CoreGui = Services.CoreGui
local Lighting = Services.Lighting

local LocalPlayer = cloneref(Players.LocalPlayer)
local PlayerGui = cloneref(LocalPlayer:FindFirstChildWhichIsA("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui"))

local Theme = {
	Base=Color3.fromRGB(16,16,21), Top=Color3.fromRGB(18,18,23), Side=Color3.fromRGB(19,19,25),
	Group=Color3.fromRGB(21,21,27), Element=Color3.fromRGB(15,15,20), ElementHov=Color3.fromRGB(30,30,38),
	Input=Color3.fromRGB(15,15,20), Accent=Color3.fromRGB(139,123,240), AccentDim=Color3.fromRGB(111,97,201),
	Text=Color3.fromRGB(230,230,236), SubText=Color3.fromRGB(150,150,165), Muted=Color3.fromRGB(111,111,125),
	Off=Color3.fromRGB(43,43,53), Stroke=Color3.fromRGB(42,42,51), StrokeSub=Color3.fromRGB(33,33,41),
	Warn=Color3.fromRGB(255,176,32), Good=Color3.fromRGB(90,210,140), Bad=Color3.fromRGB(230,106,106),
	Font=Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular),
	FontMed=Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium),
	FontBold=Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold),
	Radius=8, RadiusSm=6, RadiusXs=4,
}
local DEFAULT_ICON = "rbxassetid://10951993034"
local SHADOW_IMG   = "rbxassetid://6014261993"
local SPEED = { mul = 1 }
local function TI(t, style, dir) return TweenInfo.new(t * SPEED.mul, style, dir) end
local E_OUT  = TweenInfo.new(0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local E_FAST = TweenInfo.new(0.22, Enum.EasingStyle.Quad,  Enum.EasingDirection.Out)
local E_POP  = TweenInfo.new(0.48, Enum.EasingStyle.Back,  Enum.EasingDirection.Out)
local E_SMOO = TweenInfo.new(0.46, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local E_SPRING = TweenInfo.new(0.7, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
local E_SNAP = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local function tween(inst, info, goal)
	if SPEED.mul ~= 1 then
		info = TweenInfo.new(info.Time * SPEED.mul, info.EasingStyle, info.EasingDirection, info.RepeatCount, info.Reverses, info.DelayTime)
	end
	local t = TweenService:Create(inst, info, goal); t:Play(); return t
end
local function new(class, props)
	local inst = Instance.new(class); local parent = props.Parent; props.Parent = nil
	for k, v in pairs(props) do if k=="Font" and typeof(v)=="Font" then inst.FontFace = v else inst[k] = v end end
	inst.Parent = parent; return inst
end
local function corner(parent, r) return new("UICorner", { CornerRadius = UDim.new(0, r or 6), Parent = parent }) end
local function pad(parent, t, b, l, r) return new("UIPadding", { PaddingTop=UDim.new(0,t or 0), PaddingBottom=UDim.new(0,b or t or 0), PaddingLeft=UDim.new(0,l or t or 0), PaddingRight=UDim.new(0,r or l or t or 0), Parent=parent }) end

local UILib = {}
UILib.__index = UILib
UILib.Theme = Theme

function UILib:Window(config)
	config = config or {}
	local T = {}
	for k, v in pairs(Theme) do T[k] = v end
	if config.Theme then for k, v in pairs(config.Theme) do T[k] = v end end
	if config.Accent then T.Accent = config.Accent end
	local searchEnabled = config.Search ~= false
	local _conns = {}
	local _aliveRef = { alive = true }
	local function Signal(name)
		local sig = { _fns = {}, Name = name }
		function sig:Connect(fn)
			if type(fn) ~= "function" then warn("[Azurite] "..name..":Connect expects a function"); return { Disconnect = function() end } end
			table.insert(sig._fns, fn)
			return { Disconnect = function()
				for i = #sig._fns, 1, -1 do if sig._fns[i] == fn then table.remove(sig._fns, i) end end
			end }
		end
		function sig:Once(fn)
			local c; c = sig:Connect(function(...) c.Disconnect(); fn(...) end); return c
		end
		function sig:Wait()
			local done, res = false, nil
			local c; c = sig:Connect(function(...) res = table.pack(...); done = true; c.Disconnect() end)
			while not done do task.wait() end
			return table.unpack(res, 1, res.n)
		end
		function sig:Fire(...)
			for _, fn in ipairs(sig._fns) do
				local ok2, err = pcall(fn, ...)
				if not ok2 then warn("[Azurite] "..name.." handler error:", err) end
			end
		end
		return sig
	end
	local _agReg, _afReg = {}, {}   -- accent gradients / accent-coloured texts
	local function regAF(inst) if inst then table.insert(_afReg, inst) end return inst end
	local _newRaw = new
	local new = function(class, props)
		local inst = _newRaw(class, props)
		if inst.Name == "AF" then table.insert(_afReg, inst) end
		return inst
	end
	local _strokeReg = {}
	local function stroke(parent, color, thickness, transparency)
		local st = new("UIStroke", { Color=color or T.Stroke, Thickness=thickness or 1, Transparency=transparency or 0, ApplyStrokeMode=Enum.ApplyStrokeMode.Border, LineJoinMode=Enum.LineJoinMode.Round, Parent=parent })
		if not color then table.insert(_strokeReg, st) end
		return st
	end
	local aLo = Color3.fromRGB(150,120,255); local aHi = Color3.fromRGB(200,86,242)
	if config.Accent then aLo = config.Accent:Lerp(Color3.new(1,1,1),0.2); aHi = config.Accent:Lerp(Color3.new(0,0,0),0.12) end T.Accent = aLo; T.AccentDim = aHi
	local function accentGrad(parent, rot)
		local g = new("UIGradient", { Name="AG", Color=ColorSequence.new(aLo,aHi), Rotation=rot or 40, Parent=parent })
		table.insert(_agReg, g); return g
	end
	local function bgGrad(parent, a, b, rot) return new("UIGradient", { Name="BG", Color=ColorSequence.new(a,b), Rotation=rot or 90, Parent=parent }) end
	local function applyAccent(lo, hi, textCol)
		for _, g in ipairs(_agReg) do if g then pcall(function() g.Color = ColorSequence.new(lo, hi) end) end end
		for _, t in ipairs(_afReg) do if t then pcall(function() t.TextColor3 = textCol or lo end) end end
	end
	local function alive() return _aliveRef.alive end

	local Window = { Flags={}, Elements={}, Categories={}, Open=true, Theme=T, _accent=aLo, _recolor={}, Keybind=config.Keybind or Enum.KeyCode.RightShift }
	Window._flagTaken = {}   -- every config key handed out so far, so two elements never share one
	Window.OnPanic     = Signal("OnPanic")
	Window.OnClose     = Signal("OnClose")
	Window.OnDestroy   = Signal("OnDestroy")
	Window.OnMinimize  = Signal("OnMinimize")
	Window.OnRestore   = Signal("OnRestore")
	Window.OnSkinChanged = Signal("OnSkinChanged")
	Window.OnCategoryChanged = Signal("OnCategoryChanged")
	local UIS_ = setmetatable({}, { __index = function(_, k)
		local v = UserInputService[k]
		if typeof(v) == "RBXScriptSignal" then
			return setmetatable({}, { __index = function(_, m)
				if m == "Connect" then return function(_, fn) local c = v:Connect(fn); table.insert(_conns, c); return c end end
				return function(_, ...) return v[m](v, ...) end
			end })
		end
		if type(v) == "function" then return function(_, ...) return v(UserInputService, ...) end end
		return v
	end })
	local SKINS = {
		dark = {
			Base=Color3.fromRGB(16,16,21), Top=Color3.fromRGB(18,18,23), Side=Color3.fromRGB(19,19,25),
			Group=Color3.fromRGB(21,21,27), Element=Color3.fromRGB(15,15,20), ElementHov=Color3.fromRGB(30,30,38),
			Text=Color3.fromRGB(230,230,236), SubText=Color3.fromRGB(150,150,165), Muted=Color3.fromRGB(111,111,125),
			Off=Color3.fromRGB(43,43,53), StrokeSub=Color3.fromRGB(33,33,41),
			gBase={Color3.fromRGB(21,21,27),Color3.fromRGB(11,11,15)}, gTop={Color3.fromRGB(23,23,29),Color3.fromRGB(17,17,22)},
			gSide={Color3.fromRGB(23,23,28),Color3.fromRGB(16,16,21)}, gGroup={Color3.fromRGB(32,32,40),Color3.fromRGB(22,22,28)},
			gFloat={Color3.fromRGB(26,26,32),Color3.fromRGB(16,16,21)}, alpha=0, stroke=Color3.fromRGB(42,42,51), strokeA=0,
		},
		light = {
			Base=Color3.fromRGB(255,255,255), Top=Color3.fromRGB(255,255,255), Side=Color3.fromRGB(250,251,254),
			Group=Color3.fromRGB(255,255,255), Element=Color3.fromRGB(236,238,244), ElementHov=Color3.fromRGB(224,227,236),
			Text=Color3.fromRGB(20,20,28), SubText=Color3.fromRGB(72,73,88), Muted=Color3.fromRGB(114,116,132),
			Off=Color3.fromRGB(205,207,217), StrokeSub=Color3.fromRGB(214,216,226),
			gBase={Color3.fromRGB(255,255,255),Color3.fromRGB(233,236,244)}, gTop={Color3.fromRGB(255,255,255),Color3.fromRGB(252,252,255)},
			gSide={Color3.fromRGB(252,252,255),Color3.fromRGB(244,245,250)}, gGroup={Color3.fromRGB(255,255,255),Color3.fromRGB(250,251,254)},
			gFloat={Color3.fromRGB(253,253,255),Color3.fromRGB(240,241,247)}, alpha=0, stroke=Color3.fromRGB(206,210,222), strokeA=0,
		},
		transparent = {
			Base=Color3.fromRGB(24,24,32), Top=Color3.fromRGB(34,34,44), Side=Color3.fromRGB(28,28,37),
			Group=Color3.fromRGB(48,48,62), Element=Color3.fromRGB(30,30,40), ElementHov=Color3.fromRGB(64,64,82),
			Text=Color3.fromRGB(255,255,255), SubText=Color3.fromRGB(214,215,228), Muted=Color3.fromRGB(170,172,188),
			Off=Color3.fromRGB(96,98,116), StrokeSub=Color3.fromRGB(96,98,118),
			gBase={Color3.fromRGB(44,44,58),Color3.fromRGB(18,18,26)}, gTop={Color3.fromRGB(56,56,72),Color3.fromRGB(32,32,42)},
			gSide={Color3.fromRGB(46,46,60),Color3.fromRGB(24,24,33)}, gGroup={Color3.fromRGB(72,72,92),Color3.fromRGB(40,40,54)},
			gFloat={Color3.fromRGB(54,54,70),Color3.fromRGB(28,28,38)}, alpha=0.5, stroke=Color3.fromRGB(255,255,255), strokeA=0.6,
		},
	}
	Window._skin = "dark"
	local skinParts = { base={}, top={}, side={}, group={}, element={}, float={}, text={}, sub={}, muted={}, off={}, sep={}, icon={}, stroke={} }
	local function skinTag(inst, role) table.insert(skinParts[role], inst) end
	Window._skinTag = skinTag
	task.defer(function() for _, st in ipairs(_strokeReg) do table.insert(skinParts.stroke, st) end end)
	function Window:SetSkin(name)
		local sk = SKINS[name]; if not sk then return end
		Window._skin = name
		Window.OnSkinChanged:Fire(name)
		Window._accentText = (name == "light")
		task.defer(function() if Window._syncBlur then Window:_syncBlur() end end)
		local function accText() local a = Window._accent; return (name=="light") and Color3.new(a.R*0.62, a.G*0.5, a.B*0.78) or a end
		task.defer(function()
			applyAccent(aLo, aHi, accText())
			for _, fn in ipairs(Window._recolor) do pcall(fn) end
		end)
		T.Base, T.Top, T.Side, T.Group, T.Element, T.ElementHov = sk.Base, sk.Top, sk.Side, sk.Group, sk.Element, sk.ElementHov
		T.Text, T.SubText, T.Muted, T.Off, T.StrokeSub = sk.Text, sk.SubText, sk.Muted, sk.Off, sk.StrokeSub
		local INFO = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		local function paint(list, col, grad, alpha)
			if not alive() then return end
			for _, o in ipairs(list) do
				if o then
					pcall(function() TweenService:Create(o, INFO, { BackgroundColor3 = col, BackgroundTransparency = alpha or 0 }):Play() end)
					local g = o:FindFirstChild("BG")
					if g and grad then g.Color = ColorSequence.new(grad[1], grad[2]) end
				end
			end
		end
		paint(skinParts.base, sk.Base, sk.gBase, sk.alpha)
		paint(skinParts.top, sk.Top, sk.gTop, sk.alpha)
		paint(skinParts.side, sk.Side, sk.gSide, sk.alpha)
		paint(skinParts.group, sk.Group, sk.gGroup, sk.alpha * 0.5)
		paint(skinParts.element, sk.Element, nil, sk.alpha * 0.35)
		paint(skinParts.float, sk.Top, sk.gFloat, sk.alpha * 0.5)
		for _, o in ipairs(skinParts.text) do if o then pcall(function() TweenService:Create(o, INFO, { TextColor3 = sk.Text }):Play() end) end end
		for _, o in ipairs(skinParts.sub) do if o then pcall(function() TweenService:Create(o, INFO, { TextColor3 = sk.SubText }):Play() end) end end
		for _, o in ipairs(skinParts.muted) do if o then pcall(function() TweenService:Create(o, INFO, { TextColor3 = sk.Muted }):Play() end) end end
		for _, o in ipairs(skinParts.off) do if o then pcall(function() TweenService:Create(o, INFO, { BackgroundColor3 = sk.Off }):Play() end) end end
		for _, o in ipairs(skinParts.sep) do if o then pcall(function() TweenService:Create(o, INFO, { BackgroundColor3 = sk.StrokeSub }):Play() end) end end
		for _, o in ipairs(skinParts.icon) do if o then pcall(function() TweenService:Create(o, INFO, { ImageColor3 = sk.Text }):Play() end) end end
		for _, o in ipairs(skinParts.stroke) do if o then pcall(function() TweenService:Create(o, INFO, { Color = sk.stroke, Transparency = sk.strokeA or 0 }):Play() end) end end
	end
	local camera = workspace.CurrentCamera
	local function targetSize()
		local vp = camera and camera.ViewportSize or Vector2.new(1280,720)
		if vp.X < 640 then return UDim2.fromOffset(math.clamp(vp.X-20,300,620), math.clamp(vp.Y-100,320,440)) end
		return config.Size or UDim2.fromOffset(600,400)
	end
	PARENT = nil

	-- ===================== RANDOM + PROTECTION =====================
	local function randomString(len)
		len = len or math.random(16, 28)
		local chars = {}
		for i = 1, len do
			chars[i] = string.char(math.random(97, 122)) -- a-z
		end
		return table.concat(chars)
	end

	local function protectAndParent(gui)
		if gethui then
			local ok = pcall(function()
				gui.Parent = gethui()
			end)
			if ok and gui.Parent then return true end
		end

		if protect_gui then
			local ok = pcall(function()
				protect_gui(gui)
				gui.Parent = CoreGui
			end)
			if ok and gui.Parent then return true end
		end

		if is_sirhurt_closure or typeof(sirhurt) == "table" then
			pcall(function()
				if protect_gui then protect_gui(gui) end
				gui.Parent = CoreGui
			end)
			if gui.Parent then return true end
		end

		pcall(function()
			gui.Parent = CoreGui
		end)

		return gui.Parent ~= nil
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = randomString(22)
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 2147483647
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.IgnoreGuiInset = true

	protectAndParent(gui)
	PARENT = gui
	Window.Gui = gui
	local base = new("Frame", { Name="Base", BackgroundColor3=T.Base, BorderSizePixel=0, AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.fromScale(0.5,0.5), Size=targetSize(), ClipsDescendants=true, Parent=gui })
	corner(base, T.Radius); stroke(base, T.Stroke, 1, 0); bgGrad(base, Color3.fromRGB(21,21,27), Color3.fromRGB(11,11,15)); skinTag(base, "base")
	Window.Base = base
	local baseShadow = new("ImageLabel", { Name="Shadow", BackgroundTransparency=1, AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.fromScale(0.5,0.5), Size=UDim2.new(1,42,1,42), ZIndex=0, Image=SHADOW_IMG, ImageColor3=Color3.new(0,0,0), ImageTransparency=0.4, ScaleType=Enum.ScaleType.Slice, SliceCenter=Rect.new(49,49,450,450), Parent=base })
	table.insert(Window._recolor, function() baseShadow.ImageTransparency = (Window._skin=="light") and 0.82 or 0.4 end)
	new("UISizeConstraint", { MinSize=Vector2.new(300,320), Parent=base })

	local top = new("Frame", { Name="Top", BackgroundColor3=T.Top, BorderSizePixel=0, Size=UDim2.new(1,0,0,40), ZIndex=2, Parent=base })
	bgGrad(top, Color3.fromRGB(23,23,29), Color3.fromRGB(17,17,22)); corner(top, 8); skinTag(top, "top")
	new("Frame", { BackgroundColor3=T.StrokeSub, BorderSizePixel=0, AnchorPoint=Vector2.new(0,1), Position=UDim2.new(0,0,1,0), Size=UDim2.new(1,0,0,1), ZIndex=2, Parent=top })
	local icon = new("ImageLabel", { Name="Icon", BackgroundTransparency=1, Position=UDim2.new(0,12,0.5,-12), Size=UDim2.new(0,24,0,24), ZIndex=3, Image=config.Icon or DEFAULT_ICON, Parent=top })
	corner(icon, 6); Window.Icon = icon; skinTag(icon, "icon")
	local hasSub = (config.Subtitle ~= nil and config.Subtitle ~= "")
	skinTag(new("TextLabel", { BackgroundTransparency=1, Position=UDim2.new(0,44,0.5, hasSub and -13 or -8), Size=UDim2.new(0,200,0,16), Font=T.FontBold, Text=config.Title or "Azurite", TextColor3=T.Text, TextSize=14, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=3, Parent=top }), "text")
	local subLbl
	if hasSub then
		subLbl = new("TextLabel", { Name="Subtitle", BackgroundTransparency=1, Position=UDim2.new(0,44,0.5,3), Size=UDim2.new(0,200,0,12), Font=T.Font, Text=tostring(config.Subtitle), TextColor3=T.Muted, TextSize=10, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=3, Parent=top })
		skinTag(subLbl, "muted")
	end
	function Window:SetSubtitle(txt)
		if subLbl then subLbl.Text = tostring(txt or "") end
	end
	local crumb = new("TextLabel", { Name="Crumb", BackgroundTransparency=1, Position=UDim2.new(0, 44 + (#(config.Title or "Azurite"))*9 + 14, 0.5, -6), Size=UDim2.new(0,260,0,16), Font=T.Font, Text="", TextColor3=T.Muted, TextSize=11, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=3, Parent=top })
	local function topBtn(char, xoff, color)
		local b = new("TextButton", { BackgroundColor3=T.ElementHov, BackgroundTransparency=1, BorderSizePixel=0, AnchorPoint=Vector2.new(1,0.5), Position=UDim2.new(1,xoff,0.5,0), Size=UDim2.new(0,26,0,26), Font=T.FontBold, Text=char, TextColor3=T.Muted, TextSize=15, AutoButtonColor=false, ZIndex=3, Parent=top })
		corner(b, 5); skinTag(b, "muted"); table.insert(Window._recolor, function() if b.BackgroundTransparency == 1 then b.TextColor3 = T.Muted end end)
		local bsc = new("UIScale", { Scale=1, Parent=b })
		b.MouseEnter:Connect(function() tween(b, E_FAST, { BackgroundTransparency=0, TextColor3=color or T.Text }); tween(bsc, E_POP, { Scale=1.12 }) end)
		b.MouseLeave:Connect(function() tween(b, E_FAST, { BackgroundTransparency=1, TextColor3=T.Muted }); tween(bsc, E_FAST, { Scale=1 }) end)
		return b
	end
	local closeBtn = topBtn("\u{00D7}", -10, T.Bad)
	local minBtn   = topBtn("\u{2013}", -42, T.Accent)
	do
		local dragging, dragStart, startPos = false, nil, nil
		top.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging=true; dragStart=input.Position; startPos=base.Position
				input.Changed:Connect(function() if input.UserInputState==Enum.UserInputState.End then dragging=false end end)
			end
		end)
		local goalPos = base.Position
		UIS_.InputChanged:Connect(function(input)
			if dragging and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then
				local d = input.Position - dragStart
				goalPos = UDim2.new(startPos.X.Scale, startPos.X.Offset+d.X, startPos.Y.Scale, startPos.Y.Offset+d.Y)
			end
		end)
		local SNAP = 18
		local vel = Vector2.new()
		local function snapGoal(p)
			local vp = camera and camera.ViewportSize or Vector2.new(1280,720)
			local sz = base.AbsoluteSize
			local x, y = p.X.Offset, p.Y.Offset
			local left, right = x - sz.X/2, x + sz.X/2
			local top, bottom = y - sz.Y/2, y + sz.Y/2
			if math.abs(left) < SNAP then x = sz.X/2
			elseif math.abs(right - vp.X) < SNAP then x = vp.X - sz.X/2 end
			if math.abs(top) < SNAP then y = sz.Y/2
			elseif math.abs(bottom - vp.Y) < SNAP then y = vp.Y - sz.Y/2 end
			return UDim2.new(p.X.Scale, x, p.Y.Scale, y)
		end
		game:GetService("RunService").RenderStepped:Connect(function(dt)
			local px, py = base.Position.X.Offset, base.Position.Y.Offset
			if dragging then
				local a = math.clamp(dt*16, 0, 1)
				base.Position = base.Position:Lerp(snapGoal(goalPos), a)
				vel = Vector2.new(base.Position.X.Offset-px, base.Position.Y.Offset-py)
			elseif vel.Magnitude > 0.4 then
				vel = vel * 0.86
				base.Position = base.Position + UDim2.fromOffset(vel.X, vel.Y)
			end
			if base.Rotation ~= 0 then base.Rotation = 0 end
			if not dragging then
				local vp = camera and camera.ViewportSize or Vector2.new(1280,720)
				local ap, as = base.AbsolutePosition, base.AbsoluteSize
				local dx, dy = 0, 0
				if ap.X + as.X < 80 then dx = 80 - (ap.X + as.X) elseif ap.X > vp.X - 80 then dx = (vp.X - 80) - ap.X end
				if ap.Y < 0 then dy = -ap.Y elseif ap.Y > vp.Y - 60 then dy = (vp.Y - 60) - ap.Y end
				if dx ~= 0 or dy ~= 0 then base.Position = base.Position + UDim2.fromOffset(dx*0.2, dy*0.2) end
			end
		end)
	end
	local side = new("Frame", { Name="Side", BackgroundColor3=T.Side, BorderSizePixel=0, Position=UDim2.new(0,0,0,40), Size=UDim2.new(0,128,1,-40), ZIndex=2, Parent=base })
	bgGrad(side, Color3.fromRGB(23,23,28), Color3.fromRGB(16,16,21)); corner(side, 8); skinTag(side, "side")
	new("Frame", { BackgroundColor3=T.StrokeSub, BorderSizePixel=0, AnchorPoint=Vector2.new(1,0), Position=UDim2.new(1,0,0,0), Size=UDim2.new(0,1,1,0), ZIndex=2, Parent=side })
	local sideList = new("ScrollingFrame", { BackgroundTransparency=1, BorderSizePixel=0, Position=UDim2.new(0,8,0,8), Size=UDim2.new(1,-16,1,-48), ScrollBarThickness=0, CanvasSize=UDim2.new(), AutomaticCanvasSize=Enum.AutomaticSize.Y, ZIndex=2, Parent=side })
	new("UIListLayout", { SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,3), Parent=sideList })
	local footer = new("Frame", { BackgroundTransparency=1, Position=UDim2.new(0,8,1,-34), Size=UDim2.new(1,-16,0,26), ZIndex=2, Parent=side })
	
	
	
	
	
	local content = new("Frame", { Name="Content", BackgroundTransparency=1, Position=UDim2.new(0,128,0,40), Size=UDim2.new(1,-128,1,-40), Parent=base })
	local searchBox, colTop = nil, 8
	if searchEnabled then
		colTop = 42
		local sf = new("Frame", { BackgroundColor3=T.Element, BorderSizePixel=0, Position=UDim2.new(0,10,0,8), Size=UDim2.new(1,-20,0,26), Parent=content })
		corner(sf, T.RadiusSm); skinTag(sf, "element"); local mg = new("Frame", { BackgroundTransparency=1, Position=UDim2.new(0,9,0.5,-6), Size=UDim2.new(0,12,0,12), Parent=sf }); local ring = new("Frame", { BackgroundTransparency=1, Size=UDim2.new(0,9,0,9), Parent=mg }); corner(ring, 5); local rst = stroke(ring, T.Muted, 1, 0); local mgh = new("Frame", { BackgroundColor3=T.Muted, BorderSizePixel=0, AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.new(1,-1,1,-1), Size=UDim2.new(0,4,0,2), Rotation=45, Parent=mg }); table.insert(Window._recolor, function() rst.Color = T.Muted; mgh.BackgroundColor3 = T.Muted end)
		searchBox = new("TextBox", { BackgroundTransparency=1, Position=UDim2.new(0,28,0,0), Size=UDim2.new(1,-80,1,0), Font=T.Font, Text="", PlaceholderText="Search...", PlaceholderColor3=T.Muted, TextColor3=T.Text, TextSize=12, TextXAlignment=Enum.TextXAlignment.Left, ClearTextOnFocus=false, Parent=sf }); skinTag(searchBox, "text")
		Window._searchBox = searchBox
		Window._searchCount = new("TextLabel", { Name="AF", BackgroundTransparency=1, AnchorPoint=Vector2.new(1,0.5), Position=UDim2.new(1,-9,0.5,0), Size=UDim2.new(0,44,1,0), Font=T.FontMed, Text="", TextColor3=aLo, TextSize=11, TextXAlignment=Enum.TextXAlignment.Right, Parent=sf })
		searchBox.Focused:Connect(function() tween(sf, E_FAST, { BackgroundColor3=T.ElementHov }) end)
		searchBox.FocusLost:Connect(function() tween(sf, E_FAST, { BackgroundColor3=T.Element }) end)
	end
	local notifHolder = new("Frame", { Name="Notifications", BackgroundTransparency=1, AnchorPoint=Vector2.new(1,1), Position=UDim2.new(1,-16,1,-16), Size=UDim2.new(0,278,1,-32), ZIndex=50, Parent=gui })
	new("UIListLayout", { SortOrder=Enum.SortOrder.LayoutOrder, VerticalAlignment=Enum.VerticalAlignment.Bottom, HorizontalAlignment=Enum.HorizontalAlignment.Right, Padding=UDim.new(0,7), Parent=notifHolder })
	function Window:Notify(text, opts)
		opts = opts or {}
		if Window._hideNotifs or not alive() then return end
		local duration = opts.Duration or 3.5
		local kind = opts.Type or "info"
		local ac = (kind=="success" and T.Good) or (kind=="warning" and T.Warn) or (kind=="error" and T.Bad) or Window._accent
		local hasTitle = opts.Title ~= nil

		-- holder is what the list layout positions; the card inside is what animates.
		-- (tweening a frame the layout also drives is what made them stutter)
		local holder = new("Frame", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,0), AutomaticSize=Enum.AutomaticSize.Y, ClipsDescendants=true, ZIndex=50, Parent=notifHolder })
		local card = new("Frame", { BackgroundColor3=T.Top, BorderSizePixel=0, Size=UDim2.new(1,0,0,0), AutomaticSize=Enum.AutomaticSize.Y, BackgroundTransparency=1, ZIndex=50, Parent=holder })
		corner(card, 8); bgGrad(card, Color3.fromRGB(32,32,40), Color3.fromRGB(22,22,29)); skinTag(card, "float")
		stroke(card, nil, 1, 0.55)
		local csc = new("UIScale", { Scale=1, Parent=card })
		pad(card, 12, 12, 14, 14)

		local body = new("Frame", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,0), AutomaticSize=Enum.AutomaticSize.Y, ZIndex=51, Parent=card })
		local badge = new("Frame", { BackgroundColor3=ac, BackgroundTransparency=0.86, BorderSizePixel=0, Position=UDim2.new(0,0,0,1), Size=UDim2.new(0,20,0,20), ZIndex=51, Parent=body })
		corner(badge, 6)
		local glyph = (kind=="success" and "\u{2713}") or (kind=="warning" and "!") or (kind=="error" and "\u{00D7}") or "i"
		local glyphLbl = new("TextLabel", { BackgroundTransparency=1, Size=UDim2.new(1,0,1,0), Font=T.FontBold, Text=glyph, TextColor3=ac, TextSize=12, ZIndex=52, Parent=badge })

		local col = new("Frame", { BackgroundTransparency=1, Position=UDim2.new(0,30,0,0), Size=UDim2.new(1,-30,0,0), AutomaticSize=Enum.AutomaticSize.Y, ZIndex=51, Parent=body })
		new("UIListLayout", { SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,3), Parent=col })
		local titleLbl
		if hasTitle then
			titleLbl = new("TextLabel", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,15), Font=T.FontBold, Text=opts.Title, TextColor3=T.Text, TextSize=12, TextXAlignment=Enum.TextXAlignment.Left, TextTransparency=1, ZIndex=51, Parent=col })
			skinTag(titleLbl, "text")
		end
		local bodyLbl = new("TextLabel", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,0), AutomaticSize=Enum.AutomaticSize.Y, Font=T.Font, Text=tostring(text), TextColor3=hasTitle and T.SubText or T.Text, TextSize=12, TextWrapped=true, TextXAlignment=Enum.TextXAlignment.Left, LineHeight=1.15, TextTransparency=1, ZIndex=51, Parent=col })
		skinTag(bodyLbl, hasTitle and "sub" or "text")

		local track = new("Frame", { BackgroundColor3=T.Off, BackgroundTransparency=0.6, BorderSizePixel=0, AnchorPoint=Vector2.new(0,1), Position=UDim2.new(0,-14,1,12), Size=UDim2.new(1,28,0,2), ZIndex=51, Parent=card })
		local prog = new("Frame", { BackgroundColor3=ac, BorderSizePixel=0, Size=UDim2.new(1,0,1,0), ZIndex=52, Parent=track })
		local hit = new("TextButton", { BackgroundTransparency=1, Size=UDim2.new(1,28,1,26), Position=UDim2.new(0,-14,0,-12), Text="", ZIndex=53, Parent=card })

		-- ENTER: one tween per property, on the card only
		card.Position = UDim2.new(0, 28, 0, 0)
		TweenService:Create(card, TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = UDim2.new(0,0,0,0), BackgroundTransparency = 0 }):Play()
		if titleLbl then TweenService:Create(titleLbl, TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextTransparency = 0 }):Play() end
		TweenService:Create(bodyLbl, TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextTransparency = 0 }):Play()

		-- TIMER: a single linear tween, pausable — no per-frame loop, no stutter
		local progTween = TweenService:Create(prog, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = UDim2.new(0,0,1,0) })
		progTween:Play()

		local closing = false
		local function dismiss()
			if closing then return end
			closing = true
			card:SetAttribute("Dead", true)
			pcall(function() progTween:Cancel() end)
			TweenService:Create(card, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1, Position = UDim2.new(0,28,0,0) }):Play()
			for _, o in ipairs({ titleLbl, bodyLbl, glyphLbl }) do
				if o then TweenService:Create(o, TweenInfo.new(0.16), { TextTransparency = 1 }):Play() end
			end
			for _, o in ipairs({ prog, track, badge }) do
				TweenService:Create(o, TweenInfo.new(0.16), { BackgroundTransparency = 1 }):Play()
			end
			task.delay(0.2, function()
				local h = holder.AbsoluteSize.Y
				holder.AutomaticSize = Enum.AutomaticSize.None
				holder.Size = UDim2.new(1, 0, 0, h)
				TweenService:Create(holder, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Size = UDim2.new(1,0,0,0) }):Play()
				task.delay(0.22, function() holder:Destroy() end)
			end)
		end

		hit.MouseEnter:Connect(function()
			pcall(function() progTween:Pause() end)
			TweenService:Create(csc, TweenInfo.new(0.12), { Scale = 1.015 }):Play()
		end)
		hit.MouseLeave:Connect(function()
			if not closing then pcall(function() progTween:Play() end) end
			TweenService:Create(csc, TweenInfo.new(0.12), { Scale = 1 }):Play()
		end)
		hit.MouseButton1Click:Connect(dismiss)

		progTween.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed then dismiss() end
		end)
		task.delay(duration + 8, function() if not closing then dismiss() end end)  -- safety net if paused forever

		return { Dismiss = dismiss }
	end
	local fullSize = targetSize()
	local savedPos = base.Position
	local function applyOpen()
		base.Visible = true
		base.Size = UDim2.fromOffset(fullSize.X.Offset*0.92, fullSize.Y.Offset*0.92); base.BackgroundTransparency = 1
		tween(base, E_POP, { Size=fullSize }); tween(base, E_OUT, { BackgroundTransparency=0 })
	end
	function Window:Minimize()
		if not Window.Open then return end
		Window.Open = false
		if Window._closeSub then Window._closeSub() end
		base.Visible=false; if Window._syncBlur then task.defer(function() Window:_syncBlur() end) end; if Window._syncMouse then task.defer(function() Window:_syncMouse() end) end; if Window.SettingsPanel then Window.SettingsPanel.Visible=false end; Window._wmWas = Window.Watermark and Window.Watermark.Visible; Window._kbWas = Window.KeybindList and Window.KeybindList.Visible; if Window.Watermark then Window.Watermark.Visible=false end; if Window.KeybindList then Window.KeybindList.Visible=false end
		Window._scWas = Window._shortcuts and Window._shortcuts.Visible; if Window._shortcuts then Window._shortcuts.Visible=false end
		Window._plWas = Window._plist and Window._plist.Visible; if Window._plist then Window._plist.Visible=false end
		if Window._pill and not Window._hideMinMark then Window._pill.Visible=true end
		Window.OnMinimize:Fire()
	end
	function Window:Restore()
		Window.Open = true; base.Visible = true; if Window._syncBlur then task.defer(function() Window:_syncBlur() end) end; if Window._syncMouse then task.defer(function() Window:_syncMouse() end) end; if Window._pill then Window._pill.Visible=false end; if Window.Watermark and Window._wmWas then Window.Watermark.Visible=true end; if Window.KeybindList and Window._kbWas then Window.KeybindList.Visible=true end
		if Window._shortcuts and Window._scWas then Window._shortcuts.Visible=true end
		if Window._plist and Window._plWas then Window._plist.Visible=true end
		Window.OnRestore:Fire()
	end
	function Window:Toggle(state) if state==nil then state = not Window.Open end if state then Window:Restore() else Window:Minimize() end end
	function Window:Close() Window:Minimize() end
	Window._cleanups = {}
	function Window:OnCleanup(fn)
		if type(fn) == "function" then table.insert(Window._cleanups, fn) end
		return Window
	end
	function Window:BindConnection(conn)
		if conn and conn.Disconnect then table.insert(_conns, conn) end
		return conn
	end
	function Window:Destroy(reason)
		if not _aliveRef.alive then return end
		Window.OnDestroy:Fire(reason or "destroy")
		for _, fn in ipairs(Window._cleanups) do pcall(fn, reason or "destroy") end
		Window._cleanups = {}
		_aliveRef.alive = false; Window.Alive = false; Window.Open = false
		-- stop every element hook so no user callback fires after teardown
		for _, el in pairs(Window.Elements) do
			if type(el) == "table" then
				el._hooks, el._clicks, el._commits, el._opens, el._closes, el._binds, el._modes = {}, {}, {}, {}, {}, {}, {}
			end
		end
		Window._deps, Window._recolor, Window._anonRefresh, Window._ctxTargets = {}, {}, {}, {}
		pcall(function() UserInputService.MouseBehavior = Enum.MouseBehavior.Default end)
		pcall(function() UserInputService.MouseIconEnabled = true end)
		for _, o in ipairs(game:GetService("Lighting"):GetChildren()) do
			if o:IsA("BlurEffect") and (o.Name == "AzuriteBlur" or o == Window._blur) then pcall(function() o:Destroy() end) end
		end
		for _, c in ipairs(_conns) do pcall(function() c:Disconnect() end) end
		_conns = {}
		gui:Destroy()
	end
	function Window:Panic()
		if not _aliveRef.alive then return end
		Window.OnPanic:Fire()
		if config.OnPanic then pcall(config.OnPanic)
		elseif config.OnClose then pcall(config.OnClose) end
		Window:Destroy("panic")
	end
	function Window:Dialog(opts)
		opts = opts or {}
		local ov = new("Frame", { BackgroundColor3=Color3.new(0,0,0), BackgroundTransparency=1, Size=UDim2.new(1,0,1,0), ZIndex=94, Parent=gui })
		tween(ov, E_OUT, { BackgroundTransparency=0.45 })
		local dlg = new("Frame", { BackgroundColor3=T.Base, BorderSizePixel=0, AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.fromScale(0.5,0.5), Size=UDim2.fromOffset(opts.Width or 300,0), AutomaticSize=Enum.AutomaticSize.Y, ZIndex=95, Parent=ov })
		corner(dlg, 10); bgGrad(dlg, Color3.fromRGB(34,34,44), Color3.fromRGB(18,18,24)); pad(dlg, 16,14,16,16); skinTag(dlg, "group")
		new("UIListLayout", { SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,8), Parent=dlg })
		skinTag(new("TextLabel", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,18), Font=T.FontBold, Text=opts.Title or "Azurite", TextColor3=T.Text, TextSize=15, TextXAlignment=Enum.TextXAlignment.Left, LayoutOrder=1, ZIndex=95, Parent=dlg }), "text")
		if opts.Text then
			skinTag(new("TextLabel", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,0), AutomaticSize=Enum.AutomaticSize.Y, Font=T.Font, Text=opts.Text, TextColor3=T.SubText, TextSize=12, TextWrapped=true, TextXAlignment=Enum.TextXAlignment.Left, LayoutOrder=2, ZIndex=95, Parent=dlg }), "sub")
		end
		local input
		if opts.Input then
			local holder = new("Frame", { BackgroundColor3=T.Element, BorderSizePixel=0, Size=UDim2.new(1,0,0,28), LayoutOrder=3, ZIndex=95, Parent=dlg })
			corner(holder, 6); skinTag(holder, "element")
			input = new("TextBox", { BackgroundTransparency=1, Position=UDim2.new(0,10,0,0), Size=UDim2.new(1,-20,1,0), Font=T.Font, Text=opts.Default or "", PlaceholderText=opts.Placeholder or "", PlaceholderColor3=T.Muted, TextColor3=T.Text, TextSize=12, TextXAlignment=Enum.TextXAlignment.Left, ClearTextOnFocus=false, ZIndex=96, Parent=holder })
			skinTag(input, "text")
		end
		local row = new("Frame", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,32), LayoutOrder=90, ZIndex=95, Parent=dlg })
		new("UIListLayout", { FillDirection=Enum.FillDirection.Horizontal, SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,8), Parent=row })
		local function close(result)
			tween(ov, E_FAST, { BackgroundTransparency=1 })
			task.delay(0.18, function() ov:Destroy() end)
			if opts.Callback then task.spawn(opts.Callback, result, input and input.Text or nil) end
		end
		local buttons = opts.Buttons or { { opts.CancelText or "Cancel", false }, { opts.ConfirmText or "Confirm", true, true } }
		for idx, bdef in ipairs(buttons) do
			local isPrimary = bdef[3]
			local b = new("TextButton", { LayoutOrder=idx, BackgroundColor3=isPrimary and (opts.Danger and T.Bad or Window._accent) or T.Element, BorderSizePixel=0, Size=UDim2.new(1/#buttons,-4,1,0), Font=T.FontMed, Text=bdef[1], TextColor3=isPrimary and Color3.new(1,1,1) or T.SubText, TextSize=12, AutoButtonColor=false, ZIndex=95, Parent=row })
			corner(b, 6); if not isPrimary then skinTag(b, "element") end
			b.MouseEnter:Connect(function() tween(b, E_FAST, { BackgroundTransparency=0.15 }) end)
			b.MouseLeave:Connect(function() tween(b, E_FAST, { BackgroundTransparency=0 }) end)
			b.MouseButton1Click:Connect(function() close(bdef[2]) end)
		end
		local sc = new("UIScale", { Scale=0.92, Parent=dlg }); tween(sc, E_POP, { Scale=1 })
		if input then task.defer(function() input:CaptureFocus() end) end
		return { Close = function() close(nil) end }
	end
	function Window:Confirm(title, text, cb, danger)
		return Window:Dialog({ Title=title, Text=text, Danger=danger, Callback=function(ok2) if cb then cb(ok2 == true) end end })
	end
	function Window:Prompt(title, placeholder, cb)
		return Window:Dialog({ Title=title, Input=true, Placeholder=placeholder, Callback=function(ok2, txt) if cb then cb(ok2 == true and txt or nil) end end })
	end
	function Window:_modeDialog(name, modes, current, cb)
		if Window._modeOpen then return end
		Window._modeOpen = true
		local ov = new("Frame", { BackgroundColor3=Color3.new(0,0,0), BackgroundTransparency=1, Size=UDim2.new(1,0,1,0), ZIndex=92, Parent=gui })
		tween(ov, E_OUT, { BackgroundTransparency=0.45 })
		local dlg = new("Frame", { BackgroundColor3=T.Base, BorderSizePixel=0, AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.fromScale(0.5,0.5), Size=UDim2.fromOffset(280,0), AutomaticSize=Enum.AutomaticSize.Y, ZIndex=93, Parent=ov })
		corner(dlg, 10); bgGrad(dlg, Color3.fromRGB(34,34,44), Color3.fromRGB(18,18,24)); pad(dlg, 16,14,16,16); skinTag(dlg, "group")
		new("UIListLayout", { SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,7), Parent=dlg })
		skinTag(new("TextLabel", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,18), Font=T.FontBold, Text="Bind mode", TextColor3=T.Text, TextSize=15, TextXAlignment=Enum.TextXAlignment.Left, LayoutOrder=1, ZIndex=93, Parent=dlg }), "text")
		skinTag(new("TextLabel", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,30), Font=T.Font, Text=("How should \"%s\" behave?"):format(tostring(name)), TextColor3=T.SubText, TextSize=12, TextWrapped=true, TextXAlignment=Enum.TextXAlignment.Left, TextYAlignment=Enum.TextYAlignment.Top, LayoutOrder=2, ZIndex=93, Parent=dlg }), "sub")
		local desc = { Toggle = "press once to turn on, again to turn off", Hold = "active only while the key is held", Always = "always on, ignores the key" }
		for idx, m in ipairs(modes) do
			local b = new("TextButton", { BackgroundColor3=T.Element, BorderSizePixel=0, Size=UDim2.new(1,0,0,40), Text="", AutoButtonColor=false, LayoutOrder=2+idx, ZIndex=93, Parent=dlg })
			corner(b, 6); skinTag(b, "element")
			local nm = new("TextLabel", { BackgroundTransparency=1, Position=UDim2.new(0,11,0,5), Size=UDim2.new(1,-22,0,15), Font=T.FontMed, Text=m, TextColor3=(m==current) and Window._accent or T.Text, TextSize=12, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=94, Parent=b })
			if m ~= current then skinTag(nm, "text") end
			skinTag(new("TextLabel", { BackgroundTransparency=1, Position=UDim2.new(0,11,0,20), Size=UDim2.new(1,-22,0,14), Font=T.Font, Text=desc[m] or "", TextColor3=T.Muted, TextSize=10, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=94, Parent=b }), "muted")
			b.MouseEnter:Connect(function() tween(b, E_FAST, { BackgroundColor3=T.ElementHov }) end)
			b.MouseLeave:Connect(function() tween(b, E_FAST, { BackgroundColor3=T.Element }) end)
			b.MouseButton1Click:Connect(function()
				Window._modeOpen = false
				tween(ov, E_FAST, { BackgroundTransparency=1 })
				task.delay(0.18, function() ov:Destroy() end)
				if cb then task.spawn(cb, m) end
			end)
		end
		local cancel = new("TextButton", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,24), Font=T.Font, Text="Cancel", TextColor3=T.Muted, TextSize=11, AutoButtonColor=false, LayoutOrder=99, ZIndex=93, Parent=dlg })
		skinTag(cancel, "muted")
		cancel.MouseButton1Click:Connect(function()
			Window._modeOpen = false
			tween(ov, E_FAST, { BackgroundTransparency=1 })
			task.delay(0.18, function() ov:Destroy() end)
		end)
		local sc = new("UIScale", { Scale=0.92, Parent=dlg }); tween(sc, E_POP, { Scale=1 })
	end
	function Window:Exit()
		if Window._exitOpen then return end
		Window._exitOpen = true
		local ov = new("Frame", { BackgroundColor3=Color3.new(0,0,0), BackgroundTransparency=1, Size=UDim2.new(1,0,1,0), ZIndex=90, Parent=gui })
		tween(ov, E_OUT, { BackgroundTransparency=0.45 })
		local dlg = new("Frame", { BackgroundColor3=T.Base, BorderSizePixel=0, AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.fromScale(0.5,0.5), Size=UDim2.fromOffset(272,128), ZIndex=91, Parent=ov })
		corner(dlg, 10); bgGrad(dlg, Color3.fromRGB(24,24,30), Color3.fromRGB(14,14,18)); pad(dlg, 16,14,16,16)
		new("TextLabel", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,18), Font=T.FontBold, Text="Close Azurite?", TextColor3=T.Text, TextSize=15, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=91, Parent=dlg })
		new("TextLabel", { BackgroundTransparency=1, Position=UDim2.new(0,0,0,26), Size=UDim2.new(1,0,0,40), Font=T.Font, Text="This will remove the entire Azurite interface. This can't be undone.", TextColor3=T.SubText, TextSize=12, TextWrapped=true, TextXAlignment=Enum.TextXAlignment.Left, TextYAlignment=Enum.TextYAlignment.Top, ZIndex=91, Parent=dlg })
		local cancel = new("TextButton", { BackgroundColor3=T.Element, BorderSizePixel=0, AnchorPoint=Vector2.new(0,1), Position=UDim2.new(0,0,1,0), Size=UDim2.new(0.5,-4,0,30), Font=T.FontMed, Text="Cancel", TextColor3=T.SubText, TextSize=12, AutoButtonColor=false, ZIndex=91, Parent=dlg }); corner(cancel,6)
		local conf = new("TextButton", { BackgroundColor3=T.Bad, BorderSizePixel=0, AnchorPoint=Vector2.new(1,1), Position=UDim2.new(1,0,1,0), Size=UDim2.new(0.5,-4,0,30), Font=T.FontMed, Text="Close", TextColor3=Color3.new(1,1,1), TextSize=12, AutoButtonColor=false, ZIndex=91, Parent=dlg }); corner(conf,6)
		tween(dlg, E_POP, { Size=UDim2.fromOffset(300,142) })
		cancel.MouseButton1Click:Connect(function() tween(ov,E_FAST,{BackgroundTransparency=1}); for _,d in ipairs(dlg:GetDescendants()) do pcall(function() tween(d,E_FAST,{TextTransparency=1,BackgroundTransparency=1}) end) end; tween(dlg,E_FAST,{BackgroundTransparency=1}); task.delay(0.16,function() ov:Destroy() end); Window._exitOpen=false end)
		conf.MouseButton1Click:Connect(function()
			Window._exitOpen=false
			Window.OnClose:Fire()
			if config.OnClose then pcall(config.OnClose) end
			Window:Destroy("close")
		end)
	end
	closeBtn.MouseButton1Click:Connect(function() Window:Exit() end)
	minBtn.MouseButton1Click:Connect(function() Window:Minimize() end)
	local bubble = new("TextButton", { Name="Reopen", BackgroundColor3=T.Top, BorderSizePixel=0, AnchorPoint=Vector2.new(0.5,0), Position=UDim2.new(0.5,0,0,8), Size=UDim2.new(0,34,0,30), AutoButtonColor=false, Text="", Visible=false, ZIndex=41, Parent=gui }); Window._pill = bubble; skinTag(new("ImageLabel", { BackgroundTransparency=1, AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.fromScale(0.5,0.5), Size=UDim2.new(0,16,0,16), Image=config.Icon or DEFAULT_ICON, ImageColor3=Color3.new(1,1,1), ZIndex=41, Parent=bubble }), "icon")
	corner(bubble, 8); bgGrad(bubble, Color3.fromRGB(26,26,32), Color3.fromRGB(16,16,21)); skinTag(bubble, "float")
	bubble.MouseButton1Click:Connect(function() Window:Restore() end)
	
	local MODKEY = {
		[Enum.KeyCode.LeftControl]=true, [Enum.KeyCode.RightControl]=true,
		[Enum.KeyCode.LeftShift]=true,   [Enum.KeyCode.RightShift]=true,
		[Enum.KeyCode.LeftAlt]=true,     [Enum.KeyCode.RightAlt]=true,
	}
	Window._MODKEY = MODKEY
	local heldMods, comboUsed = {}, {}
	Window._comboUsed = comboUsed
	local function runSystemBinds(kc)
		if kc == Window.Keybind then Window:Toggle() end
		if Window._minKey and kc == Window._minKey then if Window.Open then Window:Minimize() else Window:Restore() end end
		if Window._exitKey and kc == Window._exitKey then Window:Exit() end
		if Window._panicKey and kc == Window._panicKey then Window:Panic() end
	end
	UIS_.InputBegan:Connect(function(input, processed)
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		local kc = input.KeyCode
		if MODKEY[kc] then heldMods[kc] = true; comboUsed[kc] = false; return end
		for mk in pairs(heldMods) do comboUsed[mk] = true end
		if processed or Window._typing then return end
		if Window._ctrlDown and Window._ctrlDown() then return end
		runSystemBinds(kc)
	end)
	UIS_.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		local kc = input.KeyCode
		if not MODKEY[kc] then return end
		local used = comboUsed[kc]
		heldMods[kc] = nil; comboUsed[kc] = nil
		if used or Window._typing then return end
		runSystemBinds(kc)
	end)
	if camera then camera:GetPropertyChangedSignal("ViewportSize"):Connect(function() fullSize = targetSize(); if Window.Open then tween(base, E_FAST, { Size=fullSize }) end end) end
	Window._keyOwners = {}
	Window._pendingBinds = {}
	function Window:_bindKey(newKey, oldKey, id)
		if oldKey then Window._keyOwners[oldKey.Name]=nil end
		if newKey then if Window._keyOwners[newKey.Name] and Window._keyOwners[newKey.Name]~=id then return false end Window._keyOwners[newKey.Name]=id end
		return true
	end
	Window._deps = {}
	Window._ctxTargets = {}
	local ctx = new("Frame", { Name="Ctx", BackgroundColor3=T.Top, BorderSizePixel=0, Size=UDim2.new(0,146,0,0), AutomaticSize=Enum.AutomaticSize.Y, Visible=false, ZIndex=88, Parent=gui })
	corner(ctx, 7); bgGrad(ctx, Color3.fromRGB(44,44,55), Color3.fromRGB(26,26,33)); pad(ctx, 5,5,5,5)

	new("UIListLayout", { SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,1), Parent=ctx })
	local ctxScale = new("UIScale", { Scale=1, Parent=ctx })
	local ctxBlocker = new("TextButton", { BackgroundTransparency=1, Size=UDim2.new(1,0,1,0), Text="", Visible=false, ZIndex=87, Parent=gui })
	ctxBlocker.MouseButton1Click:Connect(function() ctx.Visible=false; ctxBlocker.Visible=false end)
	UIS_.InputBegan:Connect(function(input, processed)
		if input.UserInputType ~= Enum.UserInputType.MouseButton2 then return end
		if not Window.Open or ctx.Visible then return end
		local m = UserInputService:GetMouseLocation()
		local hit
		for _, t in ipairs(Window._ctxTargets) do
			local f = t.frame
			if f and f.Parent and f.Visible then
				local p, sz = f.AbsolutePosition, f.AbsoluteSize
				if m.X >= p.X and m.X <= p.X + sz.X and m.Y >= p.Y + 36 and m.Y <= p.Y + sz.Y + 36 then hit = t break end
			end
		end
		if not hit then return end
		local el, ttl = hit.el, hit.title
		local items = {}
		local dkey = el.Flag or ttl   -- config key, which is no longer always the display name
		if el.Set and Window._defaults and Window._defaults[dkey] ~= nil then
			table.insert(items, { "Reset to default", function() pcall(function() el:Set(Window._defaults[dkey]) end) end })
		end
		local v = el.Get and el:Get() or el.Value
		if v ~= nil then
			table.insert(items, { "Copy value", function()
				local str = (typeof(v)=="Color3") and ("%d,%d,%d"):format(v.R*255,v.G*255,v.B*255) or (typeof(v)=="EnumItem" and v.Name or tostring(v))
				if setclipboard then pcall(setclipboard, str) end
				Window:Notify(ttl..": "..str, { Duration=3 })
			end })
		end
		table.insert(items, { "Search this", function() if Window._searchBox then Window._searchBox.Text = ttl end end })
		Window:_showCtx(items)
	end)
	local RunSvc = game:GetService("RunService")
	local function normLoop(a, b, who)
		local fn, interval = a, b
		if type(fn) == "number" or type(interval) == "function" then fn, interval = b, a end
		if type(fn) ~= "function" then
			warn(("[Azurite] %s expects a function, got %s"):format(who or "OnLoop", typeof(fn)))
			return nil, 0
		end
		if type(interval) ~= "number" or interval ~= interval or interval < 0 then interval = 0 end
		return fn, interval
	end
	local function normFn(fn, who)
		if type(fn) ~= "function" then
			warn(("[Azurite] %s expects a function, got %s"):format(who or "callback", typeof(fn)))
			return nil
		end
		return fn
	end
	-- Ticks fn every `interval` seconds while shouldRun() (and the window) stays alive.
	-- fn runs in its own thread per tick, so a callback that yields forever (stale remote,
	-- etc.) can't suspend the loop itself; a tick is skipped instead while the previous one
	-- is still pending. The next tick is scheduled off a fixed deadline, so the callback's
	-- own runtime doesn't get added on top of the interval.
	local function spawnLoop(interval, shouldRun, fn, onStop)
		task.spawn(function()
			local busy, warned = false, false
			local nextTick = os.clock()
			while (not shouldRun or shouldRun()) and alive() do
				if busy then
					if not warned then
						warned = true
						warn(("[Azurite] OnLoop: callback still pending after %gs, skipping ticks"):format(interval))
					end
				else
					busy, warned = true, false
					task.spawn(function()
						local ok2, err = pcall(fn)
						if not ok2 then warn("[Azurite]", err) end
						busy = false
					end)
				end
				nextTick += interval
				local dt = nextTick - os.clock()
				if dt > 0 then task.wait(dt) else nextTick = os.clock(); task.wait() end
			end
			if onStop then onStop() end
		end)
	end
	Window._normLoop, Window._normFn, Window._spawnLoop = normLoop, normFn, spawnLoop
	local function stateHelpers(el, getter)
		el._hooks = {}
		el._fireHooks = function(v) for _, h in ipairs(el._hooks) do task.spawn(h, v) end end
		function el:GetState() return getter() and true or false end
		function el:OnChanged(fn) if not normFn(fn, "OnChanged") then return el end table.insert(el._hooks, fn); task.spawn(fn, el:GetState()); return el end
		function el:OnEnabled(fn)  return el:OnChanged(function(v) if v then fn() end end) end
		function el:OnDisabled(fn) return el:OnChanged(function(v) if not v then fn() end end) end
		local function connectWhileActive(signal, fn)
			if not normFn(fn, "OnRender/OnStep/OnPhysics") then return el end
			local conn
			el:OnChanged(function(v)
				if v and not conn then
					conn = signal:Connect(function(...) local ok2, err = pcall(fn, ...) if not ok2 then warn("[Azurite]", err) end end)
					table.insert(_conns, conn)
				elseif not v and conn then conn:Disconnect(); conn = nil end
			end)
			return el
		end
		function el:OnRender(fn)    return connectWhileActive(RunSvc.RenderStepped, fn) end
		function el:WhileActive(fn) return el:OnRender(fn) end
		function el:Every(interval, fn) return el:OnLoop(fn, interval) end   -- order-agnostic via normLoop
		function el:OnStep(fn)      return connectWhileActive(RunSvc.Heartbeat, fn) end
		function el:OnPhysics(fn)   return connectWhileActive(RunSvc.Stepped, fn) end
		function el:OnLoop(fn, interval)
			local f2, iv = normLoop(fn, interval, "OnLoop")
			if not f2 then return el end
			local running = false
			el:OnChanged(function(v)
				if v and not running then
					running = true
					spawnLoop(iv, function() return el:GetState() end, f2, function() running = false end)
				end
			end)
			return el
		end
		return el
	end
	Window._stateHelpers = stateHelpers
	Window._typing = false
	local function ctrlDown()
		return UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
	end
	Window._ctrlDown = ctrlDown
	table.insert(_conns, UserInputService.TextBoxFocused:Connect(function() Window._typing = true end))
	table.insert(_conns, UserInputService.TextBoxFocusReleased:Connect(function() Window._typing = false end))
	Window._anon = (config.Anonymous == true)
	Window._anonRefresh = {}
	local _anonIds = {}
	function Window:AnonName(p)
		if not Window._anon then return (typeof(p)=="Instance") and p.DisplayName or tostring(p) end
		if typeof(p) ~= "Instance" then return "Player" end
		if p == LocalPlayer then return "You" end
		if not _anonIds[p.UserId] then
			local n = 0
			for _ in pairs(_anonIds) do n += 1 end
			_anonIds[p.UserId] = n + 1
		end
		return "Player " .. _anonIds[p.UserId]
	end
	function Window:AnonTag(p)
		if not Window._anon then return "@" .. ((typeof(p)=="Instance") and p.Name or tostring(p)) end
		return "@hidden"
	end
	function Window:SetAnonymous(v)
		Window._anon = v and true or false
		for _, fn in ipairs(Window._anonRefresh) do pcall(fn) end
	end
	local subPop = new("ScrollingFrame", { Name="SubPop", BackgroundColor3=Color3.fromRGB(34,34,44), BackgroundTransparency=0, BorderSizePixel=0, Size=UDim2.new(0,216,0,0), CanvasSize=UDim2.new(), AutomaticCanvasSize=Enum.AutomaticSize.Y, ScrollBarThickness=2, ScrollBarImageColor3=Color3.fromRGB(120,120,140), ScrollBarImageTransparency=0.35, ScrollingDirection=Enum.ScrollingDirection.Y, Visible=false, ClipsDescendants=true, ZIndex=76, Parent=gui })
	corner(subPop, 8); bgGrad(subPop, Color3.fromRGB(56,56,70), Color3.fromRGB(34,34,44)); pad(subPop, 10,11,11,11); skinTag(subPop, "group")
	stroke(subPop, nil, 1, 0.35)
	new("ImageLabel", { BackgroundTransparency=1, AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.fromScale(0.5,0.5), Size=UDim2.new(1,40,1,40), ZIndex=75, Image=SHADOW_IMG, ImageColor3=Color3.new(0,0,0), ImageTransparency=0.45, ScaleType=Enum.ScaleType.Slice, SliceCenter=Rect.new(49,49,450,450), Parent=subPop })
	new("UIListLayout", { SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,5), Parent=subPop })
	local subScale = new("UIScale", { Scale=1, Parent=subPop })
	local subBlocker = new("TextButton", { BackgroundTransparency=1, Size=UDim2.new(1,0,1,0), Text="", Visible=false, ZIndex=75, Parent=gui })
	Window._subPop, Window._subOwner = subPop, nil
	local function closeSub()
		if not subPop.Visible then return end
		tween(subScale, E_FAST, { Scale=0.9 })
		task.delay(0.12, function() subPop.Visible=false; subBlocker.Visible=false; if Window._subOwner then Window._subOwner.Parent = subPop end end)
		Window._subOwner = nil
	end
	Window._closeSub = closeSub
	subBlocker.MouseButton1Click:Connect(closeSub)
	function Window:_openSub(content, anchorFrame)
		for _, c in ipairs(subPop:GetChildren()) do if c:IsA("GuiObject") then c.Visible = false end end
		content.Parent = subPop; content.Visible = true
		for _, d in ipairs(content:GetDescendants()) do if d:IsA("GuiObject") and d.ZIndex < 77 then d.ZIndex = 77 end end
		content.ZIndex = 77
		Window._subOwner = content
		local p, sz = anchorFrame.AbsolutePosition, anchorFrame.AbsoluteSize
		subPop.Visible = true; subBlocker.Visible = true
		task.defer(function()
			local lay = subPop:FindFirstChildOfClass("UIListLayout")
			local vp = camera and camera.ViewportSize or Vector2.new(1280,720)
			local h = math.min((lay and lay.AbsoluteContentSize.Y or 200) + 22, math.max(160, vp.Y - 140))
			subPop.Size = UDim2.new(0, 216, 0, h)
			local px = p.X + sz.X + 8
			local py = p.Y + 30
			if px + 216 > vp.X - 8 then px = math.max(8, p.X - 224) end
			if py + h > vp.Y - 8 then py = math.max(8, vp.Y - h - 8) end
			subPop.Position = UDim2.fromOffset(px, py)
		end)
		subScale.Scale = 0.9; tween(subScale, E_SNAP, { Scale=1 })
	end
	Window.Alive = true
	Window._alive = alive
	do -- cursor handling: free the mouse while the menu is open
		local UIS = UserInputService
		Window._mouseMode = config.MouseMode or "free"   -- "free" | "keep" (never touch the game's lock)
		local saved = { behavior = nil, icon = nil, sensitivity = nil }
		local held = false
		function Window:_syncMouse()
			if Window._mouseMode ~= "free" then
				if held then
					held = false
					pcall(function() UIS.MouseBehavior = saved.behavior or Enum.MouseBehavior.Default end)
					pcall(function() UIS.MouseIconEnabled = (saved.icon ~= false) end)
				end
				return
			end
			local wantFree = Window.Open and _aliveRef.alive
			if wantFree and not held then
				held = true
				saved.behavior = UIS.MouseBehavior
				saved.icon = UIS.MouseIconEnabled
			elseif not wantFree and held then
				held = false
				pcall(function() UIS.MouseBehavior = saved.behavior or Enum.MouseBehavior.Default end)
				pcall(function() UIS.MouseIconEnabled = (saved.icon ~= false) end)
			end
		end
		task.spawn(function()
			while alive() do
				if Window._mouseMode == "free" and Window.Open then
					-- re-assert every frame: shiftlock / first person keep forcing LockCenter back
					if UIS.MouseBehavior ~= Enum.MouseBehavior.Default then pcall(function() UIS.MouseBehavior = Enum.MouseBehavior.Default end) end
					if not UIS.MouseIconEnabled then pcall(function() UIS.MouseIconEnabled = true end) end
				end
				game:GetService("RunService").RenderStepped:Wait()
			end
			pcall(function() UIS.MouseBehavior = Enum.MouseBehavior.Default end)
		end)
	end
	Window.IsAlive = function() return _aliveRef.alive end
	task.spawn(function()
		while alive() do
			local f = UserInputService:GetFocusedTextBox()
			Window._typing = (f ~= nil)
			task.wait(0.08)
		end
	end)
	function Window:_showCtx(items)
		for _, c in ipairs(ctx:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
		for _, it in ipairs(items) do
			local b = new("TextButton", { BackgroundColor3=T.Element, BackgroundTransparency=0.35, BorderSizePixel=0, Size=UDim2.new(1,0,0,26), Font=T.Font, Text="  "..it[1], TextColor3=T.SubText, TextSize=12, TextXAlignment=Enum.TextXAlignment.Left, AutoButtonColor=false, ZIndex=89, Parent=ctx })
			corner(b, 5)
			b.MouseEnter:Connect(function() tween(b, E_FAST, { BackgroundTransparency=0, TextColor3=T.Text }) end)
			b.MouseLeave:Connect(function() tween(b, E_FAST, { BackgroundTransparency=0.35, TextColor3=T.SubText }) end)
			b.MouseButton1Click:Connect(function() ctx.Visible=false; ctxBlocker.Visible=false; task.spawn(it[2]) end)
		end
		local m = UserInputService:GetMouseLocation()
		ctx.Visible = true; ctxBlocker.Visible = true
		task.defer(function()
			local vp = camera and camera.ViewportSize or Vector2.new(1280,720)
			local sz = ctx.AbsoluteSize
			local x = math.min(m.X, vp.X - sz.X - 8)
			local y = math.clamp(m.Y - 36, 8, math.max(8, vp.Y - sz.Y - 8))
			ctx.Position = UDim2.fromOffset(math.max(8, x), y)
		end)
		ctxScale.Scale = 0.88; tween(ctxScale, E_SNAP, { Scale=1 })
	end
	task.spawn(function() while alive() do for _, fn in ipairs(Window._deps) do pcall(fn) end task.wait(0.15) end end)
	function Window:GetConfig()
		local out = {}
		for flag, value in pairs(Window.Flags) do
			if typeof(value)=="EnumItem" then out[flag]=value.Name
			elseif typeof(value)=="Color3" then out[flag]={value.R,value.G,value.B}
			elseif type(value)=="table" then local c={} for i,x in ipairs(value) do c[i]=x end out[flag]=c
			else out[flag]=value end
		end
		return out
	end
	Window._undoStack = {}
	function Window:Snapshot(label)
		table.insert(Window._undoStack, { cfg = Window:GetConfig(), label = label or "change" })
		if #Window._undoStack > 10 then table.remove(Window._undoStack, 1) end
	end
	function Window:Undo()
		local last = table.remove(Window._undoStack)
		if not last then Window:Notify("Nothing to undo", { Duration = 2 }); return false end
		Window:LoadConfig(last.cfg, true)
		Window:Notify("Undid: " .. last.label, { Type = "success", Duration = 2 })
		return true
	end
	function Window:LoadConfig(data, skipSnapshot)
		if not skipSnapshot then Window:Snapshot("config load") end
		return Window:_applyConfig(data)
	end
	function Window:_applyConfig(data)
		if type(data)~="table" then return end
		for flag, value in pairs(data) do
			local el = Window.Elements[flag]
			if el and el.Set then
				if type(value)=="table" and #value==3 and type(value[1])=="number" and value[1]<=1 then value = Color3.new(value[1],value[2],value[3]) end
				pcall(function() el:Set(value) end)
			end
		end
	end
	local ATTR = "AzuriteCfg"
	local function enc(t)
		local ok, res = pcall(function() return game:GetService("HttpService"):JSONEncode(t) end)
		return ok and res or nil
	end
	local function dec(str)
		local ok, res = pcall(function() return game:GetService("HttpService"):JSONDecode(str) end)
		return ok and res or nil
	end
	-- Profiles are written to a real file when the executor exposes one, so they survive a
	-- rejoin. A LocalPlayer attribute is kept in sync as the fallback store for Studio and
	-- executors without filesystem access, where it only lasts for the session.
	local CFG_DIR = tostring(config.ConfigFolder or "Azurite")
	local CFG_FILE = CFG_DIR .. "/configs.json"
	local _writefile, _readfile, _isfile = writefile, readfile, isfile
	local _isfolder, _makefolder = isfolder, makefolder
	local hasFS = type(_writefile) == "function" and type(_readfile) == "function" and type(_isfile) == "function"
	local function fsRead()
		if not hasFS then return nil end
		local ok, res = pcall(function() if _isfile(CFG_FILE) then return _readfile(CFG_FILE) end return nil end)
		return ok and res or nil
	end
	local function fsWrite(str)
		if not hasFS then return false end
		return (pcall(function()
			if type(_isfolder) == "function" and type(_makefolder) == "function" and not _isfolder(CFG_DIR) then _makefolder(CFG_DIR) end
			_writefile(CFG_FILE, str)
		end))
	end
	-- Falls back to the attribute store when there is no file yet, so a session that
	-- saved before the file store existed still finds its profiles.
	local function readAll()
		return dec(fsRead() or "") or dec(LocalPlayer:GetAttribute(ATTR) or "") or {}
	end
	local warnedFS = false
	local function writeAll(all)
		local e = enc(all)
		if not e then return false end
		LocalPlayer:SetAttribute(ATTR, e)
		if hasFS and not fsWrite(e) then
			if not warnedFS then   -- autosave runs every few seconds; say it once
				warnedFS = true
				warn("[Azurite] could not write " .. CFG_FILE .. " - profiles will only last this session")
			end
			return false
		end
		return true
	end
	function Window:StorageMode() return hasFS and "file" or "session" end
	function Window:SaveProfile(name)
		name = name or "default"
		local all = readAll()
		all[name] = Window:GetConfig()
		local ok = writeAll(all)
		if name ~= "__auto" then
			if ok then Window:Notify("Profile '"..name.."' saved", { Type="success", Duration=2 })
			else Window:Notify("Could not save '"..name.."'", { Type="warning", Duration=3 }) end
		end
		return all[name]
	end
	function Window:LoadProfile(name)
		name = name or "default"
		local all = readAll()
		if not all[name] then
			if name ~= "__auto" then Window:Notify("No profile '"..name.."'", { Type="warning", Duration=2 }) end
			return false
		end
		Window:LoadConfig(all[name], name == "__auto")
		if name ~= "__auto" then Window:Notify("Profile '"..name.."' loaded", { Type="success", Duration=2 }) end
		return true
	end
	function Window:ListProfiles()
		local out = {}
		for k in pairs(readAll()) do if k ~= "__auto" then table.insert(out, k) end end
		table.sort(out)
		return out
	end
	function Window:DeleteProfile(name)
		local all = readAll()
		all[name or "default"] = nil
		writeAll(all)
	end

	local configOverlay
	function Window:ShowConfig()
		if configOverlay then configOverlay:Destroy() end
		local ov = new("Frame", { BackgroundColor3=Color3.new(0,0,0), BackgroundTransparency=1, Size=UDim2.new(1,0,1,0), ZIndex=60, Parent=gui })
		configOverlay = ov; tween(ov, E_OUT, { BackgroundTransparency=0.5 })
		local panel = new("Frame", { BackgroundColor3=T.Base, BorderSizePixel=0, AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.fromScale(0.5,0.5), Size=UDim2.fromOffset(340,360), ZIndex=61, Parent=ov }); skinTag(panel, "float")
		corner(panel, T.Radius); stroke(panel, T.Stroke, 1, 0)
		new("TextLabel", { BackgroundTransparency=1, Position=UDim2.new(0,14,0,11), Size=UDim2.new(1,-50,0,18), Font=T.FontBold, Text="Configuration", TextColor3=T.Text, TextSize=14, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=62, Parent=panel })
		local x = new("TextButton", { BackgroundTransparency=1, Position=UDim2.new(1,-32,0,9), Size=UDim2.new(0,22,0,22), Font=T.FontBold, Text="\u{2715}", TextColor3=T.Muted, TextSize=14, ZIndex=62, Parent=panel })
		x.MouseButton1Click:Connect(function() tween(ov, E_FAST, { BackgroundTransparency=1 }); task.wait(0.13); ov:Destroy(); configOverlay=nil end)
		local list = new("ScrollingFrame", { BackgroundTransparency=1, BorderSizePixel=0, Position=UDim2.new(0,12,0,40), Size=UDim2.new(1,-24,1,-52), ScrollBarThickness=0, ScrollBarImageColor3=Window._accent, CanvasSize=UDim2.new(), AutomaticCanvasSize=Enum.AutomaticSize.Y, ZIndex=62, Parent=panel })
		new("UIListLayout", { SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,3), Parent=list })
		local cfg = Window:GetConfig(); local keys = {}
		for k in pairs(cfg) do table.insert(keys, k) end
		table.sort(keys)
		if #keys == 0 then new("TextLabel", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,28), Font=T.Font, Text="(vide)", TextColor3=T.Muted, TextSize=12, ZIndex=62, Parent=list }) end
		for _, k in ipairs(keys) do
			local v = cfg[k]
			local disp = (type(v)=="table") and ("{"..table.concat(v, ", ").."}") or tostring(v)
			local rf = new("Frame", { BackgroundColor3=T.Group, BorderSizePixel=0, Size=UDim2.new(1,0,0,28), ZIndex=62, Parent=list })
			corner(rf, T.RadiusSm)
			new("TextLabel", { BackgroundTransparency=1, Position=UDim2.new(0,10,0,0), Size=UDim2.new(0.5,-12,1,0), Font=T.FontMed, Text=k, TextColor3=T.Text, TextSize=12, TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd, ZIndex=62, Parent=rf })
			new("TextLabel", { BackgroundTransparency=1, Position=UDim2.new(0.5,0,0,0), Size=UDim2.new(0.5,-12,1,0), Font=T.Font, Text=disp, TextColor3=Window._accent, TextSize=12, TextXAlignment=Enum.TextXAlignment.Right, TextTruncate=Enum.TextTruncate.AtEnd, ZIndex=62, Parent=rf })
		end
		panel.Size = UDim2.fromOffset(306,324); tween(panel, E_POP, { Size=UDim2.fromOffset(340,360) })
	end
	local tooltip = new("TextLabel", { BackgroundColor3=T.Top, BorderSizePixel=0, Size=UDim2.new(0,0,0,24), AutomaticSize=Enum.AutomaticSize.X, Font=T.Font, Text="", TextColor3=T.Warn, TextSize=11, Visible=false, ZIndex=70, TextXAlignment=Enum.TextXAlignment.Center, Parent=gui })
	corner(tooltip, 4); stroke(tooltip, T.Warn, 1, 0.5); pad(tooltip, 0, 0, 8, 8)
	local function attachTooltip(host, text)
		host.MouseEnter:Connect(function() tooltip.Text=text; tooltip.Visible=true end)
		host.MouseMoved:Connect(function() local m = UserInputService:GetMouseLocation(); tooltip.Position = UDim2.fromOffset(m.X+12, m.Y-6) end)
		host.MouseLeave:Connect(function() tooltip.Visible=false end)
	end

	local activeCategory = nil
	function Window:Category(name, catIcon)
		local cat = { Name=name, _groups={} }
		local tab = new("TextButton", { BackgroundColor3=T.Group, BackgroundTransparency=1, BorderSizePixel=0, Size=UDim2.new(1,0,0,30), Font=T.FontMed, Text="", TextColor3=T.SubText, TextSize=12, AutoButtonColor=false, ZIndex=3, Parent=sideList })
		corner(tab, T.RadiusSm)
		local ind = new("Frame", { BackgroundColor3=Color3.new(1,1,1), BorderSizePixel=0, AnchorPoint=Vector2.new(0,0.5), Position=UDim2.new(0,0,0.5,0), Size=UDim2.new(0,2,0,0), Parent=tab }); corner(ind, 1); accentGrad(ind)
		local indGlow = new("ImageLabel", { Name="AGlow", BackgroundTransparency=1, AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.new(0,1,0.5,0), Size=UDim2.new(0,26,0,26), Image=SHADOW_IMG, ImageColor3=aLo, ImageTransparency=1, ScaleType=Enum.ScaleType.Slice, SliceCenter=Rect.new(49,49,450,450), ZIndex=2, Parent=tab })
		table.insert(Window._recolor, function() indGlow.ImageColor3 = Window._accent end)
		local tabLabel = new("TextLabel", { BackgroundTransparency=1, Position=UDim2.new(0, catIcon and 32 or 11, 0, 0), Size=UDim2.new(1, catIcon and -38 or -14, 1, 0), Font=T.FontMed, Text=name, TextColor3=T.SubText, TextSize=12, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=3, Parent=tab })
		skinTag(tab, "group")
		local tabIco
		if catIcon then tabIco = new("ImageLabel", { BackgroundTransparency=1, Position=UDim2.new(0,9,0.5,-8), Size=UDim2.new(0,16,0,16), Image=catIcon, ImageColor3=T.SubText, ZIndex=3, Parent=tab }) end
		local page = new("Frame", { Name=name, BackgroundTransparency=1, Position=UDim2.new(0,10,0,colTop), Size=UDim2.new(1,-20,1,-colTop-8), Visible=false, Parent=content })
		local leftCol = new("ScrollingFrame", { Name="Left", BackgroundTransparency=1, BorderSizePixel=0, Position=UDim2.new(0,0,0,0), Size=UDim2.new(0.5,-5,1,0), ScrollBarThickness=0, CanvasSize=UDim2.new(), AutomaticCanvasSize=Enum.AutomaticSize.Y, Parent=page })
		new("UIListLayout", { SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,10), Parent=leftCol })
		new("UIPadding", { PaddingBottom=UDim.new(0,8), Parent=leftCol })
		local rightCol = new("ScrollingFrame", { Name="Right", BackgroundTransparency=1, BorderSizePixel=0, Position=UDim2.new(0.5,5,0,0), Size=UDim2.new(0.5,-5,1,0), ScrollBarThickness=0, CanvasSize=UDim2.new(), AutomaticCanvasSize=Enum.AutomaticSize.Y, Parent=page })
		new("UIListLayout", { SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,10), Parent=rightCol })
		new("UIPadding", { PaddingBottom=UDim.new(0,8), Parent=rightCol })
		for _, col in ipairs({ leftCol, rightCol }) do
			local fade = new("Frame", { BackgroundColor3=T.Base, BorderSizePixel=0, AnchorPoint=Vector2.new(0.5,1), Position=UDim2.new(0.5,0,1,0), Size=UDim2.new(1,4,0,26), BackgroundTransparency=1, ZIndex=8, Parent=page })
			fade.Position = (col == leftCol) and UDim2.new(0.25,0,1,0) or UDim2.new(0.75,0,1,0)
			fade.Size = UDim2.new(0.5,-5,0,26)
			new("UIGradient", { Rotation=90, Transparency=NumberSequence.new({ NumberSequenceKeypoint.new(0,1), NumberSequenceKeypoint.new(1,0.25) }), Parent=fade })
			skinTag(fade, "base")
			local arrowHint = new("Frame", { BackgroundColor3=T.Muted, BorderSizePixel=0, AnchorPoint=Vector2.new(0.5,1), Position=UDim2.new(0.5,0,1,-6), Size=UDim2.new(0,16,0,2), BackgroundTransparency=1, ZIndex=9, Parent=fade })
			corner(arrowHint, 1)
			task.spawn(function()
				while alive() do
					local more = (col.AbsoluteCanvasSize.Y - col.AbsoluteSize.Y - col.CanvasPosition.Y) > 8
					local want = (more and page.Visible) and 0 or 1
					if math.abs(fade.BackgroundTransparency - want) > 0.05 then
						tween(fade, E_FAST, { BackgroundTransparency = want })
						tween(arrowHint, E_FAST, { BackgroundTransparency = want == 0 and 0.35 or 1 })
					end
					task.wait(0.25)
				end
			end)
		end
		cat.Page=page; cat.Tab=tab
		local sideCount = { left=0, right=0 }
		local function select()
			if activeCategory == cat then return end
			if activeCategory then
				activeCategory.Page.Visible=false
				tween(activeCategory.Tab, E_FAST, { BackgroundTransparency=1 })
				activeCategory._label.Name="Lbl"; tween(activeCategory._label, E_FAST, { TextColor3=T.SubText })
				tween(activeCategory._ind, E_FAST, { Size=UDim2.new(0,2,0,0) }); if activeCategory._glow then tween(activeCategory._glow, E_FAST, { ImageTransparency=1 }) end
				if activeCategory._ico then tween(activeCategory._ico, E_FAST, { ImageColor3=T.SubText }) end
			end
			if Window._closeSub then Window._closeSub() end
			activeCategory = cat; page.Visible=true
			page.Position=UDim2.new(0,10,0,colTop)
			leftCol.Position=UDim2.new(0,-16,0,0); rightCol.Position=UDim2.new(0.5,-11,0,0); tween(leftCol, E_SMOO, { Position=UDim2.new(0,0,0,0) }); tween(rightCol, E_SMOO, { Position=UDim2.new(0.5,5,0,0) }); for _i,_g in ipairs(cat._groups) do local _f=_g.frame; _f.Position=UDim2.new(0,-38,0,0); task.delay(0.085*_i*SPEED.mul, function() if activeCategory==cat then tween(_f, E_SMOO, { Position=UDim2.new(0,0,0,0) }) end end); task.delay(0.085*_i*SPEED.mul+0.9, function() _f.Position=UDim2.new(0,0,0,0) end) end
			tween(tab, E_FAST, { BackgroundColor3=T.Group, BackgroundTransparency=0 })
			tabLabel.Name="AF"; tween(tabLabel, E_FAST, { TextColor3=Window._accent })
			ind.Size = UDim2.new(0,2,0,2); tween(ind, TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size=UDim2.new(0,2,0,14) }); tween(indGlow, E_SMOO, { ImageTransparency=0.55 })
			if tabIco then tween(tabIco, E_FAST, { ImageColor3=Window._accent }) end
			if crumb then crumb.Text = "\u{203A} "..name end
			Window.OnCategoryChanged:Fire(name)
			if searchBox then searchBox.Text=""; cat:_filter("") end
		end
		cat._label=tabLabel; cat._ind=ind; cat._ico=tabIco; cat._glow=indGlow; cat.Select=select
		table.insert(Window._recolor, function() if activeCategory==cat then tabLabel.TextColor3=Window._accent; if tabIco then tabIco.ImageColor3=Window._accent end end end)
		tab.MouseButton1Click:Connect(select)
		tab.MouseEnter:Connect(function() if activeCategory ~= cat then tween(tabLabel, E_FAST, { TextColor3=T.Text, Position=UDim2.new(0,(catIcon and 32 or 11)+3,0,0) }); tween(tab, E_FAST, { BackgroundTransparency=0.85 }) end end)
		tab.MouseLeave:Connect(function() if activeCategory ~= cat then tween(tabLabel, E_FAST, { TextColor3=T.SubText, Position=UDim2.new(0,catIcon and 32 or 11,0,0) }); tween(tab, E_FAST, { BackgroundTransparency=1 }) end end)
		table.insert(Window.Categories, cat)
		if #Window.Categories == 1 then task.defer(select) end
		function cat:_filter(q)
			q = string.lower(q or ""); local total = 0
			for _, g in ipairs(cat._groups) do
				if q ~= "" and g.expand then g.expand() end
				local shown = 0
				for _, it in ipairs(g.items) do
					local hay = it.title and string.lower(it.title) or ""
					if it.box then hay = hay .. " " .. string.lower(it.box) end
					if it.el and it.el.Keywords then hay = hay .. " " .. string.lower(tostring(it.el.Keywords)) end
					local vis = (q=="") or (string.find(hay, q, 1, true) ~= nil)
					it.frame.Visible = vis and true or false
					if vis then shown += 1 end
				end
				g.frame.Visible = (q=="") or (shown>0)
				total = total + shown
			end
			if Window._searchCount then Window._searchCount.Text = (q=="") and "" or (total.." found") end
			-- redistribute visible groupboxes across both columns so results never pile up on one side
			local vis = {}
			for _, g in ipairs(cat._groups) do if g.frame.Visible then table.insert(vis, g) end end
			if q ~= "" then
				for idx, g in ipairs(vis) do
					local want = (idx % 2 == 1) and leftCol or rightCol
					if g.frame.Parent ~= want then g.frame.Parent = want end
					g.frame.LayoutOrder = idx
				end
			else
				for _, g in ipairs(cat._groups) do
					if g.frame.Parent ~= g.homeCol then g.frame.Parent = g.homeCol end
					g.frame.LayoutOrder = g.homeOrder or 0
				end
			end
		end
		function cat:Groupbox(title, sideName)
			if sideName ~= "left" and sideName ~= "right" then sideName = (sideCount.left <= sideCount.right) and "left" or "right" end
			sideCount[sideName] += 1
			-- keep columns balanced: a lone box always starts on the left
			if sideCount.left == 0 and sideName == "right" then sideName = "left"; sideCount.left, sideCount.right = 1, 0 end
			local col = (sideName=="left") and leftCol or rightCol
			local box = new("Frame", { Name=title, BackgroundColor3=T.Group, BorderSizePixel=0, Size=UDim2.new(1,0,0,40), AutomaticSize=Enum.AutomaticSize.Y, Parent=col })
			corner(box, T.RadiusSm); bgGrad(box, Color3.fromRGB(32,32,40), Color3.fromRGB(22,22,28)); skinTag(box, "group")
			pad(box, 11, 12, 12, 12)
			new("UIListLayout", { SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,5), Parent=box })
			local head = new("Frame", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,16), LayoutOrder=-1, Parent=box })
			local d0 = new("Frame", { BackgroundColor3=Color3.new(1,1,1), BorderSizePixel=0, AnchorPoint=Vector2.new(0,0.5), Position=UDim2.new(0,0,0.5,0), Size=UDim2.new(0,5,0,5), Parent=head }); corner(d0, 2); accentGrad(d0)
			skinTag(new("TextLabel", { BackgroundTransparency=1, Position=UDim2.new(0,11,0,0), Size=UDim2.new(1,-24,1,0), Font=T.FontBold, Text=title, TextColor3=Color3.fromRGB(205,205,214), TextSize=12, TextXAlignment=Enum.TextXAlignment.Left, Parent=head }), "text")
			local chev = new("Frame", { BackgroundTransparency=1, AnchorPoint=Vector2.new(1,0.5), Position=UDim2.new(1,0,0.5,0), Size=UDim2.new(0,10,0,10), Parent=head })
			for _, ar in ipairs({45, -45}) do
				local bl = new("Frame", { BackgroundColor3=T.Muted, BorderSizePixel=0, AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.new(ar>0 and 0.29 or 0.71, 0, 0.42, 0), Size=UDim2.new(0,6.5,0,1.6), Rotation=ar, Parent=chev }); corner(bl,1)
				table.insert(Window._recolor, function() bl.BackgroundColor3 = T.Muted end)
			end
			box.ClipsDescendants = true
			local collapsed = false
			local headBtn = new("TextButton", { BackgroundTransparency=1, AnchorPoint=Vector2.new(1,0.5), Position=UDim2.new(1,2,0.5,0), Size=UDim2.new(0,22,0,20), Text="", ZIndex=6, Parent=head })
			headBtn.MouseEnter:Connect(function() tween(chev, E_FAST, { Rotation = collapsed and -90 or 0 }) end)
			local expandFn = function()
				if collapsed then
					collapsed = false
					for _, c in ipairs(box:GetChildren()) do if c:IsA("GuiObject") then c.Visible = true end end
					box.AutomaticSize = Enum.AutomaticSize.Y
					tween(chev, E_FAST, { Rotation=0 })
				end
			end
			local function setBodyVisible(v)
				for _, c in ipairs(box:GetChildren()) do
					if c:IsA("GuiObject") and c ~= head then c.Visible = v end
				end
			end
			headBtn.MouseButton1Click:Connect(function()
				collapsed = not collapsed
				if collapsed then
					local h = box.AbsoluteSize.Y
					box.AutomaticSize = Enum.AutomaticSize.None
					box.Size = UDim2.new(1,0,0,h)
					tween(box, E_SMOO, { Size=UDim2.new(1,0,0,38) })
					tween(chev, E_SMOO, { Rotation=-90 })
					task.delay(0.2 * SPEED.mul, function() if collapsed then setBodyVisible(false) end end)
				else
					setBodyVisible(true)
					box.AutomaticSize = Enum.AutomaticSize.Y
					tween(chev, E_SMOO, { Rotation=0 })
				end
			end)

			local group = { frame=box, items={}, expand=expandFn, toggles={}, homeCol=col, homeOrder=(sideCount.left + sideCount.right) }
			table.insert(cat._groups, group)
			local curParent = box
			local function reg(frame, ttl, el)
				if curParent == box then table.insert(group.items, { frame=frame, title=ttl, box=title, el=el }) end
				if ttl and el then table.insert(Window._ctxTargets, { frame=frame, title=ttl, el=el }) end
			end
			-- Config keys default to the element's Name. Two elements may legitimately share
			-- a name (a per-tab "Enable", say), and both would then write to the same
			-- Window.Flags / Window.Elements slot, so only the last one declared survived a
			-- save/load. A name that is already taken is qualified with its
			-- "Category > Groupbox" path instead, then a #n suffix if that collides too.
			-- Pass Flag="my_key" in the options table to pin a key that stays put when the
			-- element is renamed or moved to another tab.
			local function mkFlag(text, opts)
				local explicit = (type(opts) == "table") and opts.Flag or nil
				if type(explicit) == "string" and explicit ~= "" then
					if Window._flagTaken[explicit] then
						warn(("[Azurite] Flag %q is declared twice (%q) - the earlier element loses its config slot"):format(explicit, tostring(text)))
					end
					Window._flagTaken[explicit] = true
					return explicit
				end
				local base = tostring(text)
				if not Window._flagTaken[base] then
					Window._flagTaken[base] = true
					return base
				end
				local qual = tostring(cat.Name) .. " > " .. tostring(title) .. " > " .. base
				local key, n = qual, 1
				while Window._flagTaken[key] do n += 1; key = qual .. " #" .. n end
				Window._flagTaken[key] = true
				warn(("[Azurite] %q is used by more than one element - this one saves under %q. Set Flag=\"...\" for a stable config key."):format(base, key))
				return key
			end
			local boxAPI = {}
			local function line(h) return new("Frame", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,h or 22), Parent=curParent }) end
			local function lbl(parent, text, x, w) local l = new("TextLabel", { BackgroundTransparency=1, Position=UDim2.new(0,x or 0,0,0), Size=UDim2.new(w or 1, w and 0 or 0, 1, 0), Font=T.Font, Text=text, TextColor3=T.SubText, TextSize=12, TextXAlignment=Enum.TextXAlignment.Left, Parent=parent }); skinTag(l, "sub"); return l end
			function boxAPI:Label(text)
				local f = line(18); local l = lbl(f, text); l.TextColor3=T.Muted; l.Size=UDim2.new(1,0,1,0)
				reg(f, text); return { Set=function(_, v) l.Text=tostring(v) end, Instance=f }
			end
			function boxAPI:Section(title)
				local f = new("Frame", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,20), Parent=curParent })
				local dot = new("Frame", { BackgroundColor3=Color3.new(1,1,1), BorderSizePixel=0, AnchorPoint=Vector2.new(0,0.5), Position=UDim2.new(0,0,0.62,0), Size=UDim2.new(0,4,0,4), Parent=f })
				corner(dot,2); accentGrad(dot)
				local l = new("TextLabel", { BackgroundTransparency=1, Position=UDim2.new(0,10,0,0), Size=UDim2.new(1,-10,1,0), Font=T.FontBold, Text=tostring(title), TextColor3=T.Muted, TextSize=10, TextXAlignment=Enum.TextXAlignment.Left, TextYAlignment=Enum.TextYAlignment.Bottom, Parent=f })
				skinTag(l, "muted")
				reg(f, title)
				return { Instance=f, Set=function(_, v) l.Text = tostring(v) end }
			end
			function boxAPI:Progress(text, startValue)
				local f = line(30)
				local l = lbl(f, text, 0); l.Size = UDim2.new(1,-50,0,15)
				local val = new("TextLabel", { Name="AF", BackgroundTransparency=1, AnchorPoint=Vector2.new(1,0), Position=UDim2.new(1,0,0,0), Size=UDim2.new(0,50,0,15), Font=T.FontMed, Text="0%", TextColor3=aLo, TextSize=12, TextXAlignment=Enum.TextXAlignment.Right, Parent=f })
				local track = new("Frame", { BackgroundColor3=T.Off, BorderSizePixel=0, Position=UDim2.new(0,0,0,21), Size=UDim2.new(1,0,0,4), Parent=f })
				corner(track, 2); skinTag(track, "off")
				local fill = new("Frame", { BackgroundColor3=Color3.new(1,1,1), BorderSizePixel=0, Size=UDim2.new(0,0,1,0), Parent=track }); corner(fill, 2); accentGrad(fill, 0)
				local element = { Value = 0, Flag = nil, Instance = f }
				function element:Set(v)
					v = math.clamp(tonumber(v) or 0, 0, 1)
					element.Value = v
					val.Text = math.floor(v*100 + 0.5) .. "%"
					tween(fill, E_FAST, { Size = UDim2.new(v, 0, 1, 0) })
					return element
				end
				function element:Get() return element.Value end
				function element:SetText(t) l.Text = tostring(t); return element end
				element:Set(startValue or 0)
				reg(f, text)
				return element
			end
			function boxAPI:Stat(text, getter, interval)
				local f = line(20)
				local l = lbl(f, text, 0); l.Size = UDim2.new(1,-90,1,0)
				local val = new("TextLabel", { Name="AF", BackgroundTransparency=1, AnchorPoint=Vector2.new(1,0.5), Position=UDim2.new(1,0,0.5,0), Size=UDim2.new(0,90,1,0), Font=T.FontMed, Text="-", TextColor3=aLo, TextSize=12, TextXAlignment=Enum.TextXAlignment.Right, TextTruncate=Enum.TextTruncate.AtEnd, Parent=f })
				local element = { Instance = f }
				function element:Set(v) val.Text = tostring(v); return element end
				if type(getter) == "function" then
					task.spawn(function()
						while alive() do
							local ok2, v = pcall(getter)
							if ok2 and v ~= nil then val.Text = tostring(v) end
							task.wait(type(interval) == "number" and interval > 0 and interval or 1)
						end
					end)
				elseif getter ~= nil then val.Text = tostring(getter) end
				reg(f, text)
				return element
			end
			function boxAPI:Divider()
				local f = new("Frame", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,7), Parent=curParent })
				new("Frame", { BackgroundColor3=T.StrokeSub, BorderSizePixel=0, AnchorPoint=Vector2.new(0,0.5), Position=UDim2.new(0,0,0.5,0), Size=UDim2.new(1,0,0,1), Parent=f })
				reg(f, nil); return { Instance=f }
			end
			function boxAPI:Button(text, cb)
				cb = cb or function() end
				local f = new("Frame", { BackgroundColor3=T.Element, BorderSizePixel=0, Size=UDim2.new(1,0,0,24), Parent=curParent })
				corner(f, T.RadiusXs); skinTag(f, "element")
				skinTag(new("TextLabel", { BackgroundTransparency=1, Size=UDim2.new(1,0,1,0), Font=T.FontMed, Text=text, TextColor3=T.SubText, TextSize=12, Parent=f }), "sub")
				local b = new("TextButton", { BackgroundTransparency=1, Size=UDim2.new(1,0,1,0), Text="", Parent=f })
				b.MouseEnter:Connect(function() tween(f, E_FAST, { BackgroundColor3=T.ElementHov }) end)
				b.MouseLeave:Connect(function() tween(f, E_FAST, { BackgroundColor3=T.Element }) end)
				f.ClipsDescendants = true
				local bscale = new("UIScale", { Scale=1, Parent=f }); b.MouseButton1Click:Connect(function()
					local m = UserInputService:GetMouseLocation()
					local rx = m.X - f.AbsolutePosition.X
					local rip = new("Frame", { BackgroundColor3=Window._accent, BackgroundTransparency=0.55, BorderSizePixel=0, AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.new(0,rx,0.5,0), Size=UDim2.new(0,0,0,0), ZIndex=2, Parent=f }); corner(rip, 40)
					tween(rip, TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Size=UDim2.new(0,f.AbsoluteSize.X*2.2,0,f.AbsoluteSize.X*2.2), BackgroundTransparency=1 })
					task.delay(0.5, function() rip:Destroy() end)
					bscale.Scale=0.96; tween(bscale, E_POP, {Scale=1}); tween(f, TweenInfo.new(0.07), { BackgroundColor3=Window._accent }); task.delay(0.08, function() tween(f, E_FAST, { BackgroundColor3=T.Element }) end); task.spawn(cb) end)
				reg(f, text); return { Instance=f, Fire=function() task.spawn(cb) end }
			end
			function boxAPI:Toggle(text, default, cb, opts)
				if type(default) == "function" then cb, default = default, false end
				if type(cb) == "table" then opts, cb = cb, nil end
				cb = cb or function() end; opts = opts or {}
				local flag = mkFlag(text, opts)
				local f = line(22)
				local checkFrame = new("Frame", { BackgroundColor3=T.Element, BorderSizePixel=0, Position=UDim2.new(0,0,0.5,-8), Size=UDim2.new(0,16,0,16), Parent=f })
				corner(checkFrame, T.RadiusXs); skinTag(checkFrame, "element"); local cg = accentGrad(checkFrame); cg.Enabled = false; local cscale = new("UIScale", { Scale=1, Parent=checkFrame })
				local tick = new("TextLabel", { BackgroundTransparency=1, Size=UDim2.new(1,0,1,0), Font=T.FontBold, Text="\u{2713}", TextColor3=Color3.new(1,1,1), TextSize=12, TextTransparency=1, Parent=checkFrame })
				local l = lbl(f, text, 24); l.Size=UDim2.new(1,-24,1,0); l.TextColor3=T.SubText
				if opts.Warning then
					l.Size = UDim2.new(1,-44,1,0)
					local w = new("TextButton", { BackgroundTransparency=1, AnchorPoint=Vector2.new(1,0.5), Position=UDim2.new(1,0,0.5,0), Size=UDim2.new(0,16,0,16), Font=T.FontBold, Text="\u{26A0}", TextColor3=T.Warn, TextSize=12, Parent=f })
					attachTooltip(w, opts.Warning)
				end
				local element = { Value=false, Flag=flag }
				function element:Set(v, skip)
					v = not not v; element.Value=v; Window.Flags[flag]=v
					cg.Enabled = v; tween(checkFrame, E_FAST, { BackgroundColor3 = v and Color3.new(1,1,1) or T.Element }); if v then
						cscale.Scale=0.45; tween(cscale, TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale=1})
						tick.TextTransparency=1; tick.Rotation=-25; tween(tick, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Rotation=0})
						local pulse = new("Frame", { BackgroundColor3=Window._accent, BackgroundTransparency=0.5, BorderSizePixel=0, AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.fromScale(0.5,0.5), Size=UDim2.new(0,16,0,16), ZIndex=0, Parent=checkFrame }); corner(pulse, 6)
						tween(pulse, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Size=UDim2.new(0,34,0,34), BackgroundTransparency=1 })
						task.delay(0.55, function() pulse:Destroy() end)
					else cscale.Scale=1.12; tween(cscale, E_SNAP, {Scale=1}) end
					
					tween(tick, E_FAST, { TextTransparency = v and 0 or 1 })
					tween(l, E_FAST, { TextColor3 = v and T.Text or T.SubText })
					if element._fireHooks then element._fireHooks(v) end
					if not skip then
						if opts.Warning and v then Window:Notify(opts.Warning, { Title=text, Type="warning", Duration=3 }) end
						task.spawn(cb, v)
					end
				end
				function element:Get() return element.Value end
				function element:Toggle() element:Set(not element.Value) end
				stateHelpers(element, function() return element.Value end)
				local subContent, kbEl
				if opts.Keybind == nil and opts.Bind ~= false then opts.Keybind = true end   -- native bind on every toggle
				if opts.Keybind ~= nil or opts.Sub then
					l.Size = UDim2.new(1, opts.Warning and -62 or -44, 1, 0)
					local arrow = new("TextButton", { BackgroundTransparency=1, AnchorPoint=Vector2.new(1,0.5), Position=UDim2.new(1, opts.Warning and -20 or 0, 0.5, 0), Size=UDim2.new(0,18,0,18), Text="", ZIndex=4, Parent=f })
					local dots = {}
					for di = 0, 2 do
						local dot = new("Frame", { BackgroundColor3=T.Muted, BorderSizePixel=0, AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.new(0.5, 0, 0.5, (di-1)*5), Size=UDim2.new(0,3,0,3), Parent=arrow })
						corner(dot, 2); table.insert(dots, dot)
						table.insert(Window._recolor, function() dot.BackgroundColor3 = T.Muted end)
					end
					arrow.MouseEnter:Connect(function() for _, d in ipairs(dots) do tween(d, E_FAST, { BackgroundColor3 = Window._accent, Size = UDim2.new(0,4,0,4) }) end end)
					arrow.MouseLeave:Connect(function() for _, d in ipairs(dots) do tween(d, E_FAST, { BackgroundColor3 = T.Muted, Size = UDim2.new(0,3,0,3) }) end end)
					subContent = new("Frame", { Name=text.."Sub", BackgroundTransparency=1, Size=UDim2.new(1,0,0,0), AutomaticSize=Enum.AutomaticSize.Y, Visible=false, ZIndex=77, Parent=nil })
					new("UIListLayout", { SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,5), Parent=subContent })
					skinTag(new("TextLabel", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,15), Font=T.FontBold, Text=text, TextColor3=T.Text, TextSize=12, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=77, Parent=subContent }), "text")
					if opts.Keybind ~= nil and opts.Keybind ~= false then
						local prev = curParent; curParent = subContent
						kbEl = boxAPI:Keybind(opts.KeybindName or (text .. " bind"), (typeof(opts.Keybind)=="EnumItem") and opts.Keybind or nil, nil, { Mode = opts.KeybindMode or "Toggle", Modes = opts.KeybindModes or { "Toggle", "Hold" }, AskMode = (opts.KeybindModes ~= nil) })
						kbEl._bound = element
						element.Bind = kbEl
						curParent = prev
					end
					if opts.Sub then
						local prev = curParent; curParent = subContent
						local before = {}
						for k2, v2 in pairs(Window.Elements) do before[k2] = v2 end
						pcall(opts.Sub, boxAPI)
						curParent = prev
						if not opts.SubAlwaysActive then
							for k2, v2 in pairs(Window.Elements) do
								if before[k2] == nil and type(v2) == "table" and v2.DependsOn and v2 ~= kbEl then
									pcall(function() v2:DependsOn(element) end)
								end
							end
						end
					end

					arrow.MouseButton1Click:Connect(function() if Window._subPop and Window._subPop.Visible and Window._subOwner == subContent then Window._closeSub() else Window:_openSub(subContent, f) end end)
				end
				local btn = new("TextButton", { BackgroundTransparency=1, Size=UDim2.new(1, (subContent and (opts.Warning and -62 or -44)) or 0, 1, 0), Text="", Parent=f })
				btn.MouseEnter:Connect(function() tween(f, E_FAST, { BackgroundColor3=Color3.new(1,1,1), BackgroundTransparency=0.94 }); tween(l, E_FAST, { Position=UDim2.new(0,26,0,0) }) end); btn.MouseLeave:Connect(function() tween(f, E_FAST, { BackgroundTransparency=1 }); tween(l, E_FAST, { Position=UDim2.new(0,24,0,0) }) end); btn.MouseButton1Click:Connect(function() element:Toggle() end)
				element:Set(default, true); Window.Elements[flag]=element

				element.Instance = f
				function element:SetVisible(v) f.Visible = v and true or false end
				function element:SetLocked(v)
					element.Locked = v and true or false
					btn.Active = not element.Locked
					tween(l, E_FAST, { TextTransparency = element.Locked and 0.55 or 0 })
					tween(checkFrame, E_FAST, { BackgroundTransparency = element.Locked and 0.5 or 0 })
				end
				reg(f, text, element); return element
			end
			function boxAPI:Slider(text, default, min, max, cb, sopts)
				if type(default) == "function" then cb, default = default, nil end
				if type(min) == "function" then cb, min = min, nil end
				if type(max) == "function" then cb, max = max, nil end
				if type(default) == "table" then sopts, default = default, nil end
				if type(min) == "table" then sopts, min = min, nil end
				if type(max) == "table" then sopts, max = max, nil end
				if type(cb) == "table" then sopts, cb = cb, nil end
				sopts = sopts or {}
				cb = cb or function() end; min, max = min or 0, max or 100
				local flag = mkFlag(text, sopts)
				local f = line(30)
				local l = lbl(f, text, 0); l.Size=UDim2.new(1,-50,0,15)
				local val = new("TextLabel", { Name="AF", BackgroundTransparency=1, AnchorPoint=Vector2.new(1,0), Position=UDim2.new(1,0,0,0), Size=UDim2.new(0,50,0,15), Font=T.FontMed, Text="0", TextColor3=aLo, TextSize=12, TextXAlignment=Enum.TextXAlignment.Right, Parent=f })
				local track = new("Frame", { BackgroundColor3=T.Off, BorderSizePixel=0, Position=UDim2.new(0,0,0,20), Size=UDim2.new(1,0,0,4), Parent=f })
				corner(track, 2); skinTag(track, "off")
				local fill = new("Frame", { BackgroundColor3=Color3.new(1,1,1), BorderSizePixel=0, Size=UDim2.new(0,0,1,0), Parent=track }); corner(fill, 2); accentGrad(fill, 0)
				local knob = new("Frame", { BackgroundColor3=Color3.new(1,1,1), BorderSizePixel=0, AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.new(1,0,0.5,0), Size=UDim2.new(0,9,0,9), ZIndex=2, Parent=fill }); corner(knob, 5)
				local suffix = sopts.Suffix or ""
				local element = { Value=min, Flag=flag }
				element.Step     = sopts.Step                                   -- nil = free, 1 = ints, 5 = fives...
				element.Decimals = sopts.Decimals                               -- nil = auto
				element.Format   = sopts.Format                                 -- "int" | "float" | "percent" | function(v)
				if element.Format == "int" and element.Step == nil then element.Step = 1 end
				if element.Format == "percent" and suffix == "" then suffix = "%" end
				function element:SetSuffix(s) suffix = s or ""; element:Set(element.Value, true); return element end
				function element:SetStep(st) element.Step = st; return element end
				function element:SetFormat(f) element.Format = f; element:Set(element.Value, true); return element end
				local function shape(v)
					if element.Step and element.Step > 0 then v = math.floor((v - min)/element.Step + 0.5)*element.Step + min end
					v = math.clamp(v, min, max)
					local dec = element.Decimals
					if dec == nil then
						if element.Format == "int" then dec = 0
						elseif element.Step and element.Step >= 1 then dec = 0
						elseif element.Step and element.Step > 0 then
							dec = (element.Step >= 0.1) and 1 or 2
						elseif math.floor(min) == min and math.floor(max) == max and (max - min) >= 4 then dec = 0
						else dec = 2 end
					end
					local mult = 10 ^ dec
					return math.floor(v * mult + 0.5) / mult, dec
				end
				local function display(v, dec)
					if type(element.Format) == "function" then return tostring(element.Format(v)) end
					if element.Format == "percent" then return string.format("%d", math.floor(v + 0.5)) .. suffix end
					if dec <= 0 then return string.format("%d", v) .. suffix end
					return string.format("%." .. dec .. "f", v) .. suffix
				end
				function element:Set(v, skip)
					local dec
					v, dec = shape(tonumber(v) or min)
					element.Value=v; Window.Flags[flag]=v; val.Text=display(v, dec)
					local a = (max-min)==0 and 0 or (v-min)/(max-min)
					tween(fill, TweenInfo.new(0.16, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Size=UDim2.new(a,0,1,0) })
					if not skip then val.TextSize = 13; tween(val, E_SNAP, { TextSize = 12 }) end
					if not skip then task.spawn(cb, v) end
				end
				function element:Get() return element.Value end
				local drag = false
				local function upd(i)
					local rel = (i.Position.X - track.AbsolutePosition.X)/track.AbsoluteSize.X
					local target = min + math.clamp(rel,0,1)*(max-min)
					if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then target = element.Value + (target-element.Value)*0.12 end
					element:Set(target)
				end
				local knobGlow = new("Frame", { BackgroundColor3=Color3.new(1,1,1), BackgroundTransparency=1, BorderSizePixel=0, AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.fromScale(0.5,0.5), Size=UDim2.new(0,20,0,20), ZIndex=1, Parent=knob }); corner(knobGlow, 10)
				track.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then drag=true; tween(knob, E_SNAP, {Size=UDim2.new(0,14,0,14)}); tween(knobGlow, E_FAST, {BackgroundTransparency=0.75}); upd(i) end end)
				local hit = new("TextButton", { BackgroundTransparency=1, Position=UDim2.new(0,0,0,16), Size=UDim2.new(1,0,0,12), Text="", Parent=f })
				hit.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then drag=true; tween(knob, E_FAST, {Size=UDim2.new(0,13,0,13)}); upd(i) end end)
				UIS_.InputChanged:Connect(function(i) if drag and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then upd(i) end end)
				UIS_.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then if drag and element._fireCommit then element._fireCommit(element.Value) end drag=false; tween(knob, E_SNAP, {Size=UDim2.new(0,9,0,9)}); tween(knobGlow, E_FAST, {BackgroundTransparency=1}) end end)
				element:Set(default or min, true); Window.Elements[flag]=element; element.Instance=f
				do
					local RunSvc2 = game:GetService("RunService")
					local function every(signal, fn)
						if not Window._normFn(fn, "Slider:OnRender/OnStep/OnPhysics") then return element end
						local c = signal:Connect(function(...) local ok2, err = pcall(fn, element.Value, ...) if not ok2 then warn("[Azurite]", err) end end)
						table.insert(_conns, c); return element
					end
					function element:OnRender(fn)  return every(RunSvc2.RenderStepped, fn) end
					function element:OnStep(fn)    return every(RunSvc2.Heartbeat, fn) end
					function element:OnPhysics(fn) return every(RunSvc2.Stepped, fn) end
					function element:OnLoop(fn, interval)
						local f2, iv = Window._normLoop(fn, interval, "Slider:OnLoop")
						if not f2 then return element end
						fn, interval = f2, iv
						task.spawn(function()
							while alive() do
								local ok2, err = pcall(fn, element.Value)
								if not ok2 then warn("[Azurite]", err) end
								task.wait(interval)
							end
						end)
						return element
					end
					function element:BindTo(obj, prop)
						element:OnChanged(function(v) pcall(function() obj[prop] = v end) end)
						return element
					end
				end
				reg(f, text, element); return element
			end
			function boxAPI:TextBox(text, placeholder, clearOnFocus, cb, topts)
				if type(placeholder) == "function" then cb, placeholder = placeholder, nil end
				if type(clearOnFocus) == "function" then cb, clearOnFocus = clearOnFocus, nil end
				cb = cb or function() end
				local flag = mkFlag(text, topts)
				local f = line(24)
				local holder = new("Frame", { BackgroundColor3=T.Element, BorderSizePixel=0, Size=UDim2.new(1,0,1,0), Parent=f })
				corner(holder, T.RadiusXs); skinTag(holder, "element")
				local box2 = new("TextBox", { BackgroundTransparency=1, Position=UDim2.new(0,8,0,0), Size=UDim2.new(1,-16,1,0), Font=T.Font, Text="", PlaceholderText=placeholder or "...", PlaceholderColor3=T.Muted, TextColor3=T.Text, TextSize=12, ClearTextOnFocus=clearOnFocus==true, TextXAlignment=Enum.TextXAlignment.Left, Parent=holder })
				local element = { Value="", Flag=flag }
				function element:Set(v, skip) element.Value=tostring(v); Window.Flags[flag]=element.Value; box2.Text=element.Value; if not skip then task.spawn(cb, element.Value) end end
				function element:Get() return element.Value end
				box2.Focused:Connect(function() tween(holder, E_FAST, { BackgroundColor3=T.ElementHov }) end)
				box2.FocusLost:Connect(function(enter) tween(holder, E_FAST, { BackgroundColor3=T.Element }); if enter then element:Set(box2.Text); if element._fireCommit then element._fireCommit(element.Value) end; tween(holder, TweenInfo.new(0.08), { BackgroundColor3=Window._accent }); task.delay(0.1, function() tween(holder, E_FAST, { BackgroundColor3=T.Element }) end) end end)
				Window.Elements[flag]=element; Window.Flags[flag]=""; element.Instance=f
				reg(f, text, element); return element
			end
			local function buildDropdown(text, options, multi, default, cb, dopts)
				if type(default) == "function" then cb, default = default, nil end
				cb = cb or function() end; options = options or {}
				local flag = mkFlag(text, dopts)
				local f = new("Frame", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,40), ClipsDescendants=true, Parent=curParent })
				new("UIListLayout", { SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,4), Parent=f })
				lbl(f, text, 0).Size = UDim2.new(1,0,0,14)
				local head = new("Frame", { BackgroundColor3=T.Element, BorderSizePixel=0, Size=UDim2.new(1,0,0,24), Parent=f })
				corner(head, T.RadiusXs); skinTag(head, "element")
				local sel = new("TextLabel", { BackgroundTransparency=1, Position=UDim2.new(0,8,0,0), Size=UDim2.new(1,-28,1,0), Font=T.Font, Text=multi and "None" or "-", TextColor3=T.SubText, TextSize=12, TextTruncate=Enum.TextTruncate.AtEnd, TextXAlignment=Enum.TextXAlignment.Left, Parent=head })
				local arrow = new("Frame", { BackgroundTransparency=1, AnchorPoint=Vector2.new(1,0.5), Position=UDim2.new(1,-8,0.5,0), Size=UDim2.new(0,10,0,10), Parent=head })
				for _, ar in ipairs({45, -45}) do
					local bl = new("Frame", { BackgroundColor3=T.Muted, BorderSizePixel=0, AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.new(ar>0 and 0.29 or 0.71, 0, 0.42, 0), Size=UDim2.new(0,6.5,0,1.6), Rotation=ar, Parent=arrow }); corner(bl,1)
					table.insert(Window._recolor, function() bl.BackgroundColor3 = T.Muted end)
				end
				local listWrap = new("ScrollingFrame", { BackgroundTransparency=1, BorderSizePixel=0, Size=UDim2.new(1,0,0,0), CanvasSize=UDim2.new(), AutomaticCanvasSize=Enum.AutomaticSize.Y, ScrollBarThickness=2, ScrollBarImageColor3=T.Muted, ScrollBarImageTransparency=0.4, ScrollingDirection=Enum.ScrollingDirection.Y, ClipsDescendants=true, Parent=f })
				local ll = new("UIListLayout", { SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,2), Parent=listWrap })
				local hbtn = new("TextButton", { BackgroundTransparency=1, Size=UDim2.new(1,0,1,0), Text="", ZIndex=3, Parent=head })
				local element = { Value = multi and {} or nil, Flag=flag, Open=false, _opt=options }
				local buttons = {}
				local function refresh() if multi then sel.Text = (#element.Value==0) and "None" or table.concat(element.Value, ", ") else sel.Text = element.Value and tostring(element.Value) or "-" end sel.TextColor3 = ((multi and #element.Value>0) or (not multi and element.Value)) and Window._accent or T.SubText end
				local function heightClosed() return 14 + 4 + 24 end
				local function rebuild()
					for _, b in ipairs(buttons) do b:Destroy() end; buttons = {}
					for _, opt in ipairs(element._opt) do
						local b = new("TextButton", { BackgroundColor3=T.Element, BorderSizePixel=0, Size=UDim2.new(1,0,0,22), Font=T.Font, Text="  "..tostring(opt), TextColor3=T.SubText, TextSize=12, TextXAlignment=Enum.TextXAlignment.Left, AutoButtonColor=false, Parent=listWrap })
						corner(b, T.RadiusXs)
						local function on() if multi then return table.find(element.Value, opt) ~= nil else return element.Value == opt end end
						local function paint() b.TextColor3 = on() and Window._accent or T.SubText; b.BackgroundColor3 = on() and T.ElementHov or T.Element end
						paint()
						b.MouseEnter:Connect(function() if not on() then tween(b, E_FAST, { BackgroundColor3=T.ElementHov }) end end)
						b.MouseLeave:Connect(function() if not on() then tween(b, E_FAST, { BackgroundColor3=T.Element }) end end)
						b.MouseButton1Click:Connect(function()
							if multi then local idx = table.find(element.Value, opt); if idx then table.remove(element.Value, idx) else table.insert(element.Value, opt) end paint(); refresh(); task.spawn(cb, element.Value)
							else element.Value = opt; Window.Flags[flag]=opt; for _, bb in ipairs(buttons) do bb.TextColor3=T.SubText; bb.BackgroundColor3=T.Element end paint(); refresh(); task.spawn(cb, opt); element.Open=false; tween(f, E_FAST, { Size=UDim2.new(1,0,0,heightClosed()) }); tween(arrow, E_FAST, { Rotation=0 }) end
						end)
						table.insert(buttons, b)
					end
				end
				rebuild()
				hbtn.MouseButton1Click:Connect(function()
					if not element.Open and Window._openDrop and Window._openDrop ~= element then pcall(Window._openDrop.Close) end
					element.Open = not element.Open
					Window._openDrop = element.Open and element or nil
					local hooks = element.Open and element._opens or element._closes
					if hooks then for _, fn in ipairs(hooks) do task.spawn(fn) end end
					if element.Open then
						local listH = math.min(ll.AbsoluteContentSize.Y, 140)
						listWrap.Size = UDim2.new(1,0,0,listH)
						tween(f, E_SMOO, { Size=UDim2.new(1,0,0,heightClosed()+listH+4) }); tween(arrow, E_SNAP, { Rotation=180 })
						for bi, bb in ipairs(buttons) do
							bb.Position = UDim2.new(0,-16,0,0); bb.TextTransparency = 1
							task.delay(0.05*bi*SPEED.mul, function() if element.Open then tween(bb, TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position=UDim2.new(0,0,0,0), TextTransparency=0 }) end end)
						end
					else tween(f, E_FAST, { Size=UDim2.new(1,0,0,heightClosed()) }); tween(arrow, E_FAST, { Rotation=0 }); task.delay(0.25*SPEED.mul, function() if not element.Open then listWrap.Size = UDim2.new(1,0,0,0) end end) end
				end)
				function element:Set(v, skip) if multi then element.Value = v or {} else element.Value = v end Window.Flags[flag]=element.Value; refresh(); rebuild(); if not skip and not multi then task.spawn(cb, v) end end
				function element:Get() return element.Value end
				function element:SetOptions(o) element._opt = o or {}; rebuild(); refresh() end
				function element.Close() if element.Open then element.Open=false; tween(f, E_FAST, { Size=UDim2.new(1,0,0,heightClosed()) }); tween(arrow, E_FAST, { Rotation=0 }); task.delay(0.25*SPEED.mul, function() if not element.Open then listWrap.Size = UDim2.new(1,0,0,0) end end) end end
				f.Size = UDim2.new(1,0,0,heightClosed()); listWrap.Size = UDim2.new(1,0,0,0); table.insert(Window._recolor, function() if not element.Open then sel.TextColor3 = ((multi and #element.Value>0) or (not multi and element.Value)) and Window._accent or T.SubText end for _,bb in ipairs(buttons) do local isOn = multi and (table.find(element.Value, bb.Text:sub(3))~=nil) or (element.Value==bb.Text:sub(3)); if isOn then bb.TextColor3 = Window._accent end end end)
				if default then element:Set(default, true) end
				Window.Elements[flag]=element; Window.Flags[flag]=element.Value; element.Instance=f
				reg(f, text, element); return element
			end
			function boxAPI:Dropdown(text, options, default, cb, dopts) return buildDropdown(text, options, false, default, cb, dopts) end
			function boxAPI:MultiDropdown(text, options, defaults, cb, dopts) return buildDropdown(text, options, true, defaults, cb, dopts) end
			function boxAPI:PlayerDropdown(text, cb, popts)
				cb = cb or function() end
				local map = {}
				local function label(p) local n = Window._anon and Window:AnonName(p) or p.Name; map[n] = p; return n end
				local names = {}
				for _, p in ipairs(Players:GetPlayers()) do table.insert(names, label(p)) end
				local element = buildDropdown(text, names, false, nil, function(nm) cb(nm, map[nm]) end, popts)
				local function sync()
					map = {}
					local l = {} for _, p in ipairs(Players:GetPlayers()) do table.insert(l, label(p)) end
					element:SetOptions(l)
				end
				table.insert(_conns, Players.PlayerAdded:Connect(sync))
				table.insert(_conns, Players.PlayerRemoving:Connect(function() task.defer(sync) end))
				table.insert(Window._anonRefresh, sync)
				function element:GetPlayer() return element.Value and map[element.Value] or nil end
				return element
			end
			function boxAPI:Keybind(text, defaultKey, cb, kopts)
				if type(defaultKey) == "function" then cb, defaultKey = defaultKey, nil end
				if type(defaultKey) == "table" then kopts, defaultKey = defaultKey, nil end
				if type(cb) == "table" then kopts, cb = cb, nil end
				cb = cb or function() end
				kopts = kopts or {}
				local flag = mkFlag(text, kopts)
				local MODES = kopts.Modes or { "Toggle", "Hold", "Always" }
				local f = line(24)
				local l = lbl(f, text, 0); l.Size = UDim2.new(1,-84,1,0)
				local disp = new("TextButton", { Name="AF", BackgroundColor3=T.Element, BorderSizePixel=0, AnchorPoint=Vector2.new(1,0.5), Position=UDim2.new(1,0,0.5,0), Size=UDim2.new(0,80,0,22), Font=T.FontMed, Text="None", TextColor3=aLo, TextSize=11, TextScaled=false, TextTruncate=Enum.TextTruncate.AtEnd, AutoButtonColor=false, Parent=f })
				corner(disp, T.RadiusXs); skinTag(disp, "element")

				local element = { Value=nil, Flag=flag, Mode = kopts.Mode or MODES[1] or "Toggle", Active = false }
				local listening, listenAt = false, 0

				-- keyboard keys AND mouse buttons are both valid binds
				local function keyName(k)
					if k == nil then return "None" end
					if typeof(k) == "EnumItem" and k.EnumType == Enum.UserInputType then
						local m = { MouseButton1="MB1", MouseButton2="MB2", MouseButton3="MB3" }
						return m[k.Name] or k.Name
					end
					return (k.Name:gsub("Right","R"):gsub("Left","L"):gsub("Control","Ctrl"):gsub("Button","B"))
				end
				local function inputMatches(input)
					local v = element.Value
					if v == nil then return false end
					if typeof(v) == "EnumItem" and v.EnumType == Enum.UserInputType then return input.UserInputType == v end
					return input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == v
				end
				local function refreshText()
					local suffix = ""
					if #MODES > 1 and element.Mode ~= "Toggle" then
						suffix = (element.Mode == "Hold") and " \u{00B7}H" or " \u{00B7}A"
					end
					disp.Text = keyName(element.Value) .. suffix
				end

				local function fire(active)
					element.Active = active
					Window.Flags[flag .. " (state)"] = active
					if element._bound then element._bound:Set(active) end
					if element._fireHooks then element._fireHooks(active) end
					task.spawn(cb, active, element.Value, element.Mode)
				end
				stateHelpers(element, function() return element.Active end)

				function element:GetMode() return element.Mode end
				function element:SetMode(m)
					local okMode = false
					for _, mm in ipairs(MODES) do if mm == m then okMode = true end end
					if not okMode then m = MODES[1] end
					element.Mode = m
					if element.Mode == "Always" then if not element.Active then fire(true) end
					elseif element.Active and element.Mode ~= "Toggle" then fire(false) end
					if element._modeSync then element._modeSync(element.Mode) end
					refreshText()
				end
				function element:Set(k, skip)
					if typeof(k) == "string" then k = Enum.KeyCode[k] end
					if k and not Window:_bindKey(k, element.Value, flag) then
						if skip then task.delay(2.5, function() Window:Notify(("%s: %s already bound"):format(flag, keyName(k)), { Type="warning", Duration=3 }) end)
						else Window:Notify("Key already in use", { Type="warning", Duration=2 }) end
						return
					end
					if not k and element.Value then Window:_bindKey(nil, element.Value, flag) end
					element.Value = k; Window.Flags[flag] = k
					refreshText()
					if not skip then task.spawn(cb, element.Active, k, element.Mode) end
				end
				function element:Get() return element.Value end

				-- mode is chosen in a dialog (like the exit prompt), never with buttons on the row
				local function askMode(afterSet)
					if #MODES < 2 then if afterSet then afterSet() end return end
					Window:_modeDialog(text, MODES, element.Mode, function(chosen)
						element:SetMode(chosen)
						if afterSet then afterSet() end
					end)
				end
				element.AskMode = askMode

				disp.MouseButton1Click:Connect(function()
					if listening then stopListening(); return end
					listening = true; listenAt = os.clock()
					disp.Text = "press key \u{00B7} esc = none"
					tween(disp, E_FAST, { BackgroundColor3 = Window._accent })
				end)
				disp.MouseButton2Click:Connect(function()
					if element.Value == nil then return end
					local items = {}
					if #MODES > 1 then table.insert(items, { "Change mode\u{2026}", function() askMode() end }) end
					table.insert(items, { "Clear bind", function() element:Set(nil); Window:Notify((text or "Bind")..": None", { Duration=1.6 }) end })
					Window:_showCtx(items)
				end)

				local function overDisp()
					local m = UserInputService:GetMouseLocation()
					local p, sz = disp.AbsolutePosition, disp.AbsoluteSize
					return m.X >= p.X - 2 and m.X <= p.X + sz.X + 2 and m.Y >= p.Y + 34 and m.Y <= p.Y + sz.Y + 38
				end
				local function stopListening() listening = false; tween(disp, E_FAST, { BackgroundColor3 = T.Element }); refreshText() end
				UIS_.InputBegan:Connect(function(input, processed)
					if listening then
						if os.clock() - listenAt < 0.2 then return end
						local it = input.UserInputType
						if it == Enum.UserInputType.Keyboard then
							local kc = input.KeyCode
							if kc == Enum.KeyCode.Escape or kc == Enum.KeyCode.Backspace or kc == Enum.KeyCode.Delete then
								listening = false
								tween(disp, E_FAST, { BackgroundColor3 = T.Element })
								element:Set(nil)
							else
								listening = false
								tween(disp, E_FAST, { BackgroundColor3 = T.Element })
								element:Set(kc)
								if #MODES > 1 and kopts.AskMode then task.defer(askMode) end
							end
						elseif it == Enum.UserInputType.MouseButton1 or it == Enum.UserInputType.MouseButton2 or it == Enum.UserInputType.MouseButton3 then
							if overDisp() then
								listening = false
								tween(disp, E_FAST, { BackgroundColor3 = T.Element })
								element:Set(it)
								if #MODES > 1 and kopts.AskMode then task.defer(askMode) end
							else
								stopListening()   -- clicking outside cancels, never binds M1
							end
						end
						return
					end
					if processed or Window._typing then return end
					if Window._ctrlDown() and input.UserInputType == Enum.UserInputType.Keyboard
						and input.KeyCode ~= Enum.KeyCode.LeftControl and input.KeyCode ~= Enum.KeyCode.RightControl
						and element.Value ~= Enum.KeyCode.LeftControl and element.Value ~= Enum.KeyCode.RightControl then return end
					if element._gate and not (element._gate.Get and element._gate:Get() or element._gate.Value) then return end
					if inputMatches(input) then
						if element.Mode == "Hold" then fire(true)
						elseif element.Mode == "Toggle" then fire(not element.Active) end
					end
				end)
				UIS_.InputEnded:Connect(function(input)
					if element.Mode == "Hold" and element.Active and inputMatches(input) then fire(false) end
				end)

				element:SetMode(kopts.Mode or MODES[1])
				if defaultKey then element:Set(defaultKey, true) end
				if Window._addBind then Window:_addBind(text, element, element.Mode) end
				Window.Elements[flag] = element
				reg(f, text, element); return element
			end
			function boxAPI:Colorpicker(text, default, cb, copts)
				if type(default) == "function" then cb, default = default, nil end
				cb = cb or function() end
				local flag = mkFlag(text, copts)
				default = default or Color3.fromRGB(255,255,255)
				local h, s, v = default:ToHSV()
				local f = new("Frame", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,22), ClipsDescendants=true, Parent=curParent })
				local l = lbl(f, text, 0); l.Size=UDim2.new(1,-30,0,22)
				local swatch = new("Frame", { BackgroundColor3=Color3.new(1,1,1), BorderSizePixel=0, AnchorPoint=Vector2.new(1,0.5), Position=UDim2.new(1,0,0.5,0), Size=UDim2.new(0,16,0,16), Parent=f }); local swGrad=new("UIGradient", { Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(255,95,95)),ColorSequenceKeypoint.new(0.33,Color3.fromRGB(120,210,100)),ColorSequenceKeypoint.new(0.66,Color3.fromRGB(85,160,255)),ColorSequenceKeypoint.new(1,Color3.fromRGB(215,110,255))}), Rotation=45, Parent=swatch })
				corner(swatch, 8)
				local hbtn = new("TextButton", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,22), Text="", Parent=f })
				local svBox = new("Frame", { BackgroundColor3=Color3.fromHSV(h,1,1), BorderSizePixel=0, Position=UDim2.new(0,0,0,28), Size=UDim2.new(1,0,0,80), Parent=f })
				corner(svBox, T.RadiusXs)
				local svSat = new("Frame", { BackgroundColor3=Color3.new(1,1,1), BorderSizePixel=0, Size=UDim2.new(1,0,1,0), Parent=svBox }); corner(svSat, T.RadiusXs)
				new("UIGradient", { Rotation=0, Transparency=NumberSequence.new({ NumberSequenceKeypoint.new(0,0), NumberSequenceKeypoint.new(1,1) }), Parent=svSat })
				local svVal = new("Frame", { BackgroundColor3=Color3.new(0,0,0), BorderSizePixel=0, Size=UDim2.new(1,0,1,0), Parent=svBox }); corner(svVal, T.RadiusXs)
				new("UIGradient", { Rotation=90, Transparency=NumberSequence.new({ NumberSequenceKeypoint.new(0,1), NumberSequenceKeypoint.new(1,0) }), Parent=svVal })
				local svCur = new("Frame", { BackgroundColor3=Color3.new(1,1,1), BorderSizePixel=0, AnchorPoint=Vector2.new(0.5,0.5), Size=UDim2.new(0,7,0,7), ZIndex=3, Parent=svBox }); corner(svCur, 4); stroke(svCur, Color3.new(0,0,0), 1, 0.2)
				local hue = new("Frame", { BorderSizePixel=0, Position=UDim2.new(0,0,0,114), Size=UDim2.new(1,0,0,10), Parent=f }); corner(hue, T.RadiusXs)
				new("UIGradient", { Color=ColorSequence.new({ ColorSequenceKeypoint.new(0.00,Color3.fromRGB(255,0,0)), ColorSequenceKeypoint.new(0.17,Color3.fromRGB(255,255,0)), ColorSequenceKeypoint.new(0.33,Color3.fromRGB(0,255,0)), ColorSequenceKeypoint.new(0.50,Color3.fromRGB(0,255,255)), ColorSequenceKeypoint.new(0.67,Color3.fromRGB(0,0,255)), ColorSequenceKeypoint.new(0.83,Color3.fromRGB(255,0,255)), ColorSequenceKeypoint.new(1.00,Color3.fromRGB(255,0,0)) }), Parent=hue })
				local hueCur = new("Frame", { BackgroundColor3=Color3.new(1,1,1), BorderSizePixel=0, AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.new(h,0,0.5,0), Size=UDim2.new(0,3,1,4), ZIndex=3, Parent=hue }); corner(hueCur, 2)
				local element = { Value=default, Flag=flag, Open=false }
				local function apply(skip) element.Value = Color3.fromHSV(h,s,v); Window.Flags[flag]=element.Value; if element.Open then swatch.BackgroundColor3=element.Value end; svBox.BackgroundColor3=Color3.fromHSV(h,1,1); svCur.Position=UDim2.new(s,0,1-v,0); hueCur.Position=UDim2.new(h,0,0.5,0); if not skip then task.spawn(cb, element.Value) end end
				function element:Set(c, skip) h,s,v = c:ToHSV(); apply(skip) end
				function element:Get() return element.Value end
				apply(true)
				local sd, hd = false, false
				svBox.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then sd=true end end)
				hue.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then hd=true end end)
				UIS_.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then sd,hd=false,false end end)
				UIS_.InputChanged:Connect(function(i)
					if i.UserInputType~=Enum.UserInputType.MouseMovement and i.UserInputType~=Enum.UserInputType.Touch then return end
					if sd then s = math.clamp((i.Position.X - svBox.AbsolutePosition.X)/svBox.AbsoluteSize.X,0,1); v = 1 - math.clamp((i.Position.Y - svBox.AbsolutePosition.Y)/svBox.AbsoluteSize.Y,0,1); apply()
					elseif hd then h = math.clamp((i.Position.X - hue.AbsolutePosition.X)/hue.AbsoluteSize.X,0,1); apply() end
				end)
				hbtn.MouseButton1Click:Connect(function() element.Open = not element.Open; if element.Open then swGrad.Enabled=false; swatch.BackgroundColor3=element.Value else swGrad.Enabled=true; swatch.BackgroundColor3=Color3.new(1,1,1) end; tween(f, E_SMOO, { Size=UDim2.new(1,0,0, element.Open and 130 or 22) }) end)
				Window.Elements[flag]=element; Window.Flags[flag]=element.Value
				reg(f, text); return element
			end
			local function attachDeps(el, frame)
				function el:DependsOn(other, wanted)
					if wanted == nil then wanted = true end
					local function sync()
						local on = (other.Get and other:Get() or other.Value) == wanted
						if el.SetLocked then el:SetLocked(not on) else
							for _, d in ipairs(frame:GetDescendants()) do
								if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then pcall(function() d.TextTransparency = on and 0 or 0.55 end) end
								if d:IsA("Frame") and d.BackgroundTransparency < 1 then pcall(function() d.BackgroundTransparency = on and 0 or 0.5 end) end
							end
						end
						frame.Active = on
						for _, d in ipairs(frame:GetDescendants()) do if d:IsA("TextButton") or d:IsA("TextBox") then d.Active = on; d.Selectable = on end end
					end
					sync()
					table.insert(Window._deps, sync)
					return el
				end
				return el
			end
			local attachHooksCore
			local function attachHooks(el, isButton, kind)
				local frame = el.Instance or (group.items[#group.items] and group.items[#group.items].frame)
				-- universal signals, whatever the component
				el._hoverIn, el._hoverOut = {}, {}
				function el:OnHover(fn) table.insert(el._hoverIn, fn); return el end
				function el:OnUnhover(fn) table.insert(el._hoverOut, fn); return el end
				if frame then
					frame.MouseEnter:Connect(function() for _, fn in ipairs(el._hoverIn) do task.spawn(fn) end end)
					frame.MouseLeave:Connect(function() for _, fn in ipairs(el._hoverOut) do task.spawn(fn) end end)
				end
				function el:Tooltip(txt) if frame and attachTooltip then attachTooltip(frame, txt) end return el end
				function el:SetKeywords(words)
					el.Keywords = (type(words) == "table") and table.concat(words, " ") or tostring(words)
					return el
				end
				function el:Hide() if el.SetVisible then el:SetVisible(false) elseif frame then frame.Visible = false end return el end
				function el:Show() if el.SetVisible then el:SetVisible(true) elseif frame then frame.Visible = true end return el end
				function el:Lock() if el.SetLocked then el:SetLocked(true) end return el end
				function el:Unlock() if el.SetLocked then el:SetLocked(false) end return el end
				function el:Reset()
					if Window._defaults and el.Flag and Window._defaults[el.Flag] ~= nil and el.Set then pcall(function() el:Set(Window._defaults[el.Flag]) end) end
					return el
				end
				-- slider / textbox: fire only when the user stops dragging or presses Enter
				if kind == "Slider" or kind == "TextBox" then
					el._commits = {}
					function el:OnCommit(fn) table.insert(el._commits, fn); return el end
					function el:OnRelease(fn) return el:OnCommit(fn) end
					el._fireCommit = function(v) for _, fn in ipairs(el._commits) do task.spawn(fn, v) end end
				end
				-- dropdowns: open / close signals
				if kind == "Dropdown" or kind == "MultiDropdown" or kind == "PlayerDropdown" then
					el._opens, el._closes = {}, {}
					function el:OnOpen(fn) table.insert(el._opens, fn); return el end
					function el:OnClose(fn) table.insert(el._closes, fn); return el end
				end
				-- keybind: know when the bind itself or its mode changes
				if kind == "Keybind" then
					el._binds, el._modes = {}, {}
					function el:OnBind(fn) table.insert(el._binds, fn); return el end
					function el:OnModeChanged(fn) table.insert(el._modes, fn); return el end
					local setMode = el.SetMode
					if setMode then
						function el:SetMode(m)
							setMode(el, m)
							for _, fn in ipairs(el._modes) do task.spawn(fn, el.Mode) end
						end
					end
					local setK = el.Set
					if setK then
						function el:Set(k, skip)
							setK(el, k, skip)
							for _, fn in ipairs(el._binds) do task.spawn(fn, el.Value, el.Mode) end
						end
					end
				end
				return attachHooksCore(el, isButton)
			end
			attachHooksCore = function(el, isButton)
				if isButton then
					el._clicks = {}
					local fire = el.Fire
					function el:OnClick(fn) table.insert(el._clicks, fn); return el end
					function el:Fire(...)
						for _, fn in ipairs(el._clicks) do task.spawn(fn) end
						if fire then return fire(...) end
					end
					if el.Instance then
						local btn = el.Instance:FindFirstChildWhichIsA("TextButton")
						if btn then btn.MouseButton1Click:Connect(function() for _, fn in ipairs(el._clicks) do task.spawn(fn) end end) end
					end
					return el
				end
				if el.OnChanged then return el end            -- Toggle / Keybind already have full state helpers
				el._hooks = el._hooks or {}
				function el:OnChanged(fn)
					if not Window._normFn(fn, "OnChanged") then return el end
					table.insert(el._hooks, fn)
					task.spawn(fn, (el.Get and el:Get()) or el.Value)
					return el
				end
				if el.OnLoop and not el.Every then function el:Every(interval, fn) return el:OnLoop(fn, interval) end end
				if not el.OnLoop then
					function el:OnLoop(fn, interval)
						local f2, iv = Window._normLoop(fn, interval, "OnLoop")
						if not f2 then return el end
						Window._spawnLoop(iv, nil, function() return f2((el.Get and el:Get()) or el.Value) end)
						return el
					end
					function el:Every(interval, fn) return el:OnLoop(fn, interval) end
				end
				if el.OnCommit and not el.OnRelease then function el:OnRelease(fn) return el:OnCommit(fn) end end
				local set = el.Set
				if set then
					function el:Set(v, skip)
						set(el, v, skip)
						for _, fn in ipairs(el._hooks) do task.spawn(fn, (el.Get and el:Get()) or el.Value) end
					end
				end
				return el
			end
			local ARGSPEC = {
				Toggle        = { {"Name","string"}, {"Default","boolean"}, {"Callback","function"}, {"Options","table"} },
				Slider        = { {"Name","string"}, {"Default","number"}, {"Min","number"}, {"Max","number"}, {"Callback","function"}, {"Options","table"} },
				TextBox       = { {"Name","string"}, {"Placeholder","string"}, {"ClearOnFocus","boolean"}, {"Callback","function"}, {"Options","table"} },
				Dropdown      = { {"Name","string"}, {"List","table"}, {"Default","string"}, {"Callback","function"}, {"Options","table"} },
				MultiDropdown = { {"Name","string"}, {"List","table"}, {"Default","table"}, {"Callback","function"}, {"Options","table"} },
				PlayerDropdown= { {"Name","string"}, {"Callback","function"}, {"Options","table"} },
				Keybind       = { {"Name","string"}, {"Key","EnumItem"}, {"Callback","function"}, {"Options","table"} },
				Colorpicker   = { {"Name","string"}, {"Default","Color3"}, {"Callback","function"}, {"Options","table"} },
				Button        = { {"Name","string"}, {"Callback","function"} },
				Label         = { {"Name","string"} },
				Section       = { {"Name","string"} },
				Progress      = { {"Name","string"}, {"Default","number"} },
				Stat          = { {"Name","string"}, {"Value","function"}, {"Interval","number"} },
			}
			local ALIASES = { Name = { "Text", "Title", "Label" }, List = { "Options", "Items", "Values" },
				Default = { "Value", "Start", "Key" }, Callback = { "Action", "OnChange", "Fn" },
				Options = { "Opts", "Config", "Settings" }, Min = { "From" }, Max = { "To" }, Key = { "Bind", "Keybind" } }
			local function resolveArgs(name, ...)
				local spec = ARGSPEC[name]
				if not spec then return ... end
				local args = table.pack(...)
				-- form 1: a single config table -> { Name = ..., Default = ..., Callback = ... }
				local first = args[1]
				if args.n == 1 and type(first) == "table" and (first.Name or first.Text or first.Title or first.Label) then
					local out = {}
					for i, slot in ipairs(spec) do
						local v = first[slot[1]]
						if v == nil then
							for _, a in ipairs(ALIASES[slot[1]] or {}) do
								if first[a] ~= nil then v = first[a]; break end
							end
						end
						out[i] = v
					end
					for i, slot in ipairs(spec) do
						if slot[1] == "Options" and out[i] == nil then out[i] = first end
					end
					return table.unpack(out, 1, #spec)
				end
				-- form 2: loose positional -> bucket by type, relative order kept inside a type
				local buckets = {}
				for i = 1, args.n do
					local v = args[i]
					if v ~= nil then
						local t = typeof(v)
						if t == "Enum" or t == "EnumItem" then t = "EnumItem" end
						buckets[t] = buckets[t] or {}
						table.insert(buckets[t], v)
					end
				end
				local out = {}
				for i, slot in ipairs(spec) do
					local b = buckets[slot[2]]
					if b and #b > 0 then out[i] = table.remove(b, 1) end
				end
				return table.unpack(out, 1, #spec)
			end
			Window._deps = Window._deps or {}
			for _, nm in ipairs({"Toggle","Slider","TextBox","Dropdown","MultiDropdown","PlayerDropdown","Keybind","Colorpicker","Button","Label","Section","Progress","Stat"}) do
				local orig = boxAPI[nm]
				boxAPI[nm] = function(self, ...)
					local el = orig(self, resolveArgs(nm, ...))
					if type(el) == "table" then
						attachDeps(el, el.Instance or (group.items[#group.items] and group.items[#group.items].frame))
						attachHooks(el, nm == "Button", nm)
					end
					return el
				end
			end
			return boxAPI
		end
		return cat
	end
		-- === Built-in settings, watermark, loader ===
	local uiScale = new("UIScale", { Scale = 1, Parent = base })
	Window._hideNotifs = false

	local watermark = new("Frame", { Name="Watermark", BackgroundColor3=T.Top, BorderSizePixel=0, AnchorPoint=Vector2.new(0.5,0), Position=UDim2.new(0.5,0,0,8), Size=UDim2.new(0,220,0,28), Visible = config.Watermark ~= false, ZIndex=45, Parent=gui })
	corner(watermark, 8); bgGrad(watermark, Color3.fromRGB(26,26,32), Color3.fromRGB(16,16,21)); skinTag(watermark, "float")
	skinTag(new("ImageLabel", { BackgroundTransparency=1, Position=UDim2.new(0,11,0.5,-7), Size=UDim2.new(0,14,0,14), Image=config.Icon or DEFAULT_ICON, ImageColor3=Color3.new(1,1,1), ZIndex=45, Parent=watermark }), "icon")
	local wmText = new("TextLabel", { BackgroundTransparency=1, RichText=true, Position=UDim2.new(0,32,0,0), Size=UDim2.new(1,-42,1,0), Font=T.FontMed, Text="Azurite", TextColor3=T.SubText, TextSize=12, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=45, Parent=watermark })
	task.spawn(function()
		local RunService=game:GetService("RunService"); local Stats=game:GetService("Stats")
		local frames, acc = 0, 0
		local hb = RunService.RenderStepped:Connect(function(dt) frames += 1; acc += dt end)
		table.insert(_conns, hb)
		while alive() do
			task.wait(1)
			if not watermark.Visible then frames, acc = 0, 0 end
			local fps = (acc > 0) and math.floor(frames/acc + 0.5) or 0
			frames, acc = 0, 0
			local ping=0
			pcall(function() ping=math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue()+0.5) end)
			local nameHex = (Window._skin=="light") and "#14141c" or "#ffffff"
			local sepHex = (Window._skin=="light") and "#9a9caa" or "#6a6a78"
			wmText.TextColor3 = T.SubText
			wmText.Text=(('<font color="%s">Azurite</font>   <font color="%s">|</font>   %d fps   <font color="%s">|</font>   %d ms   <font color="%s">|</font>   %s'):format(nameHex, sepHex, fps, sepHex, ping, sepHex, os.date("%H:%M")))
			watermark.Size=UDim2.new(0, math.clamp(wmText.TextBounds.X+46,180,340),0,28)
		end
	end)
	Window.Watermark = watermark

	local setPanel = new("ScrollingFrame", { Name="Settings", BackgroundColor3=T.Base, BorderSizePixel=0, AnchorPoint=Vector2.new(1,0), Position=UDim2.new(1,-8,0,44), Size=UDim2.new(0,238,0,120), CanvasSize=UDim2.new(), AutomaticCanvasSize=Enum.AutomaticSize.Y, ScrollBarThickness=0, ScrollingDirection=Enum.ScrollingDirection.Y, Visible=false, ZIndex=58, Parent=base })
	corner(setPanel, 8); stroke(setPanel, T.Stroke, 1, 0); bgGrad(setPanel, Color3.fromRGB(23,23,29), Color3.fromRGB(14,14,18)); pad(setPanel, 11,13,13,13); skinTag(setPanel, "float")
	new("UIListLayout", { SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,8), Parent=setPanel })
	local acc = new("Frame", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,34), LayoutOrder=1, ZIndex=58, Parent=secAccount })
	local av = new("ImageLabel", { BackgroundColor3=T.Element, Size=UDim2.new(0,30,0,30), Position=UDim2.new(0,0,0.5,-15), ZIndex=58, Parent=acc }); corner(av, 15)
	task.spawn(function() local ok,url=pcall(function() return Players:GetUserThumbnailAsync(LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100) end); if ok then av.Image=url end end)
	skinTag(new("TextLabel", { BackgroundTransparency=1, Position=UDim2.new(0,38,0,2), Size=UDim2.new(1,-40,0,15), Font=T.FontBold, Text=LocalPlayer.DisplayName, TextColor3=T.Text, TextSize=13, TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd, ZIndex=58, Parent=acc }), "text")
	skinTag(new("TextLabel", { BackgroundTransparency=1, Position=UDim2.new(0,38,0,17), Size=UDim2.new(1,-40,0,14), Font=T.Font, Text="@"..LocalPlayer.Name, TextColor3=T.Muted, TextSize=11, TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd, ZIndex=58, Parent=acc }), "muted")

	local scaleRow = new("Frame", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,30), LayoutOrder=3, ZIndex=58, Parent=secStyle })
	skinTag(new("TextLabel", { BackgroundTransparency=1, Size=UDim2.new(1,-48,0,15), Font=T.Font, Text="Menu scale", TextColor3=T.SubText, TextSize=12, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=58, Parent=scaleRow }), "sub")
	local scaleVal = new("TextLabel", { Name="AF", BackgroundTransparency=1, AnchorPoint=Vector2.new(1,0), Position=UDim2.new(1,0,0,0), Size=UDim2.new(0,48,0,15), Font=T.FontMed, Text="100%", TextColor3=aLo, TextSize=12, TextXAlignment=Enum.TextXAlignment.Right, ZIndex=58, Parent=scaleRow })
	local sTrack = new("Frame", { BackgroundColor3=T.Off, BorderSizePixel=0, Position=UDim2.new(0,0,0,21), Size=UDim2.new(1,0,0,4), ZIndex=58, Parent=scaleRow }); corner(sTrack,2); skinTag(sTrack, "off")
	local sFill = new("Frame", { BackgroundColor3=Color3.new(1,1,1), BorderSizePixel=0, Size=UDim2.new(0.45,0,1,0), ZIndex=58, Parent=sTrack }); corner(sFill,2); accentGrad(sFill,0)
	local sDrag=false
	local function setScale(a) a=math.clamp(a,0,1); local sc=0.75+a*0.55; uiScale.Scale=sc; sFill.Size=UDim2.new(a,0,1,0); scaleVal.Text=math.floor(sc*100+0.5).."%" end
	setScale((1-0.75)/0.55)
	sTrack.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then sDrag=true; setScale((i.Position.X-sTrack.AbsolutePosition.X)/sTrack.AbsoluteSize.X) end end)
	UIS_.InputChanged:Connect(function(i) if sDrag and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then setScale((i.Position.X-sTrack.AbsolutePosition.X)/sTrack.AbsoluteSize.X) end end)
	UIS_.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then sDrag=false end end)
	local themeRow = new("Frame", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,38), LayoutOrder=4, ZIndex=58, Parent=secStyle })
	skinTag(new("TextLabel", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,15), Font=T.Font, Text="Accent", TextColor3=T.SubText, TextSize=12, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=58, Parent=themeRow }), "sub")
	local sw = new("Frame", { BackgroundTransparency=1, Position=UDim2.new(0,0,0,19), Size=UDim2.new(1,0,0,18), ZIndex=58, Parent=themeRow })
	new("UIListLayout", { FillDirection=Enum.FillDirection.Horizontal, SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,8), Parent=sw })
	local presets = { {Color3.fromRGB(150,120,255),Color3.fromRGB(200,86,242)}, {Color3.fromRGB(80,196,255),Color3.fromRGB(60,92,255)}, {Color3.fromRGB(255,108,142),Color3.fromRGB(224,38,96)}, {Color3.fromRGB(96,240,150),Color3.fromRGB(32,190,116)}, {Color3.fromRGB(255,210,86),Color3.fromRGB(247,148,34)} }
	for pi, pr in ipairs(presets) do
		local b = new("TextButton", { LayoutOrder=pi, BackgroundColor3=Color3.new(1,1,1), BorderSizePixel=0, Size=UDim2.new(0,18,0,18), Text="", AutoButtonColor=false, ZIndex=58, Parent=sw }); corner(b, 5)
		new("UIGradient", { Color=ColorSequence.new(pr[1],pr[2]), Rotation=40, Parent=b })
		b.MouseButton1Click:Connect(function()
			aLo,aHi = pr[1],pr[2]; Window._accent=aLo
			applyAccent(aLo, aHi, Window._accentText and Color3.new(aLo.R*0.62, aLo.G*0.5, aLo.B*0.78) or aLo)
			for _,fn in ipairs(Window._recolor) do pcall(fn) end
		end)
	end
	local setHost = setPanel
	local _setSections = {}
	local function setSection(name, order, openByDefault)
		local wrap = new("Frame", { Name="Sec"..name, BackgroundTransparency=1, Size=UDim2.new(1,0,0,0), AutomaticSize=Enum.AutomaticSize.Y, LayoutOrder=order, ZIndex=58, Parent=setPanel })
		new("UIListLayout", { SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,7), Parent=wrap })
		local head = new("TextButton", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,20), Text="", LayoutOrder=0, ZIndex=58, Parent=wrap })
		local lab = new("TextLabel", { BackgroundTransparency=1, Position=UDim2.new(0,12,0,0), Size=UDim2.new(1,-12,1,0), Font=T.FontBold, Text=name, TextColor3=T.Text, TextSize=11, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=58, Parent=head })
		skinTag(lab, "text")
		local dot = new("Frame", { BackgroundColor3=Color3.new(1,1,1), BorderSizePixel=0, AnchorPoint=Vector2.new(0,0.5), Position=UDim2.new(0,0,0.5,0), Size=UDim2.new(0,4,0,4), ZIndex=58, Parent=head })
		corner(dot,2); accentGrad(dot)
		local chev = new("Frame", { BackgroundTransparency=1, AnchorPoint=Vector2.new(1,0.5), Position=UDim2.new(1,-2,0.5,0), Size=UDim2.new(0,10,0,10), ZIndex=58, Parent=head })
		for _, ar in ipairs({45, -45}) do
			local bl = new("Frame", { BackgroundColor3=T.Muted, BorderSizePixel=0, AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.new(ar>0 and 0.29 or 0.71, 0, 0.42, 0), Size=UDim2.new(0,6.5,0,1.6), Rotation=ar, ZIndex=58, Parent=chev }); corner(bl,1)
			table.insert(Window._recolor, function() bl.BackgroundColor3 = T.Muted end)
		end
		local body = new("Frame", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,0), AutomaticSize=Enum.AutomaticSize.None, ClipsDescendants=true, LayoutOrder=1, ZIndex=58, Parent=wrap })
		new("UIListLayout", { SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,8), Parent=body })
		local open = false
		chev.Rotation = -90
		local function setBodyVisible(v) for _, c in ipairs(body:GetChildren()) do if c:IsA("GuiObject") then c.Visible = v end end end
		task.defer(function() if not open then setBodyVisible(false) end end)
		head.MouseButton1Click:Connect(function()
			open = not open
			if open then
				setBodyVisible(true)
				body.AutomaticSize = Enum.AutomaticSize.Y
				tween(chev, E_SMOO, { Rotation = 0 })
			else
				local h = body.AbsoluteSize.Y
				body.AutomaticSize = Enum.AutomaticSize.None
				body.Size = UDim2.new(1,0,0,h)
				tween(body, E_SMOO, { Size = UDim2.new(1,0,0,0) })
				tween(chev, E_SMOO, { Rotation = -90 })
				task.delay(0.25 * SPEED.mul, function() if not open then setBodyVisible(false) end end)
			end
		end)
		head.MouseEnter:Connect(function() tween(lab, E_FAST, { TextColor3 = Window._accent }) end)
		head.MouseLeave:Connect(function() tween(lab, E_FAST, { TextColor3 = T.Text }) end)
		_setSections[name] = body
		return body
	end
	local secAccount = setSection("Account", 1)
	local secStyle   = setSection("Style", 2)
	local secWindow  = setSection("Window", 3)
	local secKeys    = setSection("Keybinds", 4)
	local secConfig  = setSection("Config", 5)
	local function setToggleRow(label, default, cb, order)
		local r = new("Frame", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,22), LayoutOrder=order, ZIndex=58, Parent=setHost })
		local cf = new("Frame", { BackgroundColor3=T.Element, BorderSizePixel=0, Position=UDim2.new(0,0,0.5,-8), Size=UDim2.new(0,16,0,16), ZIndex=58, Parent=r }); corner(cf, 4); skinTag(cf, "element"); local cg=accentGrad(cf); cg.Enabled=false
		local tk=new("TextLabel", { BackgroundTransparency=1, Size=UDim2.new(1,0,1,0), Font=T.FontBold, Text="\u{2713}", TextColor3=Color3.new(1,1,1), TextSize=12, TextTransparency=1, ZIndex=58, Parent=cf })
		skinTag(new("TextLabel", { BackgroundTransparency=1, Position=UDim2.new(0,24,0,0), Size=UDim2.new(1,-24,1,0), Font=T.Font, Text=label, TextColor3=T.SubText, TextSize=12, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=58, Parent=r }), "sub")
		local st=false
		local function set(v) st=v; cg.Enabled=v; cf.BackgroundColor3 = v and Color3.new(1,1,1) or T.Element; tween(tk,E_FAST,{TextTransparency=v and 0 or 1}); cb(v) end
		table.insert(Window._recolor, function() if not st then cf.BackgroundColor3 = T.Element end end)
		new("TextButton", { BackgroundTransparency=1, Size=UDim2.new(1,0,1,0), Text="", ZIndex=58, Parent=r }).MouseButton1Click:Connect(function() set(not st) end)
		set(default)
		return set
	end
	do
		local nameLbl, tagLbl
		for _, c in ipairs(acc:GetChildren()) do if c:IsA("TextLabel") then if not nameLbl then nameLbl = c else tagLbl = c end end end
		Window._anonName, Window._anonTag, Window._anonAv = nameLbl, tagLbl, av
	end
	setHost = secAccount
	table.insert(Window._anonRefresh, function()
		local v = Window._anon
		if Window._anonName then Window._anonName.Text = v and "Anonymous" or LocalPlayer.DisplayName end
		if Window._anonTag then Window._anonTag.Text = v and "@hidden" or ("@"..LocalPlayer.Name) end
		if Window._anonAv then Window._anonAv.ImageTransparency = v and 1 or 0; Window._anonAv.BackgroundColor3 = v and T.Off or T.Element end
	end)
	setToggleRow("Anonymous (stream safe)", config.Anonymous == true, function(v) Window:SetAnonymous(v) end, 4.2)
	setHost = secWindow
	setToggleRow("Hide watermark", config.Watermark == false, function(v) watermark.Visible = not v end, 5)
	setToggleRow("Hide notifications", false, function(v) Window._hideNotifs = v end, 6)
	local function setKeybindRow(label, default, cb, order, sysId)
		local r = new("Frame", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,24), LayoutOrder=order, ZIndex=58, Parent=setHost })
		skinTag(new("TextLabel", { BackgroundTransparency=1, Size=UDim2.new(1,-76,1,0), Font=T.Font, Text=label, TextColor3=T.SubText, TextSize=12, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=58, Parent=r }), "sub")
		local disp = new("TextButton", { Name="AF", BackgroundColor3=T.Element, BorderSizePixel=0, AnchorPoint=Vector2.new(1,0.5), Position=UDim2.new(1,0,0.5,0), Size=UDim2.new(0,72,0,22), Font=T.FontMed, Text="None", TextColor3=aLo, TextSize=11, AutoButtonColor=false, ZIndex=58, Parent=r }); corner(disp, 4); skinTag(disp, "element")
		local listening = false; local curKey = nil
		local function short(k) if not k then return "None" end return (k.Name:gsub("Right","R"):gsub("Left","L"):gsub("Control","Ctrl")) end
		local proxy = { Value=nil }
		local function set(k, skip) if k and not Window:_bindKey(k, curKey, "set:"..label) then if not skip then Window:Notify("Key already in use", {Type="warning", Duration=2}) end return end if not k and curKey then Window:_bindKey(nil, curKey, "set:"..label) end curKey=k; proxy.Value=k; disp.Text=short(k); cb(k) end
		disp.MouseButton1Click:Connect(function() listening=true; disp.Text="..." end)
		UIS_.InputBegan:Connect(function(inp, gpe)
			if not listening then return end
			if inp.UserInputType==Enum.UserInputType.Keyboard then listening=false; if inp.KeyCode==Enum.KeyCode.Escape then set(nil) else set(inp.KeyCode) end
			elseif inp.UserInputType==Enum.UserInputType.MouseButton1 then listening=false; disp.Text=short(curKey) end
		end)
		set(default, true)
		if sysId then if Window._addBind then Window:_addBind(sysId, proxy, "System") else table.insert(Window._pendingBinds, { sysId, proxy, "System" }) end end
	end
	setHost = secKeys
	setKeybindRow("Menu key", config.Keybind or Enum.KeyCode.RightShift, function(k) Window.Keybind = k end, 7.5, "Toggle menu")
	setKeybindRow("Minimize key", config.MinimizeKey, function(k) Window._minKey = k end, 8, "Minimize / restore")
	setKeybindRow("Exit key", config.CloseKey, function(k) Window._exitKey = k end, 9, "Exit")
	setHost = secWindow
	setToggleRow("Hide minimize mark", false, function(v) Window._hideMinMark = v end, 10)
	setHost = secKeys
	setKeybindRow("Command bar key", config.CommandKey or Enum.KeyCode.Semicolon, function(k) Window._cmdKey = k end, 10.5, "Command bar")
	setHost = secStyle
	setToggleRow("Rainbow accent", true, function(v) Window._rainbow = v end, 11)
	setHost = secWindow
	do -- skin selector
		local r = new("Frame", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,40), LayoutOrder=4.5, ZIndex=58, Parent=secStyle })
		skinTag(new("TextLabel", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,15), Font=T.Font, Text="Skin", TextColor3=T.SubText, TextSize=12, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=58, Parent=r }), "sub")
		local row = new("Frame", { BackgroundTransparency=1, Position=UDim2.new(0,0,0,19), Size=UDim2.new(1,0,0,21), ZIndex=58, Parent=r })
		new("UIListLayout", { FillDirection=Enum.FillDirection.Horizontal, SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,5), Parent=row })
		local btns = {}
		for idx, sk in ipairs({ {"Dark","dark"}, {"Light","light"}, {"Glass","transparent"} }) do
			local b = new("TextButton", { Name="SkinBtn", LayoutOrder=idx, BackgroundColor3=T.Element, BorderSizePixel=0, Size=UDim2.new(0.333,-4,1,0), Font=T.FontMed, Text=sk[1], TextColor3=T.SubText, TextSize=11, AutoButtonColor=false, ZIndex=58, Parent=row })
			corner(b, 5); skinTag(b, "element")
			table.insert(btns, { id=sk[2], btn=b })
			b.MouseButton1Click:Connect(function()
				Window:SetSkin(sk[2])
				for _, e in ipairs(btns) do
					local on = (e.id == sk[2])
					e.btn.Name = on and "AF" or "SkinBtn"
					TweenService:Create(e.btn, E_FAST, { TextColor3 = on and Window._accent or T.SubText }):Play()
				end
			end)
		end
		task.defer(function() local d = btns[1] and btns[1].btn; if d then d.Name="AF"; d.TextColor3 = Window._accent end end)
	end
	do -- window opacity
		local r = new("Frame", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,30), LayoutOrder=11.5, ZIndex=58, Parent=secWindow })
		new("TextLabel", { BackgroundTransparency=1, Size=UDim2.new(1,-48,0,15), Font=T.Font, Text="Opacity", TextColor3=T.SubText, TextSize=12, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=58, Parent=r })
		local ov = new("TextLabel", { Name="AF", BackgroundTransparency=1, AnchorPoint=Vector2.new(1,0), Position=UDim2.new(1,0,0,0), Size=UDim2.new(0,48,0,15), Font=T.FontMed, Text="100%", TextColor3=aLo, TextSize=12, TextXAlignment=Enum.TextXAlignment.Right, ZIndex=58, Parent=r })
		local tr = new("Frame", { BackgroundColor3=T.Off, BorderSizePixel=0, Position=UDim2.new(0,0,0,21), Size=UDim2.new(1,0,0,4), ZIndex=58, Parent=r }); corner(tr,2)
		local fi = new("Frame", { BackgroundColor3=Color3.new(1,1,1), BorderSizePixel=0, Size=UDim2.new(1,0,1,0), ZIndex=58, Parent=tr }); corner(fi,2); accentGrad(fi,0)
		local dr=false
		local function setOp(a) a=math.clamp(a,0,1); local t=(1-a)*0.55; base.BackgroundTransparency=t; top.BackgroundTransparency=t; side.BackgroundTransparency=t; fi.Size=UDim2.new(a,0,1,0); ov.Text=math.floor(45+a*55).."%" end
		tr.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dr=true; setOp((i.Position.X-tr.AbsolutePosition.X)/tr.AbsoluteSize.X) end end)
		UIS_.InputChanged:Connect(function(i) if dr and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then setOp((i.Position.X-tr.AbsolutePosition.X)/tr.AbsoluteSize.X) end end)
		UIS_.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dr=false end end)
	end
	do -- background blur (default ON, follows minimize state, self-healing)
		local Lighting = game:GetService("Lighting")
		local blur = Instance.new("BlurEffect")
		blur.Name = "AzuriteBlur"; blur.Size = 0; blur.Enabled = false; blur.Parent = Lighting
		Window._blur = blur
		Window._blurWanted = (config.Blur ~= false)
		function Window:_syncBlur(instant)
			local b = Window._blur
			if not b or not b.Parent then return end
			local show = Window._blurWanted and Window.Open and _aliveRef.alive
			local target = show and ((Window._skin == "transparent") and 18 or 12) or 0
			b.Enabled = true
			if instant then b.Size = target else TweenService:Create(b, E_SMOO, { Size = target }):Play() end
			if not show then task.delay(0.32, function()
				if b and b.Parent and not (Window._blurWanted and Window.Open and _aliveRef.alive) then b.Size = 0; b.Enabled = false end
			end) end
		end
		function Window:Search(q)
		if Window._searchBox then Window._searchBox.Text = tostring(q or "") end
		return Window
	end
	function Window:SelectCategory(name)
		for _, c in ipairs(Window.Categories) do if c.Name == name then c.Select(); return true end end
		return false
	end
	function Window:FixBlur()
			for _, o in ipairs(Lighting:GetChildren()) do
				if o:IsA("BlurEffect") and (o.Name == "AzuriteBlur" or o == Window._blur) then pcall(function() o:Destroy() end) end
			end
			local nb = Instance.new("BlurEffect")
			nb.Name = "AzuriteBlur"; nb.Size = 0; nb.Enabled = false; nb.Parent = Lighting
			Window._blur = nb
			Window:_syncBlur(true)
			Window:Notify("Blur reset", { Type = "success", Duration = 2 })
		end
		setHost = secWindow
		setToggleRow("Background blur", config.Blur ~= false, function(v) Window._blurWanted = v; Window:_syncBlur() end, 11.7)
		do
			local r = new("Frame", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,26), LayoutOrder=11.75, ZIndex=58, Parent=secWindow })
			local b = new("TextButton", { BackgroundColor3=T.Element, BorderSizePixel=0, Size=UDim2.new(1,0,1,0), Font=T.FontMed, Text="Fix blur bug", TextColor3=T.SubText, TextSize=11, AutoButtonColor=false, ZIndex=58, Parent=r })
			corner(b, 5); skinTag(b, "element")
			b.MouseEnter:Connect(function() tween(b, E_FAST, { BackgroundColor3=T.ElementHov }) end)
			b.MouseLeave:Connect(function() tween(b, E_FAST, { BackgroundColor3=T.Element }) end)
			b.MouseButton1Click:Connect(function() Window:FixBlur() end)
		end
		task.spawn(function()
			task.wait(0.2)
			Window:_syncBlur(true)
			while alive() do
				local mine = Window._blur
				for _, o in ipairs(Lighting:GetChildren()) do
					if o:IsA("BlurEffect") and o.Name == "AzuriteBlur" and o ~= mine then pcall(function() o:Destroy() end) end
				end
				if mine and mine.Parent then
					local show = Window._blurWanted and Window.Open and _aliveRef.alive
					if not show and mine.Size > 0.1 then Window:_syncBlur() end
				end
				task.wait(1)
			end
		end)
	end
	do -- profiles row
		local r = new("Frame", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,52), LayoutOrder=11.8, ZIndex=58, Parent=secConfig })
		new("TextLabel", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,15), Font=T.Font, Text="Profile", TextColor3=T.SubText, TextSize=12, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=58, Parent=r })
		local nameBox = new("TextBox", { BackgroundColor3=T.Element, BorderSizePixel=0, Position=UDim2.new(0,0,0,19), Size=UDim2.new(1,0,0,22), Font=T.Font, Text="default", PlaceholderText="name", PlaceholderColor3=T.Muted, TextColor3=T.Text, TextSize=11, ClearTextOnFocus=false, ZIndex=58, Parent=r }); corner(nameBox,4)
		local function mini(txt, x, w, fn)
			local b = new("TextButton", { BackgroundColor3=T.Element, BorderSizePixel=0, Position=UDim2.new(x,0,0,45), Size=UDim2.new(w,-3,0,0), Font=T.FontMed, Text=txt, TextColor3=T.SubText, TextSize=11, AutoButtonColor=false, ZIndex=58, Parent=r })
			b.Size = UDim2.new(w,-3,0,0)
			return b
		end
		local sBtn = new("TextButton", { BackgroundColor3=T.Element, BorderSizePixel=0, Position=UDim2.new(0,0,0,45), Size=UDim2.new(0.5,-3,0,0), Font=T.FontMed, Text="Save", TextColor3=T.SubText, TextSize=11, AutoButtonColor=false, ZIndex=58, Parent=r }); corner(sBtn,4)
		local lBtn = new("TextButton", { BackgroundColor3=T.Element, BorderSizePixel=0, Position=UDim2.new(0.5,3,0,45), Size=UDim2.new(0.5,-3,0,0), Font=T.FontMed, Text="Load", TextColor3=T.SubText, TextSize=11, AutoButtonColor=false, ZIndex=58, Parent=r }); corner(lBtn,4)
		r.Size = UDim2.new(1,0,0,71); sBtn.Size = UDim2.new(0.5,-3,0,22); lBtn.Size = UDim2.new(0.5,-3,0,22)
		for _, b in ipairs({sBtn,lBtn}) do
			b.MouseEnter:Connect(function() tween(b, E_FAST, { BackgroundColor3=T.ElementHov }) end)
			b.MouseLeave:Connect(function() tween(b, E_FAST, { BackgroundColor3=T.Element }) end)
		end
		sBtn.MouseButton1Click:Connect(function() Window:SaveProfile(nameBox.Text) end)
		lBtn.MouseButton1Click:Connect(function() Window:LoadProfile(nameBox.Text) end)
	end
	do -- animation speed
		local r = new("Frame", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,30), LayoutOrder=11.6, ZIndex=58, Parent=secStyle })
		skinTag(new("TextLabel", { BackgroundTransparency=1, Size=UDim2.new(1,-48,0,15), Font=T.Font, Text="Animation speed", TextColor3=T.SubText, TextSize=12, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=58, Parent=r }), "sub")
		local val = new("TextLabel", { Name="AF", BackgroundTransparency=1, AnchorPoint=Vector2.new(1,0), Position=UDim2.new(1,0,0,0), Size=UDim2.new(0,52,0,15), Font=T.FontMed, Text="1.0x", TextColor3=aLo, TextSize=12, TextXAlignment=Enum.TextXAlignment.Right, ZIndex=58, Parent=r })
		local tr = new("Frame", { BackgroundColor3=T.Off, BorderSizePixel=0, Position=UDim2.new(0,0,0,21), Size=UDim2.new(1,0,0,4), ZIndex=58, Parent=r }); corner(tr,2); skinTag(tr,"off")
		local fi = new("Frame", { BackgroundColor3=Color3.new(1,1,1), BorderSizePixel=0, Size=UDim2.new(0.33,0,1,0), ZIndex=58, Parent=tr }); corner(fi,2); accentGrad(fi,0)
		local dr=false
		local function setSpd(a) a=math.clamp(a,0,1); SPEED.mul = 0.5 + a*2.5; fi.Size=UDim2.new(a,0,1,0); val.Text=string.format("%.1fx", SPEED.mul) end
		setSpd((1-0.5)/2.5)
		tr.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dr=true; setSpd((i.Position.X-tr.AbsolutePosition.X)/tr.AbsoluteSize.X) end end)
		UIS_.InputChanged:Connect(function(i) if dr and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then setSpd((i.Position.X-tr.AbsolutePosition.X)/tr.AbsoluteSize.X) end end)
		UIS_.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dr=false end end)
	end
	do -- cursor mode
		local r = new("Frame", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,40), LayoutOrder=11.85, ZIndex=58, Parent=secWindow })
		skinTag(new("TextLabel", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,15), Font=T.Font, Text="Cursor", TextColor3=T.SubText, TextSize=12, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=58, Parent=r }), "sub")
		local row = new("Frame", { BackgroundTransparency=1, Position=UDim2.new(0,0,0,19), Size=UDim2.new(1,0,0,21), ZIndex=58, Parent=r })
		new("UIListLayout", { FillDirection=Enum.FillDirection.Horizontal, SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,5), Parent=row })
		local btns = {}
		for idx, m in ipairs({ {"Free","free"}, {"Game","keep"} }) do
			local b = new("TextButton", { Name="CurBtn", LayoutOrder=idx, BackgroundColor3=T.Element, BorderSizePixel=0, Size=UDim2.new(0.5,-3,1,0), Font=T.FontMed, Text=m[1], TextColor3=T.SubText, TextSize=11, AutoButtonColor=false, ZIndex=58, Parent=row })
			corner(b, 5); skinTag(b, "element")
			table.insert(btns, { id=m[2], btn=b })
			b.MouseButton1Click:Connect(function()
				Window._mouseMode = m[2]
				if Window._syncMouse then Window:_syncMouse() end
				for _, e in ipairs(btns) do
					local on = (e.id == m[2])
					e.btn.Name = on and "AF" or "CurBtn"
					TweenService:Create(e.btn, E_FAST, { TextColor3 = on and Window._accent or T.SubText }):Play()
				end
			end)
		end
		task.defer(function()
			local want = (Window._mouseMode == "keep") and 2 or 1
			local d = btns[want] and btns[want].btn
			if d then d.Name = "AF"; d.TextColor3 = Window._accent end
		end)
	end
	setHost = secKeys
	setKeybindRow("Panic key (kill UI)", config.PanicKey, function(k) Window._panicKey = k end, 11.9, "Panic")
	setHost = secWindow

	do
		local r = new("Frame", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,28), LayoutOrder=12, ZIndex=58, Parent=secConfig })
		local btn = new("TextButton", { BackgroundColor3=T.Element, BorderSizePixel=0, Size=UDim2.new(1,0,1,0), Font=T.FontMed, Text="Reset all values", TextColor3=T.SubText, TextSize=12, AutoButtonColor=false, ZIndex=58, Parent=r }); corner(btn, 5)
		btn.MouseEnter:Connect(function() tween(btn, E_FAST, { BackgroundColor3=T.ElementHov }) end)
		btn.MouseLeave:Connect(function() tween(btn, E_FAST, { BackgroundColor3=T.Element }) end)
		btn.MouseButton1Click:Connect(function()
			if Window._defaults then Window:Snapshot("reset"); Window:LoadConfig(Window._defaults, true); Window:Notify("Values reset", { Type="success", Duration=2 }) end
		end)
	end
	task.spawn(function()
		local hh = 0
		while alive() do
			if Window._rainbow then
				hh = (hh + 0.0022) % 1
				aLo = Color3.fromHSV(hh, 0.55, 1); aHi = Color3.fromHSV((hh+0.08)%1, 0.8, 0.92); Window._accent = aLo
				local at = Window._accentText and Color3.new(aLo.R*0.62, aLo.G*0.5, aLo.B*0.78) or aLo
				applyAccent(aLo, aHi, at)
				for _,fn in ipairs(Window._recolor) do pcall(fn) end
			end
			task.wait(0.03)
		end
	end)
	do
		local lay = setPanel:FindFirstChildOfClass("UIListLayout")
		local function fit()
			local content = lay.AbsoluteContentSize.Y + 24
			setPanel.Size = UDim2.new(0, 238, 0, math.min(content, math.max(160, base.AbsoluteSize.Y - 56)))
		end
		lay:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fit)
		base:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		setPanel:GetPropertyChangedSignal("Visible"):Connect(function() if setPanel.Visible then fit() end end)
		task.defer(fit)
	end
	Window.SettingsPanel = setPanel
	local function toggleSettings() setPanel.Visible = not setPanel.Visible end
	local setBtn = new("TextButton", { BackgroundTransparency=1, BorderSizePixel=0, AnchorPoint=Vector2.new(1,0.5), Position=UDim2.new(1,-74,0.5,0), Size=UDim2.new(0,26,0,26), Text="", AutoButtonColor=false, ZIndex=3, Parent=top })
	corner(setBtn, 5)
	local gearIco = new("Frame", { BackgroundTransparency=1, AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.fromScale(0.5,0.5), Size=UDim2.new(0,15,0,12), ZIndex=3, Parent=setBtn })
	local gparts = {}
	for r=0,2 do
		local ln = new("Frame", { BackgroundColor3=T.Muted, BorderSizePixel=0, Position=UDim2.new(0,0,0,r*5), Size=UDim2.new(1,0,0,2), ZIndex=3, Parent=gearIco }); corner(ln,1); table.insert(gparts, ln); table.insert(Window._recolor, function() ln.BackgroundColor3 = T.Muted end)
		local kn = new("Frame", { BackgroundColor3=T.Muted, BorderSizePixel=0, AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.new(r==1 and 0.7 or 0.3,0,0,r*5+1), Size=UDim2.new(0,4,0,4), ZIndex=4, Parent=gearIco }); corner(kn,2); table.insert(gparts, kn); table.insert(Window._recolor, function() kn.BackgroundColor3 = T.Muted end)
	end
	setBtn.MouseEnter:Connect(function() for _,p in ipairs(gparts) do tween(p,E_FAST,{BackgroundColor3=T.Text}) end end)
	setBtn.MouseLeave:Connect(function() for _,p in ipairs(gparts) do tween(p,E_FAST,{BackgroundColor3=T.Muted}) end end)
	setBtn.MouseButton1Click:Connect(toggleSettings)
	
	
	

	local function playLoader(done)
		base.Visible = false; watermark.Visible = false
		local ov = new("Frame", { Name="Loader", BackgroundColor3=T.Base, BorderSizePixel=0, Size=UDim2.new(1,0,1,0), BackgroundTransparency=1, ZIndex=80, Parent=gui })
		bgGrad(ov, Color3.fromRGB(18,18,24), Color3.fromRGB(10,10,14))
		tween(ov, E_OUT, { BackgroundTransparency=0.1 })
		local bx = new("Frame", { BackgroundTransparency=1, AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.fromScale(0.5,0.5), Size=UDim2.new(0,180,0,96), ZIndex=81, Parent=ov })
		local ic = new("ImageLabel", { BackgroundTransparency=1, AnchorPoint=Vector2.new(0.5,0), Position=UDim2.new(0.5,0,0,0), Size=UDim2.new(0,0,0,0), Image=config.Icon or DEFAULT_ICON, ImageColor3=Color3.new(1,1,1), ZIndex=81, Parent=bx })
		local ag = accentGrad(ic); ag.Rotation=45
		local title = new("TextLabel", { BackgroundTransparency=1, Position=UDim2.new(0,0,0,50), Size=UDim2.new(1,0,0,22), Font=T.FontBold, Text="AZURITE", TextColor3=T.Text, TextSize=18, TextTransparency=1, ZIndex=81, Parent=bx })
		local barBg = new("Frame", { BackgroundColor3=T.Off, BorderSizePixel=0, AnchorPoint=Vector2.new(0.5,0), Position=UDim2.new(0.5,0,0,80), Size=UDim2.new(0,120,0,3), BackgroundTransparency=1, ZIndex=81, Parent=bx }); corner(barBg,2)
		local barFill = new("Frame", { BackgroundColor3=Color3.new(1,1,1), BorderSizePixel=0, Size=UDim2.new(0,0,1,0), ZIndex=81, Parent=barBg }); corner(barFill,2); accentGrad(barFill,0)
		tween(ic, E_POP, { Size=UDim2.new(0,42,0,42) }); tween(ic, TweenInfo.new(0.85,Enum.EasingStyle.Quint,Enum.EasingDirection.Out), { Rotation=360 })
		task.wait(0.15); tween(title, E_SMOO, { TextTransparency=0 }); tween(barBg, E_FAST, { BackgroundTransparency=0 })
		tween(barFill, TweenInfo.new(0.9, Enum.EasingStyle.Quad), { Size=UDim2.new(1,0,1,0) })
		task.wait(1.05)
		tween(ic, E_FAST, { ImageTransparency=1 }); tween(title, E_FAST, { TextTransparency=1 })
		tween(barBg, E_FAST, { BackgroundTransparency=1 }); tween(barFill, E_FAST, { BackgroundTransparency=1 }); tween(ov, E_FAST, { BackgroundTransparency=1 })
		task.wait(0.22); ov:Destroy()
		watermark.Visible = (config.Watermark ~= false)
		done()
	end

		-- === Keybind list (floating) ===
	local kbList = new("Frame", { Name="KeybindList", BackgroundColor3=T.Base, BorderSizePixel=0, Position=UDim2.new(0,14,0,50), Size=UDim2.new(0,262,0,80), Visible=false, ZIndex=46, Parent=gui })
	corner(kbList, 8); bgGrad(kbList, Color3.fromRGB(25,25,31), Color3.fromRGB(13,13,17)); skinTag(kbList, "float")
	local kbShadow = new("ImageLabel", { BackgroundTransparency=1, AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.fromScale(0.5,0.5), Size=UDim2.new(1,36,1,36), ZIndex=45, Image=SHADOW_IMG, ImageColor3=Color3.new(0,0,0), ImageTransparency=0.5, ScaleType=Enum.ScaleType.Slice, SliceCenter=Rect.new(49,49,450,450), Parent=kbList })
	table.insert(Window._recolor, function() kbShadow.ImageTransparency = (Window._skin=="light") and 0.86 or 0.5 end)
	local kbBar = new("Frame", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,30), ZIndex=46, Parent=kbList })
	local kbAcc = new("Frame", { BackgroundColor3=Color3.new(1,1,1), BorderSizePixel=0, Position=UDim2.new(0,11,0.5,-6), Size=UDim2.new(0,3,0,12), ZIndex=46, Parent=kbBar }); corner(kbAcc,2); accentGrad(kbAcc)
	new("TextLabel", { BackgroundTransparency=1, Position=UDim2.new(0,20,0,0), Size=UDim2.new(1,-30,1,0), Name="AF", Font=T.FontBold, Text="Keybind list", TextColor3=aLo, TextSize=12, TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd, ZIndex=46, Parent=kbBar })
	skinTag(new("Frame", { BackgroundColor3=T.StrokeSub, BorderSizePixel=0, Position=UDim2.new(0,10,0,30), Size=UDim2.new(1,-20,0,1), ZIndex=46, Parent=kbList }), "sep")
	local kbHead = new("Frame", { BackgroundTransparency=1, Position=UDim2.new(0,11,0,35), Size=UDim2.new(1,-22,0,15), ZIndex=46, Parent=kbList })
	skinTag(new("TextLabel", { BackgroundTransparency=1, Size=UDim2.new(0.48,0,1,0), Font=T.Font, Text="Function", TextColor3=T.Muted, TextSize=10, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=46, Parent=kbHead }), "muted")
	skinTag(new("TextLabel", { BackgroundTransparency=1, Position=UDim2.new(0.5,0,0,0), Size=UDim2.new(0.28,0,1,0), Font=T.Font, Text="Key", TextColor3=T.Muted, TextSize=10, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=46, Parent=kbHead }), "muted")
	skinTag(new("TextLabel", { BackgroundTransparency=1, Position=UDim2.new(0.78,0,0,0), Size=UDim2.new(0.22,0,1,0), Font=T.Font, Text="Mode", TextColor3=T.Muted, TextSize=10, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=46, Parent=kbHead }), "muted")
	local kbRows = new("ScrollingFrame", { BackgroundTransparency=1, BorderSizePixel=0, Position=UDim2.new(0,11,0,54), Size=UDim2.new(1,-22,0,0), CanvasSize=UDim2.new(), AutomaticCanvasSize=Enum.AutomaticSize.Y, ScrollBarThickness=0, ScrollingDirection=Enum.ScrollingDirection.Y, ZIndex=46, Parent=kbList })
	do
		local lay
		task.defer(function()
			lay = kbRows:FindFirstChildOfClass("UIListLayout")
			if not lay then return end
			local function fit()
				local h = math.min(lay.AbsoluteContentSize.Y + 12, 260)
				kbRows.Size = UDim2.new(1,-22,0,h)
				kbList.Size = UDim2.new(0,262,0,h + 66)
			end
			lay:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fit); fit()
		end)
	end
	new("UIListLayout", { SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,3), Parent=kbRows })
	new("UIPadding", { PaddingBottom=UDim.new(0,10), Parent=kbRows })
	Window.KeybindList = kbList
	Window._hideKeybinds = false
	do
		local dragging, ds, sp2 = false, nil, nil
		kbBar.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=true; ds=i.Position; sp2=kbList.Position end end)
		local kbGoal = kbList.Position
		UIS_.InputChanged:Connect(function(i) if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then local d=i.Position-ds; kbGoal=UDim2.new(0, sp2.X.Offset+d.X, 0, sp2.Y.Offset+d.Y) end end)
		game:GetService("RunService").RenderStepped:Connect(function(dt)
			if dragging then
				local px = kbList.Position.X.Offset
				kbList.Position = kbList.Position:Lerp(kbGoal, math.clamp(dt*16,0,1))
				kbList.Rotation = math.clamp((kbList.Position.X.Offset-px)*0.12, -2.5, 2.5)
			elseif kbList.Rotation ~= 0 then kbList.Rotation = (math.abs(kbList.Rotation) < 0.05) and 0 or kbList.Rotation * 0.8 end
		end)
		UIS_.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=false end end)
	end
	local kbScale = new("UIScale", { Scale=1, Parent=kbList })
	function Window:_addBind(name, el, mode)
		name = tostring(name):gsub("%s+key$", "")
		if not Window._hideKeybinds and not kbList.Visible then kbList.Visible = true; kbScale.Scale=0.85; tween(kbScale, E_POP, {Scale=1}) end
		local row = new("Frame", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,16), ZIndex=46, Parent=kbRows })
		skinTag(new("TextLabel", { BackgroundTransparency=1, Size=UDim2.new(0.48,0,1,0), Font=T.FontMed, Text=name, TextColor3=T.SubText, TextSize=11, TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd, ZIndex=46, Parent=row }), "sub")
		local kv = new("TextLabel", { BackgroundTransparency=1, Position=UDim2.new(0.5,0,0,0), Size=UDim2.new(0.28,0,1,0), Font=T.FontMed, Text="None", TextColor3=T.Text, TextSize=11, TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd, ZIndex=46, Parent=row }); skinTag(kv, "text")
		local isSys = (mode == "System")
		local mlProps = { Name=isSys and "Sys" or "AF", BackgroundTransparency=1, Position=UDim2.new(0.78,0,0,0), Size=UDim2.new(0.22,0,1,0), Font=T.Font, Text=mode or "Toggle", TextColor3=isSys and T.Muted or aLo, TextSize=11, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=46, Parent=row }
		if not isSys then mlProps.AutoButtonColor = false end
		local ml = new(isSys and "TextLabel" or "TextButton", mlProps)
		if isSys then skinTag(ml, "muted")
		else
			ml.Text = el.Mode or "Toggle"
			el._modeSync = function(m) ml.Text = m end
			ml.MouseButton1Click:Connect(function()
				if el.AskMode then el.AskMode() elseif el.SetMode then el:SetMode("Toggle") end
			end)
		end
		row.LayoutOrder = (mode=="System") and 100 or 1
		task.spawn(function()
			while alive() and not row:GetAttribute("Dead") do
				local k = el.Value
				if k and typeof(k) == "EnumItem" and k.EnumType == Enum.UserInputType then
					local m = { MouseButton1="MB1", MouseButton2="MB2", MouseButton3="MB3" }
					kv.Text = m[k.Name] or k.Name
				else
					kv.Text = k and (k.Name:gsub("Right","R"):gsub("Left","L"):gsub("Control","Ctrl")) or "None"
				end
				row.Visible = (mode == "System") or (k ~= nil)
				if el.Mode and ml and ml:IsA("TextButton") then ml.Text = el.Mode end
				task.wait(0.4)
			end
		end)
	end
	for _, pb in ipairs(Window._pendingBinds or {}) do Window:_addBind(pb[1], pb[2], pb[3]) end
	Window._pendingBinds = {}
	setToggleRow("Hide keybind list", false, function(v) Window._hideKeybinds = v; kbList.Visible = (not v) and (#kbRows:GetChildren() > 2) end, 7)
	do
		local cmds, cmdOrder = {}, {}
		local cbar = new("Frame", { Name="CommandBar", BackgroundColor3=Color3.new(0,0,0), BackgroundTransparency=1, Size=UDim2.new(1,0,1,0), Visible=false, ZIndex=97, Parent=gui })
		local cbox = new("Frame", { BackgroundColor3=T.Base, BorderSizePixel=0, AnchorPoint=Vector2.new(0.5,1), Position=UDim2.new(0.5,0,0.88,0), Size=UDim2.new(0,520,0,42), AutomaticSize=Enum.AutomaticSize.Y, ZIndex=98, Parent=cbar })
		corner(cbox, 10); bgGrad(cbox, Color3.fromRGB(27,27,34), Color3.fromRGB(15,15,20))
		local caret = new("Frame", { BackgroundColor3=Color3.new(1,1,1), BorderSizePixel=0, Position=UDim2.new(0,13,0,15), Size=UDim2.new(0,3,0,14), ZIndex=99, Parent=cbox }); corner(caret,2); accentGrad(caret)
		local cin = new("TextBox", { BackgroundTransparency=1, Position=UDim2.new(0,26,0,0), Size=UDim2.new(1,-40,0,42), Font=T.FontMed, Text="", PlaceholderText="Type a command...", PlaceholderColor3=T.Muted, TextColor3=T.Text, TextSize=14, TextXAlignment=Enum.TextXAlignment.Left, ClearTextOnFocus=false, ZIndex=99, Parent=cbox })
		local hint = new("TextLabel", { BackgroundTransparency=1, Position=UDim2.new(0,26,0,42), Size=UDim2.new(1,-40,0,0), Font=T.Font, Text="", TextColor3=T.Muted, TextSize=11, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=99, Parent=cbox })
		local sug = new("ScrollingFrame", { BackgroundTransparency=1, BorderSizePixel=0, Position=UDim2.new(0,8,0,44), Size=UDim2.new(1,-16,0,0), CanvasSize=UDim2.new(), AutomaticCanvasSize=Enum.AutomaticSize.Y, ScrollBarThickness=2, ScrollBarImageColor3=T.Muted, ScrollBarImageTransparency=0.4, ScrollingDirection=Enum.ScrollingDirection.Y, ZIndex=99, Parent=cbox })
		new("UIListLayout", { SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,2), Parent=sug })
		new("UIPadding", { PaddingBottom=UDim.new(0,8), Parent=sug })

		local function argSig(c)
			local out = {}
			for _, a in ipairs(c.Args or {}) do table.insert(out, a.Optional and ("["..a.Name.."]") or ("<"..a.Name..">")) end
			return table.concat(out, " ")
		end
		local function parse(str)
			local parts = {}
			for w in str:gmatch("%S+") do table.insert(parts, w) end
			return parts
		end
		local function coerce(v, t)
			if t=="number" then return tonumber(v)
			elseif t=="bool" then local l=v:lower(); return (l=="true" or l=="1" or l=="yes" or l=="on")
			elseif t=="player" then
				local lv=v:lower()
				for _, p in ipairs(Players:GetPlayers()) do if p.Name:lower():sub(1,#lv)==lv or p.DisplayName:lower():sub(1,#lv)==lv then return p end end
				return nil
			end
			return v
		end
		local function fitSug()
			task.defer(function()
				local lay = sug:FindFirstChildOfClass("UIListLayout")
				sug.Size = UDim2.new(1,-16,0, math.min((lay and lay.AbsoluteContentSize.Y or 0) + 8, 220))
			end)
		end
		local function refreshSug()
			for _, c in ipairs(sug:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
			fitSug()
			local parts = parse(cin.Text)
			local head = (parts[1] or ""):lower()
			local exact = cmds[head]
			if exact and (#parts > 1 or cin.Text:sub(-1)==" ") then
				local sig = argSig(exact)
				hint.Text = ("%s %s   %s"):format(head, sig, exact.Description or "")
				hint.Size = UDim2.new(1,-40,0,16); sug.Position = UDim2.new(0,8,0,60); fitSug()
				return
			end
			hint.Text = ""; hint.Size = UDim2.new(1,-40,0,0); sug.Position = UDim2.new(0,8,0,44); fitSug()
			local n = 0
			for _, name in ipairs(cmdOrder) do
				local c = cmds[name]
				if n < 5 and (head=="" or name:sub(1,#head)==head) then
					n += 1
					local row = new("TextButton", { BackgroundColor3=T.Element, BackgroundTransparency=0.25, BorderSizePixel=0, Size=UDim2.new(1,0,0,28), Font=T.FontMed, Text="   "..name.." ", TextColor3=T.Text, TextSize=12, TextXAlignment=Enum.TextXAlignment.Left, AutoButtonColor=false, ZIndex=99, Parent=sug }); corner(row,6)
					new("TextLabel", { Name="AF", BackgroundTransparency=1, Position=UDim2.new(0,20+#name*7.5,0,0), Size=UDim2.new(0,200,1,0), Font=T.Font, Text=argSig(c), TextColor3=Window._accent, TextSize=11, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=99, Parent=row })
					new("TextLabel", { BackgroundTransparency=1, AnchorPoint=Vector2.new(1,0.5), Position=UDim2.new(1,-10,0.5,0), Size=UDim2.new(0.5,0,1,0), Font=T.Font, Text=c.Description or "", TextColor3=T.Muted, TextSize=11, TextXAlignment=Enum.TextXAlignment.Right, TextTruncate=Enum.TextTruncate.AtEnd, ZIndex=99, Parent=row })
					row.MouseEnter:Connect(function() tween(row, E_FAST, { BackgroundTransparency=0 }) end)
					row.MouseLeave:Connect(function() tween(row, E_FAST, { BackgroundTransparency=0.25 }) end)
					local nm = name
					row.MouseButton1Click:Connect(function() cin.Text = nm.." "; cin:CaptureFocus(); cin.CursorPosition = #cin.Text+1 end)
				end
			end
		end
		local function runCommand(str)
			local parts = parse(str)
			local name = (parts[1] or ""):lower()
			local c = cmds[name]
			if not c then Window:Notify("Unknown command: "..name, { Type="error", Duration=2.5 }); return end
			local args, ok = {}, true
			for idx, a in ipairs(c.Args or {}) do
				local raw = parts[idx+1]
				if raw == nil then
					if a.Optional then args[a.Name] = a.Default
					else Window:Notify(("Missing argument <%s>"):format(a.Name), { Type="warning", Duration=2.5 }); ok=false; break end
				else
					local v = coerce(raw, a.Type or "string")
					if v == nil then Window:Notify(("Bad value for <%s>"):format(a.Name), { Type="error", Duration=2.5 }); ok=false; break end
					args[a.Name] = v
				end
			end
			if ok then local s2, e = pcall(c.Callback, args, str); if not s2 then Window:Notify("Command error: "..tostring(e), { Type="error", Duration=3 }) end end
		end
		function Window:Command(name, opts)
			name = name:lower(); opts = opts or {}
			cmds[name] = { Args=opts.Args, Description=opts.Description, Callback=opts.Callback or function() end }
			table.insert(cmdOrder, name); table.sort(cmdOrder)
			return cmds[name]
		end
		Window._cmdKey = config.CommandKey or Enum.KeyCode.Semicolon
		Window._cmdOpenedAt = 0
		function Window:CloseCommandBar()
			cbar.Visible = false
			if cin:IsFocused() then cin:ReleaseFocus(false) end
		end
		function Window:OpenCommandBar()
			Window._cmdOpenedAt = os.clock()
			cbar.Visible = true; cin.Text=""; refreshSug()
			cbox.Position = UDim2.new(0.5,0,0.9,0); tween(cbox, E_POP, { Position=UDim2.new(0.5,0,0.88,0) })
			tween(cbar, E_OUT, { BackgroundTransparency=0.55 })
			task.spawn(function()
				game:GetService("RunService").RenderStepped:Wait()
				game:GetService("RunService").RenderStepped:Wait()
				if not cbar.Visible then return end
				cin:CaptureFocus()
				-- the key that opened the bar can still land in the field: scrub it for a few frames
				for _ = 1, 6 do
					cin.Text = ""; cin.CursorPosition = 1
					game:GetService("RunService").RenderStepped:Wait()
				end
				cin.CursorPosition = 1
			end)
		end
		cin.FocusLost:Connect(function(enter)
			local t = cin.Text
			cbar.Visible = false
			if enter and t ~= "" then runCommand(t) end
		end)
		cin:GetPropertyChangedSignal("Text"):Connect(refreshSug)
		new("TextButton", { BackgroundTransparency=1, Size=UDim2.new(1,0,1,0), Text="", ZIndex=97, Parent=cbar }).MouseButton1Click:Connect(function() Window:CloseCommandBar() end)
		UIS_.InputEnded:Connect(function(i)
			if i.UserInputType ~= Enum.UserInputType.Keyboard then return end
			if not (Window._MODKEY and Window._MODKEY[i.KeyCode]) then return end
			if i.KeyCode ~= Window._cmdKey then return end
			if Window._comboUsed and Window._comboUsed[i.KeyCode] then return end
			if cbar.Visible then Window:CloseCommandBar() else task.spawn(function() Window:OpenCommandBar() end) end
		end)
		UIS_.InputBegan:Connect(function(i, p)
			if i.KeyCode ~= Window._cmdKey then return end
			if Window._MODKEY and Window._MODKEY[i.KeyCode] then return end   -- handled on release
			if Window._ctrlDown() then return end
			if cbar.Visible then
				if os.clock() - Window._cmdOpenedAt > 0.25 then Window:CloseCommandBar() end
				return
			end
			if p then return end
			task.spawn(function() Window:OpenCommandBar() end)
		end)
		-- built-ins so it's useful out of the box
		Window:Command("theme", { Description="change accent color", Args={{Name="preset", Type="number", Optional=true, Default=1}}, Callback=function(a)
			local p = presets[math.clamp(math.floor(a.preset),1,#presets)]
			aLo,aHi = p[1],p[2]; Window._accent=aLo; Window._rainbow=false
			applyAccent(aLo, aHi, Window._accentText and Color3.new(aLo.R*0.62, aLo.G*0.5, aLo.B*0.78) or aLo)
			for _,fn in ipairs(Window._recolor) do pcall(fn) end
		end })
		Window:Command("scale", { Description="set menu scale", Args={{Name="percent", Type="number"}}, Callback=function(a) uiScale.Scale = math.clamp(a.percent/100, 0.6, 1.6) end })
		Window:Command("rainbow", { Description="toggle rainbow accent", Args={{Name="state", Type="bool", Optional=true}}, Callback=function(a) Window._rainbow = (a.state == nil) and (not Window._rainbow) or a.state end })
		Window:Command("watermark", { Description="show/hide watermark", Args={{Name="state", Type="bool", Optional=true}}, Callback=function(a) watermark.Visible = (a.state == nil) and (not watermark.Visible) or a.state end })
		Window:Command("reset", { Description="reset all values", Callback=function() if Window._defaults then Window:LoadConfig(Window._defaults); Window:Notify("Values reset", {Type="success", Duration=2}) end end })
		Window:Command("save", { Description="save a config profile", Args={{Name="name", Type="string", Optional=true, Default="default"}}, Callback=function(a) Window:SaveProfile(a.name) end })
		Window:Command("load", { Description="load a config profile", Args={{Name="name", Type="string", Optional=true, Default="default"}}, Callback=function(a) Window:LoadProfile(a.name) end })
		Window:Command("profiles", { Description="list saved profiles", Callback=function()
			local l = Window:ListProfiles()
			Window:Notify(#l>0 and table.concat(l, ", ") or "no profiles", { Title="Profiles", Duration=4 })
		end })
		Window:Command("opacity", { Description="window opacity 45-100", Args={{Name="percent", Type="number"}}, Callback=function(a)
			local t = 1 - math.clamp((a.percent-45)/55, 0, 1)
			base.BackgroundTransparency = t*0.55; top.BackgroundTransparency = t*0.55; side.BackgroundTransparency = t*0.55
		end })
		Window:Command("blur", { Description="toggle background blur", Args={{Name="state", Type="bool", Optional=true}}, Callback=function(a)
			Window._blurWanted = (a.state == nil) and (not Window._blurWanted) or a.state
			if Window._syncBlur then Window:_syncBlur() end
		end })
		Window:Command("fixblur", { Description="clear stuck blur", Callback=function() if Window.FixBlur then Window:FixBlur() end end })
		Window:Command("cursor", { Description="free / game", Args={{Name="mode", Type="string", Optional=true, Default="free"}}, Callback=function(a)
			Window._mouseMode = (a.mode:lower()=="game" or a.mode:lower()=="keep") and "keep" or "free"
			if Window._syncMouse then Window:_syncMouse() end
			Window:Notify("Cursor: "..Window._mouseMode, { Type="success", Duration=2 })
		end })
		Window:Command("skin", { Description="dark / light / glass", Args={{Name="name", Type="string", Optional=true, Default="dark"}}, Callback=function(a)
			local n = a.name:lower(); if n=="glass" then n="transparent" end
			Window:SetSkin(n); Window:Notify("Skin: "..n, { Type="success", Duration=2 })
		end })
		Window:Command("close", { Description="close azurite", Callback=function() Window:Exit() end })
	end

	do
		local pal = new("Frame", { Name="Palette", BackgroundColor3=Color3.new(0,0,0), BackgroundTransparency=1, Size=UDim2.new(1,0,1,0), Visible=false, ZIndex=95, Parent=gui })
		local pbox = new("Frame", { BackgroundColor3=T.Base, BorderSizePixel=0, AnchorPoint=Vector2.new(0.5,0), Position=UDim2.new(0.5,0,0.22,0), Size=UDim2.new(0,420,0,44), AutomaticSize=Enum.AutomaticSize.Y, ZIndex=96, Parent=pal })
		corner(pbox, 10); bgGrad(pbox, Color3.fromRGB(26,26,33), Color3.fromRGB(15,15,20))
		local pin = new("TextBox", { BackgroundTransparency=1, Position=UDim2.new(0,16,0,0), Size=UDim2.new(1,-32,0,44), Font=T.FontMed, Text="", PlaceholderText="Jump to...", PlaceholderColor3=T.Muted, TextColor3=T.Text, TextSize=14, TextXAlignment=Enum.TextXAlignment.Left, ClearTextOnFocus=false, ZIndex=96, Parent=pbox })
		local plist = new("ScrollingFrame", { BackgroundTransparency=1, BorderSizePixel=0, Position=UDim2.new(0,8,0,44), Size=UDim2.new(1,-16,0,0), CanvasSize=UDim2.new(), AutomaticCanvasSize=Enum.AutomaticSize.Y, ScrollBarThickness=2, ScrollBarImageColor3=T.Muted, ScrollBarImageTransparency=0.4, ScrollingDirection=Enum.ScrollingDirection.Y, ZIndex=96, Parent=pbox })
		new("UIListLayout", { SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,2), Parent=plist })
		new("UIPadding", { PaddingBottom=UDim.new(0,8), Parent=plist })
		local function refreshPal()
			for _, c in ipairs(plist:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
			task.defer(function()
				local lay = plist:FindFirstChildOfClass("UIListLayout")
				plist.Size = UDim2.new(1,-16,0, math.min((lay and lay.AbsoluteContentSize.Y or 0) + 8, 260))
			end)
			local q = pin.Text:lower(); local n = 0
			for _, c in ipairs(Window.Categories) do
				for _, g in ipairs(c._groups) do
					for _, it in ipairs(g.items) do
						if it.title and n < 6 and (q=="" or it.title:lower():find(q,1,true)) then
							n += 1
							local row = new("TextButton", { BackgroundColor3=T.Element, BackgroundTransparency=0.25, BorderSizePixel=0, Size=UDim2.new(1,0,0,30), Font=T.Font, Text="   "..it.title, TextColor3=T.SubText, TextSize=12, TextXAlignment=Enum.TextXAlignment.Left, AutoButtonColor=false, ZIndex=96, Parent=plist }); corner(row, 6)
							new("TextLabel", { Name="AF", BackgroundTransparency=1, AnchorPoint=Vector2.new(1,0.5), Position=UDim2.new(1,-10,0.5,0), Size=UDim2.new(0,120,1,0), Font=T.Font, Text=c.Name, TextColor3=Window._accent, TextSize=11, TextXAlignment=Enum.TextXAlignment.Right, ZIndex=96, Parent=row })
							row.MouseEnter:Connect(function() tween(row, E_FAST, { BackgroundTransparency=0 }) end)
							row.MouseLeave:Connect(function() tween(row, E_FAST, { BackgroundTransparency=0.25 }) end)
							local cc, ttl = c, it.title
							row.MouseButton1Click:Connect(function()
								pal.Visible=false; cc.Select()
								if searchBox then searchBox.Text = ttl end
							end)
						end
					end
				end
			end
		end
		pin:GetPropertyChangedSignal("Text"):Connect(refreshPal)
		UIS_.InputBegan:Connect(function(i, p)
			if i.KeyCode==Enum.KeyCode.Z and Window._ctrlDown() and Window.Open and not Window._typing then
				Window:Undo()
			end
			if i.KeyCode==Enum.KeyCode.F and Window._ctrlDown() and Window.Open and not Window._typing and Window._searchBox then
				task.defer(function() Window._searchBox:CaptureFocus() end)
			end
			if i.KeyCode==Enum.KeyCode.K and Window._ctrlDown() and Window.Open and not Window._typing then
				pal.Visible = not pal.Visible
				if pal.Visible then pin.Text=""; refreshPal(); pbox.Size=UDim2.new(0,390,0,44); tween(pbox, E_POP, { Size=UDim2.new(0,420,0,44) }); tween(pal, E_OUT, { BackgroundTransparency=0.5 }); task.wait(0.05); pin:CaptureFocus() end
			elseif i.KeyCode==Enum.KeyCode.Escape and pal.Visible then pal.Visible=false end
		end)
		new("TextButton", { BackgroundTransparency=1, Size=UDim2.new(1,0,1,0), Text="", ZIndex=95, Parent=pal }).MouseButton1Click:Connect(function() pal.Visible=false end)
	end

	-- ===== PLAYER LIST (floating, draggable, live) =====
	function Window:PlayerList(opts)
		opts = opts or {}
		if Window._plistAPI then
			local api = Window._plistAPI
			if opts.Title and api.SetTitle then api:SetTitle(opts.Title) end
			if opts.OnSelect then api._onSelect = opts.OnSelect end
			if opts.OnRightClick then api._onRightClick = opts.OnRightClick end
			return api
		end
		local ROW_H, MAX_H = 34, opts.MaxHeight or 320
		local pl = new("Frame", { Name="PlayerList", BackgroundColor3=T.Base, BorderSizePixel=0, Position=opts.Position or UDim2.new(1,-278,0,54), Size=UDim2.new(0,262,0,120), Visible=true, ZIndex=44, Parent=gui })
		corner(pl, 8); bgGrad(pl, Color3.fromRGB(25,25,31), Color3.fromRGB(13,13,17)); skinTag(pl, "float")
		Window._plist = pl
		local bar = new("Frame", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,30), ZIndex=44, Parent=pl })
		local acc = new("Frame", { BackgroundColor3=Color3.new(1,1,1), BorderSizePixel=0, Position=UDim2.new(0,11,0.5,-6), Size=UDim2.new(0,3,0,12), ZIndex=44, Parent=bar }); corner(acc,2); accentGrad(acc)
		new("TextLabel", { Name="AF", BackgroundTransparency=1, Position=UDim2.new(0,20,0,0), Size=UDim2.new(1,-56,1,0), Font=T.FontBold, Text=opts.Title or "Players", TextColor3=aLo, TextSize=12, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=44, Parent=bar })
		local count = new("TextLabel", { BackgroundTransparency=1, AnchorPoint=Vector2.new(1,0.5), Position=UDim2.new(1,-11,0.5,0), Size=UDim2.new(0,44,1,0), Font=T.Font, Text="0", TextColor3=T.Muted, TextSize=11, TextXAlignment=Enum.TextXAlignment.Right, ZIndex=44, Parent=bar })
		skinTag(count, "muted")

		skinTag(new("Frame", { BackgroundColor3=T.StrokeSub, BorderSizePixel=0, Position=UDim2.new(0,10,0,30), Size=UDim2.new(1,-20,0,1), ZIndex=44, Parent=pl }), "sep")
		-- search field so 100-player servers stay usable
		local sf = new("Frame", { BackgroundColor3=T.Element, BorderSizePixel=0, Position=UDim2.new(0,10,0,37), Size=UDim2.new(1,-20,0,24), ZIndex=44, Parent=pl })
		corner(sf, 5); skinTag(sf, "element")
		local pSearch = new("TextBox", { BackgroundTransparency=1, Position=UDim2.new(0,9,0,0), Size=UDim2.new(1,-18,1,0), Font=T.Font, Text="", PlaceholderText="Filter players...", PlaceholderColor3=T.Muted, TextColor3=T.Text, TextSize=11, TextXAlignment=Enum.TextXAlignment.Left, ClearTextOnFocus=false, ZIndex=44, Parent=sf })
		skinTag(pSearch, "text")
		local rows = new("ScrollingFrame", { BackgroundTransparency=1, BorderSizePixel=0, Position=UDim2.new(0,8,0,68), Size=UDim2.new(1,-16,0,ROW_H), CanvasSize=UDim2.new(), AutomaticCanvasSize=Enum.AutomaticSize.Y, ScrollBarThickness=0, ScrollingDirection=Enum.ScrollingDirection.Y, ZIndex=44, Parent=pl })
		local rowsLayout = new("UIListLayout", { SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,3), Parent=rows })
		new("UIPadding", { PaddingBottom=UDim.new(0,4), Parent=rows })
		do
			local dragging, ds, sp2 = false, nil, nil
			local goal = pl.Position
			bar.InputBegan:Connect(function(i2) if i2.UserInputType==Enum.UserInputType.MouseButton1 or i2.UserInputType==Enum.UserInputType.Touch then dragging=true; ds=i2.Position; sp2=pl.Position end end)
			UIS_.InputChanged:Connect(function(i2) if dragging and (i2.UserInputType==Enum.UserInputType.MouseMovement or i2.UserInputType==Enum.UserInputType.Touch) then local d=i2.Position-ds; goal=UDim2.new(sp2.X.Scale, sp2.X.Offset+d.X, sp2.Y.Scale, sp2.Y.Offset+d.Y) end end)
			UIS_.InputEnded:Connect(function(i2) if i2.UserInputType==Enum.UserInputType.MouseButton1 or i2.UserInputType==Enum.UserInputType.Touch then dragging=false end end)
			game:GetService("RunService").RenderStepped:Connect(function(dt) if dragging then pl.Position = pl.Position:Lerp(goal, math.clamp(dt*16,0,1)) end end)
		end

		local selected, filter = nil, ""
		local marks, actions = {}, {}
		local api = { Frame = pl }
		-- dev API -----------------------------------------------------------
		function api:Mark(player, info)      -- { Color=Color3, Tag="ADMIN", TagColor=Color3, Note="..." }
			local key = (typeof(player)=="Instance") and player.Name or tostring(player)
			marks[key] = info
			if api._rebuild then api._rebuild() end
		end
		function api:Unmark(player)
			local key = (typeof(player)=="Instance") and player.Name or tostring(player)
			marks[key] = nil; if api._rebuild then api._rebuild() end
		end
		function api:AddAction(label, fn)    -- right-click menu entry
			table.insert(actions, { label = label, fn = fn })
		end
		function api:GetSelected() return selected end
		function api:SetTitle(t) for _, d in ipairs(bar:GetChildren()) do if d:IsA("TextLabel") and d.Name == "AF" then d.Text = tostring(t) end end return api end
		function api:SetVisible(v) pl.Visible = v and true or false end
		function api:Refresh() if api._rebuild then api._rebuild() end end
		----------------------------------------------------------------------
		local function fitHeight(n)
			local h = math.clamp(n * (ROW_H + 3), ROW_H, MAX_H)
			rows.Size = UDim2.new(1,-16,0,h)
			pl.Size = UDim2.new(0,262,0, h + 76)
		end
		local function build()
			for _, c in ipairs(rows:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
			local list = {}
			for _, p in ipairs(Players:GetPlayers()) do
				local disp = Window:AnonName(p):lower()
				if filter == "" or disp:find(filter,1,true) or (not Window._anon and (p.Name:lower():find(filter,1,true) or p.DisplayName:lower():find(filter,1,true))) then table.insert(list, p) end
			end
			count.Text = ("%d/%d"):format(#list, #Players:GetPlayers())
			fitHeight(#list)
			for idx, p in ipairs(list) do
				local mk = marks[p.Name] or {}
				local row = new("TextButton", { LayoutOrder=idx, BackgroundColor3=T.Element, BackgroundTransparency=0.4, BorderSizePixel=0, Size=UDim2.new(1,0,0,ROW_H), Text="", AutoButtonColor=false, ZIndex=44, Parent=rows })
				corner(row, 6); skinTag(row, "element")
				local av = new("ImageLabel", { BackgroundColor3=T.Off, BorderSizePixel=0, Position=UDim2.new(0,6,0.5,-11), Size=UDim2.new(0,22,0,22), ZIndex=44, Parent=row }); corner(av, 11)
				if not Window._anon then
					task.spawn(function() local ok2, url = pcall(function() return Players:GetUserThumbnailAsync(p.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100) end); if ok2 then av.Image = url end end)
				end
				local nameLbl = new("TextLabel", { Name = "PName", BackgroundTransparency=1, Position=UDim2.new(0,34,0,3), Size=UDim2.new(1,-100,0,14), Font=T.FontMed, Text=Window:AnonName(p), TextColor3=mk.Color or T.Text, TextSize=12, TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd, ZIndex=44, Parent=row })
				if not mk.Color then skinTag(nameLbl, "text") end
				skinTag(new("TextLabel", { BackgroundTransparency=1, Position=UDim2.new(0,34,0,17), Size=UDim2.new(1,-100,0,13), Font=T.Font, Text=(not Window._anon and mk.Note) or Window:AnonTag(p), TextColor3=T.Muted, TextSize=10, TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd, ZIndex=44, Parent=row }), "muted")
				if mk.Tag then
					local tagCol = mk.TagColor or mk.Color
					local tag = new("TextLabel", { Name = (not tagCol) and "AF" or "Tag", BackgroundColor3=tagCol or Window._accent, BackgroundTransparency=0.85, BorderSizePixel=0, AnchorPoint=Vector2.new(1,0.5), Position=UDim2.new(1,-8,0.5,0), Size=UDim2.new(0,0,0,16), AutomaticSize=Enum.AutomaticSize.X, Font=T.FontMed, Text=mk.Tag, TextColor3=tagCol or Window._accent, TextSize=10, ZIndex=44, Parent=row })
					corner(tag, 4); pad(tag, 0,0,6,6)
					if not tagCol then table.insert(Window._recolor, function() if tag.Parent then tag.BackgroundColor3 = Window._accent end end) end
				else
					local team = new("TextLabel", { BackgroundTransparency=1, AnchorPoint=Vector2.new(1,0.5), Position=UDim2.new(1,-10,0.5,0), Size=UDim2.new(0,64,1,0), Font=T.Font, Text=(p.Team and p.Team.Name) or "-", TextColor3=T.Muted, TextSize=10, TextXAlignment=Enum.TextXAlignment.Right, TextTruncate=Enum.TextTruncate.AtEnd, ZIndex=44, Parent=row })
					skinTag(team, "muted")
				end
				row.MouseEnter:Connect(function() tween(row, E_FAST, { BackgroundTransparency=0 }) end)
				row.MouseLeave:Connect(function() tween(row, E_FAST, { BackgroundTransparency = (selected==p) and 0 or 0.4 }) end)
				row.MouseButton1Click:Connect(function()
					selected = p
					for _, rr in ipairs(rows:GetChildren()) do if rr:IsA("TextButton") then rr.BackgroundTransparency = 0.4 end end
					row.BackgroundTransparency = 0
					local cbSel = api._onSelect or opts.OnSelect
					if cbSel then task.spawn(cbSel, p) end
				end)
				row.MouseButton2Click:Connect(function()
					selected = p
					local items = {}
					if not Window._anon then
						table.insert(items, { "Copy username", function() if setclipboard then pcall(setclipboard, p.Name) end Window:Notify("Copied "..p.Name, { Duration=2 }) end })
						table.insert(items, { "Copy display name", function() if setclipboard then pcall(setclipboard, p.DisplayName) end Window:Notify("Copied "..p.DisplayName, { Duration=2 }) end })
						table.insert(items, { "Copy user id", function() if setclipboard then pcall(setclipboard, tostring(p.UserId)) end Window:Notify("Copied "..p.UserId, { Duration=2 }) end })
					end
					for _, it in ipairs({
						{ "Teleport to", function()
							local me, him = LocalPlayer.Character, p.Character
							if me and him then me:PivotTo(him:GetPivot() * CFrame.new(0,0,3)); Window:Notify("Teleported to "..Window:AnonName(p), { Type="success", Duration=2 })
							else Window:Notify("Character not found", { Type="warning", Duration=2 }) end
						end },
					}) do table.insert(items, it) end
					for _, a in ipairs(actions) do
						table.insert(items, { a.label, function() task.spawn(a.fn, p) end })
					end
					local cbRc = api._onRightClick or opts.OnRightClick
					if cbRc then task.spawn(cbRc, p, items) end
					Window:_showCtx(items)
				end)
			end
		end
		api._rebuild = build
		table.insert(Window._anonRefresh, build)
		build()
		pSearch:GetPropertyChangedSignal("Text"):Connect(function() filter = pSearch.Text:lower(); build() end)
		table.insert(_conns, Players.PlayerAdded:Connect(function() task.defer(build) end))
		table.insert(_conns, Players.PlayerRemoving:Connect(function(p) if selected==p then selected=nil end task.defer(build) end))
		task.spawn(function() while alive() do task.wait(8); if pl.Visible then build() end end end)
		Window._plistAPI = api
		setHost = secWindow
		Window._plistToggle = setToggleRow("Hide player list", false, function(v) pl.Visible = not v end, 7.2)
		return api
	end

	do
		local sc = new("Frame", { Name="Shortcuts", BackgroundColor3=T.Base, BorderSizePixel=0, AnchorPoint=Vector2.new(0,1), Position=UDim2.new(0,14,1,-14), Size=UDim2.new(0,236,0,120), Visible=true, ZIndex=44, Parent=gui })
		corner(sc, 8); bgGrad(sc, Color3.fromRGB(25,25,31), Color3.fromRGB(13,13,17)); skinTag(sc, "float")
		local bar = new("Frame", { BackgroundTransparency=1, Size=UDim2.new(1,0,0,30), ZIndex=44, Parent=sc })
		local acc = new("Frame", { BackgroundColor3=Color3.new(1,1,1), BorderSizePixel=0, Position=UDim2.new(0,11,0.5,-6), Size=UDim2.new(0,3,0,12), ZIndex=44, Parent=bar }); corner(acc,2); accentGrad(acc)
		new("TextLabel", { Name="AF", BackgroundTransparency=1, Position=UDim2.new(0,20,0,0), Size=UDim2.new(1,-56,1,0), Font=T.FontBold, Text="Shortcuts", TextColor3=aLo, TextSize=12, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=44, Parent=bar })

		skinTag(new("Frame", { BackgroundColor3=T.StrokeSub, BorderSizePixel=0, Position=UDim2.new(0,10,0,30), Size=UDim2.new(1,-20,0,1), ZIndex=44, Parent=sc }), "sep")
		local rows = new("ScrollingFrame", { BackgroundTransparency=1, BorderSizePixel=0, Position=UDim2.new(0,8,0,37), Size=UDim2.new(1,-16,0,40), CanvasSize=UDim2.new(), AutomaticCanvasSize=Enum.AutomaticSize.Y, ScrollBarThickness=0, ScrollingDirection=Enum.ScrollingDirection.Y, ZIndex=44, Parent=sc })
		local rowsLay = new("UIListLayout", { SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,3), Parent=rows })
		new("UIPadding", { PaddingBottom=UDim.new(0,4), Parent=rows })
		do
			local dragging, ds, sp2 = false, nil, nil
			local goal = sc.Position
			bar.InputBegan:Connect(function(i2) if i2.UserInputType==Enum.UserInputType.MouseButton1 or i2.UserInputType==Enum.UserInputType.Touch then dragging=true; ds=i2.Position; sp2=sc.Position end end)
			UIS_.InputChanged:Connect(function(i2) if dragging and (i2.UserInputType==Enum.UserInputType.MouseMovement or i2.UserInputType==Enum.UserInputType.Touch) then local d=i2.Position-ds; goal=UDim2.new(sp2.X.Scale, sp2.X.Offset+d.X, sp2.Y.Scale, sp2.Y.Offset+d.Y) end end)
			UIS_.InputEnded:Connect(function(i2) if i2.UserInputType==Enum.UserInputType.MouseButton1 or i2.UserInputType==Enum.UserInputType.Touch then dragging=false end end)
			game:GetService("RunService").RenderStepped:Connect(function(dt) if dragging then sc.Position = sc.Position:Lerp(goal, math.clamp(dt*16,0,1)) end end)
		end
		local entries = {}
		local function fit()
			local h = math.clamp(rowsLay.AbsoluteContentSize.Y + 8, 40, 280)
			rows.Size = UDim2.new(1,-16,0,h)
			sc.Size = UDim2.new(0,236,0,h + 48)
		end
		local function build()
			for _, c in ipairs(rows:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
			for idx, e in ipairs(entries) do
				local row = new("TextButton", { LayoutOrder=idx, BackgroundColor3=T.Element, BackgroundTransparency=0.4, BorderSizePixel=0, Size=UDim2.new(1,0,0,28), Text="", AutoButtonColor=false, ZIndex=44, Parent=rows })
				corner(row, 6); skinTag(row, "element")
				skinTag(new("TextLabel", { BackgroundTransparency=1, Position=UDim2.new(0,10,0,0), Size=UDim2.new(1,-80,1,0), Font=T.Font, Text=e.label, TextColor3=T.SubText, TextSize=11, TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd, ZIndex=44, Parent=row }), "sub")
				local hintLbl = new("TextLabel", { Name="AF", BackgroundTransparency=1, AnchorPoint=Vector2.new(1,0.5), Position=UDim2.new(1,-10,0.5,0), Size=UDim2.new(0,66,1,0), Font=T.FontMed, Text="", TextColor3=aLo, TextSize=10, TextXAlignment=Enum.TextXAlignment.Right, TextTruncate=Enum.TextTruncate.AtEnd, ZIndex=44, Parent=row })
				if type(e.hint) == "function" then
					task.spawn(function() while alive() and row.Parent do hintLbl.Text = tostring(e.hint() or ""); task.wait(1) end end)
				else hintLbl.Text = tostring(e.hint or "") end
				row.MouseEnter:Connect(function() tween(row, E_FAST, { BackgroundTransparency=0 }) end)
				row.MouseLeave:Connect(function() tween(row, E_FAST, { BackgroundTransparency=0.4 }) end)
				if e.action then row.MouseButton1Click:Connect(function() task.spawn(e.action) end) end
			end
			task.defer(fit)
		end
		function Window:AddShortcut(label, action, hint)
			table.insert(entries, { label = label, action = action, hint = hint })
			build(); return Window
		end
		function Window:RemoveShortcut(label)
			for i2 = #entries, 1, -1 do if entries[i2].label == label then table.remove(entries, i2) end end
			build(); return Window
		end
		Window._shortcuts = sc
		Window._scHidden = false
		local function keyOf(k) return k and (k.Name:gsub("Right","R"):gsub("Left","L"):gsub("Control","Ctrl")) or "None" end
		Window:AddShortcut("Command bar", function() Window:OpenCommandBar() end, function() return keyOf(Window._cmdKey) end)
		Window:AddShortcut("Search", function() if Window._searchBox then Window._searchBox:CaptureFocus() end end, "Ctrl+F")
		Window:AddShortcut("Jump to setting", function()
			local pal = gui:FindFirstChild("Palette")
			if pal then pal.Visible = true; pal.BackgroundTransparency = 0.5 end
		end, "Ctrl+K")
		Window:AddShortcut("Settings", function() if Window.SettingsPanel then Window.SettingsPanel.Visible = not Window.SettingsPanel.Visible end end)
		Window:AddShortcut("Minimize", function() Window:Minimize() end, function() return keyOf(Window._minKey) end)
		Window:AddShortcut("Save config", function() Window:SaveProfile("default") end)
		Window:AddShortcut("Undo last change", function() Window:Undo() end, "Ctrl+Z")
		rowsLay:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fit)
		setHost = secWindow
		Window._scToggle = setToggleRow("Hide shortcuts", false, function(v) sc.Visible = not v end, 7.3)
	end
	task.defer(function() if alive() and not Window._plistAPI then pcall(function() Window:PlayerList({}) end) end end)

	if searchBox then
		searchBox:GetPropertyChangedSignal("Text"):Connect(function() if activeCategory then activeCategory:_filter(searchBox.Text) end end)
		UIS_.InputBegan:Connect(function(i, p) if i.KeyCode==Enum.KeyCode.Escape and searchBox.Text~="" then searchBox.Text="" end end)
	end
	if config.Skin then task.defer(function() Window:SetSkin(config.Skin) end) end
	if config.AutoSave ~= false then
		task.delay(1.5, function()
			if not alive() then return end
			pcall(function() Window:LoadProfile("__auto") end)
			local last = ""
			task.spawn(function()
				while alive() do
					task.wait(5)
					local ok2, enc = pcall(function() return game:GetService("HttpService"):JSONEncode(Window:GetConfig()) end)
					if ok2 and enc ~= last then last = enc; pcall(function() Window:SaveProfile("__auto") end) end
				end
			end)
		end)
	end
	task.defer(function()
		Window._defaults = Window:GetConfig()
		task.delay(2, function() local n=0; for _ in pairs(Window._defaults) do n+=1 end if n==0 then Window._defaults = Window:GetConfig() end end)
	end)
	if config.Loader == false then applyOpen() else task.spawn(function() playLoader(applyOpen) end) end
	return Window
end
return UILib