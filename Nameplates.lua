local _, FS = ...
local Nameplates = FS:RegisterModule("Nameplates", "AceTimer-3.0")
FS.Hud = Nameplates

local LSM = LibStub("LibSharedMedia-3.0")

local pi2, pi_2 = math.pi * 2, math.pi / 2
local inf = math.huge

local hud = CreateFrame("Frame", "FSNameplateHUD", UIParent)
hud:SetFrameStrata("BACKGROUND")
hud:SetAllPoints()
hud:Hide()

local fakePlayerPlate = CreateFrame("Frame", "FSNameplatePlayerFake", hud)
fakePlayerPlate:SetWidth(10)
fakePlayerPlate:SetHeight(10)
fakePlayerPlate:SetPoint("BOTTOM", hud, "CENTER", 0, 0)
fakePlayerPlate:Show()
fakePlayerPlate.token = "player"

local Makers_Color = {
	{ 0.98, 0.93, 0.33 },
	{ 1.00, 0.57, 0.00 },
	{ 0.84, 0.30, 0.91 },
	{ 0.16, 0.89, 0.13 },
	{ 0.46, 0.69, 0.93 },
	{ 0.00, 0.57, 1.00 },
	{ 1.00, 0.23, 0.20 },
	{ 1.00, 0.98, 0.98 }
}

-------------------------------------------------------------------------------
-- Config
-------------------------------------------------------------------------------

local nameplates_defaults = {
	profile = {
		enable = true,
		clickthrough = false,
		offset = 0,
	}
}

local nameplates_config = {
	title = {
		type = "description",
		name = "|cff64b4ffNameplates HUD",
		fontSize = "large",
		order = 0,
	},
	desc = {
		type = "description",
		name = "Provides a nameplate drawing API.\n",
		fontSize = "medium",
		order = 1,
	},
	enable = {
		type = "toggle",
		name = "Enable",
		descStyle = "inline",
		width = "full",
		get = function() return Nameplates.settings.enable end,
		set = function(_, v)
			Nameplates.settings.enable = v
			if v then
				Nameplates:Enable()
			else
				Nameplates:Disable()
			end
		end,
		order = 2
	},
	--[[clickthrough = {
		type = "toggle",
		name = "Click through friendly nameplates",
		descStyle = "inline",
		width = "full",
		get = function() return Nameplates.settings.clickthrough end,
		set = function(_, v)
			Nameplates.settings.clickthrough = v
			C_NamePlate.SetNamePlateFriendlyClickThrough(v)
		end,
		order = 3
	},]]
	offset = {
		type = "range",
		name = "Offset",
		min = -10000,
		max = 10000,
		softMin = -300,
		softMax = 300,
		bigStep = 1,
		get = function() return Nameplates.settings.offset end,
		set = function(_, value)
			Nameplates.settings.offset = value
			Nameplates:RefreshBidings()
		end,
		order = 10
	},
}

-------------------------------------------------------------------------------
-- Life-cycle
-------------------------------------------------------------------------------

function Nameplates:OnInitialize()
	self.db = FS.db:RegisterNamespace("Nameplates", nameplates_defaults)
	self.settings = self.db.profile
	FS.Config:Register("Nameplates HUD", nameplates_config)

	--C_NamePlate.SetNamePlateFriendlyClickThrough(self.settings.clickthrough)

	self.index = {}
	self.objects = {}
	self.registry = {}
end

function Nameplates:OnEnable()
	self:RegisterEvent("NAME_PLATE_CREATED")
	self:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	self:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
	self:RegisterEvent("ENCOUNTER_END")
	self:ScheduleRepeatingTimer("GC", 60)
	if self.settings.enable then
		hud:Show()
	end
end

function Nameplates:OnDisable()
	hud:Hide()
end

function Nameplates:RefreshBidings()
	for owner, objects in pairs(self.objects) do
		local nameplate = self:GetNameplateByGUID(owner)
		if nameplate then
			for obj in pairs(objects) do
				obj:Attach(nameplate)
			end
		end
	end
end

function Nameplates:ENCOUNTER_END()
	for owner, objects in pairs(self.objects) do
		for obj, timestamp in pairs(objects) do
			obj:Remove()
		end
	end
end

function Nameplates:GC()
	if IsEncounterInProgress() then return end
	local now = GetTime()
	for owner, objects in pairs(self.objects) do
		local nameplate = self:GetNameplateByGUID(owner)
		if not nameplate then
			for obj, timestamp in pairs(objects) do
				if now - timestamp > 60 then
					obj:Remove()
				end
			end
		end
	end
end

-------------------------------------------------------------------------------
-- Index
-------------------------------------------------------------------------------

function Nameplates:GetNameplateByGUID(guid)
	if UnitExists(guid) then
		guid = UnitGUID(guid)
	end
	if guid == UnitGUID("player") then
		return fakePlayerPlate
	else
		local nameplate = self.index[guid]
		if nameplate then
			if UnitGUID(nameplate.token) == guid then
				return nameplate
			end
		end
	end
end

function Nameplates:RegisterObject(obj, name, remove)
	if remove then self:RemoveObject(name) end
	self.registry[obj] = name
end

function Nameplates:RemoveObject(name)
	for obj, key in pairs(self.registry) do
		if key == name then
			obj:Remove()
		end
	end
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

function Nameplates:NAME_PLATE_CREATED(_, nameplate)
	-- Nothing
end

function Nameplates:NAME_PLATE_UNIT_ADDED(_, token)
	if UnitIsUnit(token, "player") then return end
	local guid = UnitGUID(token)
	local nameplate = C_NamePlate.GetNamePlateForUnit(token)
	nameplate.token = token
	self.index[guid] = nameplate

	if self.objects[guid] then
		for obj in pairs(self.objects[guid]) do
			obj:Attach(nameplate)
		end
	end
end

function Nameplates:NAME_PLATE_UNIT_REMOVED(_, nameplate)
	if UnitIsUnit(nameplate, "player") then return end
	local guid = UnitGUID(nameplate)
	self.index[guid] = nil

	if self.objects[guid] then
		for obj in pairs(self.objects[guid]) do
			obj:Detach()
			self.objects[guid][obj] = GetTime()
		end
	end
end

-------------------------------------------------------------------------------
-- Frames Pool
-------------------------------------------------------------------------------

local alloc_frame, free_frame
do
	local pool = {}

	local function normalize(frame)
		frame:Hide()
		frame:SetFrameStrata("BACKGROUND")
		frame:ClearAllPoints()
		frame:SetAlpha(1)
		if frame.tex then frame.tex:Hide() end
		if frame.line then frame.line:Hide() end
		if frame.text then frame.text:Hide() end
		return frame
	end

	function alloc_frame()
		return normalize(#pool > 0 and table.remove(pool) or CreateFrame("Frame", nil, hud))
	end

	function free_frame(frame)
		frame:Hide()
		frame:SetScript("OnUpdate", nil)
		table.insert(pool, frame)
	end
end

-------------------------------------------------------------------------------
-- Aura tracking
-------------------------------------------------------------------------------

local function setup_aura_tracking(self, guid, aura, buff)
	local unit = UnitExists(guid) and guid or FS.Roster:GetUnit(guid)
	if not unit then
		error("Cannot find unit " .. guid .. " for aura-tracking HUD object")
	end
	local spell = type(aura) == "string" and duration or GetSpellInfo(aura < 0 and -aura or aura)
	if buff == nil then buff = not not UnitBuff(unit, spell) end
	local auraType = buff and UnitBuff or UnitDebuff
	function self:TimeLeft()
		local _, _, _, _, _, duration, expires = auraType(unit, spell)
		local left = duration and expires - GetTime() or 0
		return left, duration or 1
	end
	function self:Progress()
		local left, total = self:TimeLeft()
		return 1 - left / total
	end
end

-------------------------------------------------------------------------------
-- Object API
-------------------------------------------------------------------------------

local NameplateObject = {}

function NameplateObject:Attach(nameplate)
	self.frame:SetPoint("CENTER", nameplate, "BOTTOM", self.offset_x , self.offset_y + Nameplates.settings.offset)
	if not self.attached then
		self.frame:Show()
		self.attached = true
		if self.OnAttachChange then self:OnAttachChange(true, nameplate) end
	end
end

function NameplateObject:Detach()
	if self.attached then
		self.frame:Hide()
		self.frame:ClearAllPoints()
		self.attached = false
		if self.OnAttachChange then self:OnAttachChange(false) end
	end
end

function NameplateObject:IsAttached()
	return self.attached
end

function NameplateObject:UseTexture(path)
	if not self.frame.tex then
		self.frame.tex = self.frame:CreateTexture(nil, "ARTWORK")
	end
	local tex = self.frame.tex
	tex:SetAllPoints()
	tex:SetDrawLayer("BACKGROUND")
	tex:SetBlendMode("BLEND")
	tex:SetTexCoord(0, 1, 0, 1)
	tex:SetTexture(path)
	tex:Show()
	return tex
end

function NameplateObject:UseLine(thickness)
	if not self.frame.line then
		self.frame.line = self.frame:CreateLine()
	end
	local line = self.frame.line
	line:SetDrawLayer("BACKGROUND")
	line:SetBlendMode("ADD")
	line:SetColorTexture(1, 1, 1, 0.6)
	line:SetThickness(thickness)
	line:Show()
	return line
end

function NameplateObject:UseText()
	if not self.frame.text then
		self.frame.text = self.frame:CreateFontString(nil, "OVERLAY")
	end
	local text = self.frame.text
	text:SetAllPoints()
	text:SetJustifyH("CENTER")
	text:SetJustifyV("MIDDLE")
	text:SetTextColor(1, 1, 1)
	text:Show()
	return text
end

function NameplateObject:SetOffset(x, y)
	self.offset_x = x
	self.offset_y = y
	if self.attached then
		self:Attach(Nameplates:GetNameplateByGUID(self.owner))
	end
	return self
end

function NameplateObject:SetSize(...)
	self.frame:SetSize(...)
	return self
end

function NameplateObject:SetColor(r, g, b, a, ...)
	if r > 1 then r = r / 255 end
	if g > 1 then g = g / 255 end
	if b > 1 then b = b / 255 end
	if a and a > 1 then a = a / 255 end
	if self.frame.tex then
		self.frame.tex:SetVertexColor(r, g, b, a, ...)
	end
	if self.frame.line then
		self.frame.line:SetColorTexture(r, g, b, a, ...)
	end
	if self.frame.text then
		self.frame.text:SetTextColor(r, g, b, a, ...)
	end
	if self.spinner then
		self.spinner:SetVertexColor(r, g, b, a, ...)
	end
	return self
end

function NameplateObject:SetMarkerColor(marker, a)
	local color = Makers_Color[marker]
	if color then
		local r, g, b = unpack(color)
		return self:SetColor(r, g, b, a)
	else
		return self
	end
end

function NameplateObject:SetBlendMode(...)
	if self.frame.tex then
		self.frame.tex:SetBlendMode(...)
	end
	return self
end

function NameplateObject:Register(name, remove)
	Nameplates:RegisterObject(self, name, remove)
	return self
end

function NameplateObject:Remove()
	if self.__removed then return end
	self.__removed = true
	Nameplates.registry[self] = nil
	local objects = Nameplates.objects[self.owner]
	objects[self] = nil
	if not next(objects) then
		Nameplates.objects[self.owner] = nil
	end
	if self.CleanupHook then self:CleanupHook() end
	if self.OnRemove then self:OnRemove() end
	free_frame(self.frame)
end

function Nameplates:CreateObject(guid, proto)
	if UnitExists(guid) then guid = UnitGUID(guid) end
	local obj = setmetatable(proto or {}, { __index = NameplateObject })

	obj.owner = guid
	obj.frame = alloc_frame()
	obj.tex = obj.frame.tex

	obj.offset_x = 0
	obj.offset_y = 0

	obj.frame:SetScript("OnUpdate", function(_, dt)
		if obj.OnUpdate then obj:OnUpdate(dt) end
		if obj.Update then obj:Update(dt) end
	end)

	local objects = self.objects[guid]
	if not objects then
		objects = {}
		self.objects[guid] = objects
	end
	objects[obj] = GetTime()

	local nameplate = self:GetNameplateByGUID(guid)
	if nameplate then
		obj:Attach(nameplate)
	end

	return obj
end

-------------------------------------------------------------------------------
-- API
-------------------------------------------------------------------------------

-- Texture
function Nameplates:DrawTexture(guid, width, height, tex_path)
	if tex_path == nil then
		tex_path = height
		height = width
	end

	local texture = self:CreateObject(guid, { width = width, height = height })

	local tex = texture:UseTexture(tex_path)
	tex:SetDrawLayer("ARTWORK")
	tex:SetVertexColor(1, 1, 1, 1)

	function texture:SetSize(width, height)
		self.width = width
		self.height = height
		return self
	end

	function texture:Update()
		local width, height = self.width, self.height
		if self.Rotate then
			-- Rotation require a multiplier on size
			width = width * (2 ^ 0.5)
			height = height * (2 ^ 0.5)
			self.tex:SetRotation(self:Rotate() % pi2)
		end
		self.frame:SetSize(width, height)
	end

	function texture:SetBlendMode(...)
		tex:SetBlendMode(...)
		return self
	end

	return texture
end

-- Raid target
function Nameplates:DrawMarker(guid, size, target)
	if target == nil then
		target = size
		size = 50
	end
	local path = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. target
	return self:DrawTexture(guid, size, size, path)
end

-- Generic circle
function Nameplates:DrawCircle(guid, radius, tex_path)
	local circle = self:CreateObject(guid, { radius = radius })
	local smoothing = false

	local tex = circle:UseTexture(tex_path)
	tex:SetBlendMode("ADD")
	tex:SetVertexColor(0.8, 0.8, 0.8, 0.5)

	function circle:SetRadius(radius)
		self.radius = radius
		return self
	end

	local target, current = 0, inf
	function circle:Update()
		local size = self.radius * 2
		if self.Rotate then
			size = size * (2 ^ 0.5)
			target = self:Rotate()
			if smoothing and current ~= inf then
				current = current + (target - current) / 3
			else
				current = target
			end
			tex:SetRotation(current % pi2)
		end
		self.frame:SetSize(size, size)
	end

	function circle:SetSmooth(smooth)
		smoothing = smooth
		return self
	end

	circle:Update()
	return circle
end

-- Draw a radius circle
function Nameplates:DrawRadius(guid, radius)
	return self:DrawCircle(guid, radius, radius < 15 and "Interface\\AddOns\\FS_Core\\media\\radius_lg" or "Interface\\AddOns\\FS_Core\\media\\radius")
end

-- Area of Effect
function Nameplates:DrawArea(guid, radius)
	return self:DrawCircle(guid, radius, "Interface\\AddOns\\FS_Core\\media\\radar_circle")
end

-- Target reticle
function Nameplates:DrawTarget(guid, radius)
	local target = self:DrawCircle(guid, radius, "Interface\\AddOns\\FS_Core\\media\\alert_circle")
	function target:Rotate()
		return GetTime() * 1.5
	end
	return target
end

-- Clock
function Nameplates:DrawClock(guid, radius, duration, buff)
	local clock = self:DrawCircle(guid, radius, "Interface\\AddOns\\FS_Core\\media\\timer")

	-- Timer informations
	local done = false
	local rotate = 0

	if not duration then
		function clock:Progress()
			return 0
		end
	elseif type(duration) == "string" or duration < 0 or duration > 1000 then
		setup_aura_tracking(clock, guid, duration, buff)
	else
		local start = GetTime()

		function clock:Progress()
			if not duration then return 0 end
			local dt = GetTime() - start
			return dt < duration and dt / duration or 1
		end

		function clock:Reset(d)
			start = GetTime()
			duration = d
			done = false
			return self
		end
	end

	-- Hook the Update() function directly to let the OnUpdate() hook available for user code
	local circle_update = clock.Update
	function clock:Update()
		local pct = self:Progress()
		if pct < 0 then pct = 0 end
		if pct > 1 then pct = 1 end
		rotate = pi2 * pct
		if pct == 1 and not done then
			done = true
			if self.OnDone then self:OnDone() end
		end
		circle_update(clock)
	end

	function clock:OnDone()
		self:Remove()
	end

	function clock:Rotate()
		return rotate
	end

	return clock
end

-- Line
function Nameplates:DrawLine(a, b, thickness)
	local anchorA = self:CreateObject(a):SetSize(1, 1)
	local anchorB = self:CreateObject(b):SetSize(1, 1)

	local line = anchorA:UseLine(thickness or 2)
	line:SetStartPoint("CENTER", anchorA.frame)
	line:SetEndPoint("CENTER", anchorB.frame)

	local function update_line_visibility()
		if anchorA:IsAttached() and anchorB:IsAttached() then
			line:Show()
		else
			line:Hide()
		end
	end

	anchorA.OnAttachChange = update_line_visibility
	anchorB.OnAttachChange = update_line_visibility

	function anchorA:SetThickness(thickness)
		line:SetThickness(thickness)
		return self
	end

	local obj_remove = anchorA.Remove
	function anchorA:Remove()
		obj_remove(anchorA)
		anchorB:Remove()
	end

	return anchorA
end

-- Text
function Nameplates:DrawText(owner, label, size)
	local obj = Nameplates:CreateObject(owner):SetSize(300, 300)

	local size = size or 20
	local font = "Fonts\\FRIZQT__.TTF"
	local outline = "OUTLINE"

	local text = obj:UseText()
	text:SetFont(font, size, outline)
	text:SetText(label)

	function obj:SetFont(s, f, o)
		size = s or size
		font = (f and LSM:Fetch("font", f, true) or f) or font
		outline = o or outline
		text:SetFont(font, size, outline)
		return self
	end

	function obj:SetText(...)
		text:SetText(...)
		return self
	end

	return obj
end

-- Spinner
do
	local spinner_pool = {}

	local function alloc_spinner(anchor)
		local spinner
		if #spinner_pool > 0 then
			spinner = table.remove(spinner_pool)
		else
			spinner = FS.Util.Spinner.Create()
		end
		spinner.frame:SetParent(anchor.frame)
		spinner.frame:SetPoint("CENTER", anchor.frame, "CENTER")
		spinner.frame:Show()
		return spinner
	end

	local function free_spinner(spinner)
		spinner:Hide()
		table.insert(spinner_pool, spinner)
	end

	function Nameplates:DrawSpinner(guid, radius, duration, buff)
		local done = false

		local parent = self:CreateObject(guid):SetSize(1, 1)
		local spinner = alloc_spinner(parent)
		local smoothing = false

		local size = radius * 2.3 -- To match DrawCircle radius
		spinner:SetTexture("Interface\\AddOns\\FS_Core\\media\\ring512")
		spinner:SetSize(size, size)
		spinner:SetBlendMode("ADD")
		spinner:Color(0.8, 0.8, 0.8, 0.8)

		spinner:SetClockwise(true)

		if not duration then
			function parent:Progress()
				return 0
			end
		elseif type(duration) == "string" or duration < 0 or duration > 1000 then
			setup_aura_tracking(parent, guid, duration, buff)
		else
			local start = GetTime()

			function parent:Progress()
				if not duration then return 0 end
				local dt = GetTime() - start
				return dt < duration and dt / duration or 1
			end

			function parent:Reset(d)
				start = GetTime()
				duration = d
				done = false
				return self
			end
		end

		-- Hook the Update() function directly to let the OnUpdate() hook available for user code
		local target, current = 0, inf
		function parent:Update(dt)
			local pct = self:Progress()
			if pct < 0 then pct = 0 end
			if pct > 1 then pct = 1 end
			target = pct
			if smoothing and current ~= inf then
				current = current + (target - current) / 3
			else
				current = target
			end
			spinner:SetValue(current)
			if pct == 1 and not done then
				done = true
				if self.OnDone then self:OnDone() end
			end
		end

		function parent:OnDone()
			self:Remove()
		end

		function parent:CleanupHook()
			free_spinner(spinner)
		end

		function parent:SetSmooth(smooth)
			smoothing = smooth
			return self
		end

		function parent:SetRadius(radius)
			local size = radius * 2.3 -- To match DrawCircle radius
			spinner:SetSize(size, size)
			return self
		end

		function parent:SetColor(r, g, b, a, ...)
			if r > 1 then r = r / 255 end
			if g > 1 then g = g / 255 end
			if b > 1 then b = b / 255 end
			if a and a > 1 then a = a / 255 end
			spinner:Color(r, g, b, a, ...)
			return self
		end

		function parent:SetBlendMode(...)
			spinner:SetBlendMode(...)
			return self
		end

		function parent:SetClockwise(...)
			spinner:SetClockwise(...)
			return self
		end

		return parent
	end
end

do
	local timer_mt = {
		__index = function(self, key)
			local clock_fn = self.clock[key]
			local spinner_fn = self.spinner[key]
			local clock_is_fn = type(clock_fn) == "function"
			local spinner_is_fn = type(spinner_fn) == "function"
			if clock_is_fn or spinner_is_fn then
				return function(_, ...)
					if clock_is_fn then
						clock_fn(self.clock, ...)
					end
					if spinner_is_fn then
						spinner_fn(self.spinner, ...)
					end
					return self
				end
			end
		end,
		__newindex = function(self, key, value)
			self.clock[key] = value
			self.spinner[key] = value
		end
	}

	function Nameplates:DrawTimer(...)
		local obj = {}
		obj.clock = self:DrawClock(...)
		obj.spinner = self:DrawSpinner(...)
		return setmetatable(obj, timer_mt)
	end
end
