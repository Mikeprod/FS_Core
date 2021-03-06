local _, FS = ...
local Misc = FS:RegisterModule("Miscellaneous")

local features = {}

-------------------------------------------------------------------------------
-- Config
-------------------------------------------------------------------------------

local misc_defaults = {
	profile = {}
}

local misc_config = {
	title = {
		type = "description",
		name = "|cff64b4ffMiscellaneous",
		fontSize = "large",
		order = 0,
	},
	desc = {
		type = "description",
		name = "Various useful options.\n",
		fontSize = "medium",
		order = 1,
	},
}

-------------------------------------------------------------------------------
-- Life-cycle
-------------------------------------------------------------------------------
function Misc:OnInitialize()
	self.db = FS.db:RegisterNamespace("Miscellaneous", misc_defaults)
	self.settings = self.db.profile
	FS.Config:Register("Miscellaneous", misc_config, 12)

	self:RegisterEvent("ADDON_LOADED")
end

function Misc:OnEnable()
	for name in pairs(features) do
		self:SyncFeature(name)
	end
end

do
	local order = 10
	function Misc:RegisterFeature(name, short, long, default, fn)
		misc_config[name] = {
			type = "toggle",
			name = short,
			descStyle = "inline",
			desc = "|cffaaaaaa" .. long,
			width = "full",
			get = function() return Misc.settings[name] end,
			set = function(_, v)
				Misc.settings[name] = v
				Misc:SyncFeature(name)
			end,
			order = order
		}
		misc_defaults.profile[name] = default
		order = order + 1
		features[name] = fn
	end
end

function Misc:SyncFeature(name)
	features[name](Misc.settings[name])
end

function Misc:ADDON_LOADED(event, addon)
	if addon == "Blizzard_TalkingHeadUI" then
		self:SyncFeature("TalkingHead")
	end
end

-------------------------------------------------------------------------------
-- Features
-------------------------------------------------------------------------------

do
	Misc:RegisterFeature("MaxCam",
		"Maximize camera distance",
		"Automatically reset your camera to max distance when logging in.",
		true,
		function(state)
			if state then
				C_Timer.After(0.3, function()
					SetCVar("cameraDistanceMaxZoomFactor", 2.6)
					MoveViewOutStart(50000)
				end)
			end
		end)
end

do
	local enabled = false
	Misc:RegisterFeature("SlashRL",
		"Enable /rl",
		"Enables the short version for reloading the interface.",
		true,
		function(state)
			if state and not enabled then
				enabled = true
				FS.Console:RegisterChatCommand("rl", function() ReloadUI() end)
			end
		end)
end

do
	local enabled = false
	Misc:RegisterFeature("TalkingHead",
		"Disable Talking Head",
		"Disables the Talking Head feature that is used for some quest and event dialogues.",
		false,
		function(state)
			if not enabled and TalkingHeadFrame_PlayCurrent then
				enabled = true
				hooksecurefunc("TalkingHeadFrame_PlayCurrent", function()
					if state then TalkingHeadFrame:Hide() end
				end)
			end
		end)
end

do
	Misc:RegisterFeature("HideOrderHallBar",
		"Disable Order Hall Command Bar",
		"Hides the information bar inside your class Order Hall.",
		false,
		function(state)
			if state then
				C_Timer.After(0.3, function()
					LoadAddOn("Blizzard_OrderHallUI")
					local b = OrderHallCommandBar
					b:UnregisterAllEvents()
					b:HookScript("OnShow", b.Hide)
					b:Hide()
				end)
			end
		end)
end


-------------------------------------------------------------------------------
-- C_ArtifactUI.GetTotalPurchasedRanks() shenanigans
-------------------------------------------------------------------------------

do
	local OnShow

	local function OnShowHook(self)
		if C_ArtifactUI.GetTotalPurchasedRanks() then
			OnShow(self)
		else
			ArtifactFrame:Hide()
		end
	end

	hooksecurefunc("ArtifactFrame_LoadUI", function()
		if not OnShow then
			OnShow = ArtifactFrame:GetScript("OnShow")
			ArtifactFrame:SetScript("OnShow", OnShowHook)
		end
	end)
end
