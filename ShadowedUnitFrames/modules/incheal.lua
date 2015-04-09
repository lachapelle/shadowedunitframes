local IncHeal = {playerHeals = {}}
local frames, playerHeals = {}, IncHeal.playerHeals
local playerName = UnitName("player")
local HealComm, resetFrame
ShadowUF:RegisterModule(IncHeal, "incHeal", ShadowUF.L["Incoming heals"])

function IncHeal:OnEnable(frame)
	frames[frame] = true
	frame.incHeal = frame.incHeal or ShadowUF.Units:CreateBar(frame)
	frame.incHeal:SetFrameLevel(frame.topFrameLevel - 2)
	
	frame:RegisterUnitEvent("UNIT_MAXHEALTH", self, "UpdateFrame")
	frame:RegisterUnitEvent("UNIT_HEALTH", self, "UpdateFrame")
	frame:RegisterUpdateFunc(self, "UpdateFrame")
	
	self:Setup()
end

function IncHeal:OnDisable(frame)
	frame:UnregisterAll(self)
	frame.incHeal:Hide()
	frames[frame] = nil

	self:Setup()
end

function IncHeal:OnLayoutApplied(frame)
	if( frame.visibility.incHeal and frame.visibility.healthBar ) then
		frame.incHeal:SetWidth(frame.healthBar:GetWidth() * ShadowUF.db.profile.units[frame.unitType].incHeal.cap)
		frame.incHeal:SetHeight(frame.healthBar:GetHeight())
		frame.incHeal:SetStatusBarTexture(ShadowUF.Layout.mediaPath.statusbar)
		frame.incHeal:SetStatusBarColor(ShadowUF.db.profile.healthColors.inc.r, ShadowUF.db.profile.healthColors.inc.g, ShadowUF.db.profile.healthColors.inc.b, ShadowUF.db.profile.bars.alpha)
		frame.incHeal:SetPoint("TOPLEFT", frame.healthBar)
		frame.incHeal:SetPoint("BOTTOMLEFT", frame.healthBar)
		frame.incHeal:Hide()
	end
end

-- Check if we need to register callbacks
function IncHeal:Setup()
	local enabled
	for frame in pairs(frames) do
		enabled = true
		break
	end
	
	if( not enabled ) then
		if( HealComm ) then
			HealComm:UnregisterAllCallbacks(IncHeal)
			resetFrame:UnregisterAllEvents()
		end
		return
	end

	HealComm = HealComm or LibStub("LibHealComm-3.0")
	HealComm.RegisterCallback(self, "HealComm_DirectHealStart", "DirectHealStart")
	HealComm.RegisterCallback(self, "HealComm_DirectHealStop", "DirectHealStop")
	HealComm.RegisterCallback(self, "HealComm_DirectHealDelayed", "DirectHealDelayed")
	HealComm.RegisterCallback(self, "HealComm_HealModifierUpdate", "HealModifierUpdate")

	-- When you leave a raid or party, all incoming heal data must be reset to stop it from locking and showing the incoming heal bar
	if( not resetFrame ) then
		resetFrame = CreateFrame("Frame")
		resetFrame:SetScript("OnEvent", function(self, event)
			if( ( event == "PARTY_MEMBERS_CHANGED" and GetNumPartyMembers() == 0 ) or ( event == "RAID_ROSTER_UPDATE" and GetNumRaidMembers() == 0 ) ) then
				for k in pairs(playerHeals) do playerHeals[k] = nil end
				for frame in pairs(frames) do
					frame.incHeal:Hide()
				end
			end
		end)
	end

	resetFrame:RegisterEvent("RAID_ROSTER_UPDATE")
	resetFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
end

local function getName(unit)
	local name, server = UnitName(unit)
	if( server and server ~= "" ) then
		name = string.format("%s-%s", name, server)
	end
	
	return name
end

local function updateHealthBar(frame, target, succeeded)
	-- Add in the players own heals
	local healed = playerHeals[target] or 0
	
	-- Add in any heals from other people
	local incoming = select(2, HealComm:UnitIncomingHealGet(target, 0))
	if( incoming ) then
		healed = healed + incoming
	end
	
	-- Apply any healing debuffs
	healed = math.floor(healed * HealComm:UnitHealModifierGet(target))
	
	if( healed > 0 ) then
		frame.incHeal.total = UnitHealth(frame.unit) + healed
		frame.incHeal:SetMinMaxValues(0, UnitHealthMax(frame.unit) * ShadowUF.db.profile.units[frame.unitType].incHeal.cap)
		frame.incHeal:SetValue(frame.incHeal.total)
		frame.incHeal.nextUpdate = nil
		frame.incHeal.hasHeal = true
		frame.incHeal:Show()
		
	elseif( frame.incHeal.hasHeal ) then
		if( succeeded ) then
			frame.incHeal.nextUpdate = true
		else
			frame.incHeal:Hide()
		end
		
		frame.incHeal.hasHeal = nil

		-- If it's an overheal, we won't have anything to do on a next update anyway
		local maxHealth = UnitHealthMax(frame.unit)
		if( maxHealth <= frame.incHeal.total ) then
			frame.incHeal:SetValue(maxHealth)
		end
	end
end

function IncHeal:UpdateFrame(frame, event)
	local name = getName(frame.unit)
	if( name ) then
		updateHealthBar(frame, name, event)
	end
end

function IncHeal:UpdateIncoming(healer, amount, succeeded, ...)
	for i=1, select("#", ...) do
		local target = select(i, ...)
		if( healer == playerName ) then
			if( amount ) then
				playerHeals[target] = (playerHeals[target] or 0) + amount
			else
				playerHeals[target] = nil
			end
		end
		
		self:UpdateHealing(target, succeeded)
	end
end

function IncHeal:UpdateHealing(target, succeeded)
	for frame in pairs(frames) do
		if( frame:IsVisible() and frame.unit and getName(frame.unit) == target ) then
			updateHealthBar(frame, target, succeeded)
		end
	end
end

-- Handle callbacks from HealComm
function IncHeal:DirectHealStart(event, healerName, amount, endTime, ...)
	self:UpdateIncoming(healerName, amount, nil, ...)
end

function IncHeal:DirectHealStop(event, healerName, amount, succeeded, ...)
	self:UpdateIncoming(healerName, nil, succeeded, ...)
end

function IncHeal:DirectHealDelayed(event, healerName, amount, endTime, ...)
	self:UpdateIncoming(healerName, 0, ...)
end

function IncHeal:HealModifierUpdate(event, unit, targetName, healMod)
	self:UpdateHealing(targetName)
end


