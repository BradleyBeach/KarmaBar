--[[TODO LIST
	THREE BIG STEPS:
	FRAMEWORK
		1. DONE - throw together a quick options pane
		2. DONE - set checkbox to register an event for tracking ToK activating
		3. DONE - handler for that event, to display the sigil during ToK
	GATHER API INFO
		1. DONE - figure out how to get the buff information (duration, shield) from the buff aura (and print one/both to chat to verify)
		2. DONE - decide* best way to track the remaining shield as it is expended
			*ended up parsing combat log for absorb events and manually tracking remaining value
	DISPLAY
		1. DONE - overlay a number on the sigil to track remaining duration
			!!this point marks completion of baseline functionality!!
		2. put a bar on the screen
		3. start the sigil on the right (or left?) side of the bar
		4. have the sigil move along the bar based on remaining karma shield, hitting the left (or right?) side of bar at 0
		5. whole display vanishes when removed for any reason
			(there are 4: all karma used, duration over, enemy died, dispelled by enemy player in pvp)
			note: there may be overlap/those may be considered the same thing behind the scenes. won't know until I read into the api more.
			note 2: this could be four steps, over time. no need to hammer them all in at once.
			(PARTIALLY?) DONE - works for expiration and full consumption. should also work for others, but untested.
]]

print("EXPERIMENTAL KARMA ADDON IN USE; TURN OFF WHEN ACTUALLY PLAYING UNTIL COMPLETE")

-- partially drawn from the Warcraft Wiki's AddOn tutorial
-- (mainly with regards to generating an options panel, and with some best practices)
-- https://warcraft.wiki.gg/wiki/Create_a_WoW_AddOn_in_15_Minutes

--making the main frame for the AddOn, which will handle events
KarmaBarFrame = CreateFrame("Frame")

--establishing default settings
--currently, the options are a bit light, but good practice in case of later expansion
local defaults = {sigil = false}

--[[generalized event handler
	When KarmaBarFrame gets word of an event for which it registered,
	this looks up the specific handler stored within itself and passes along the args.
]]
function KarmaBarFrame:MyGenHandler(event, ...)
	self[event](self, event, ...)
end

--setting up 'widget script handler'
--when the "OnEvent" Script Type is invoked, pass things off to the generalized handler
KarmaBarFrame:SetScript("OnEvent", KarmaBarFrame.MyGenHandler)

--registering KarmaBarFrame for the "ADDON_LOADED" event
KarmaBarFrame:RegisterEvent("ADDON_LOADED")

--the function that runs when MyGenHandler is passed the ADDON_LOADED event
--in other words, initial set-up when the user loads into the game
function KarmaBarFrame:ADDON_LOADED(event, addOnName)
	--we only want to run when THIS AddOn loads, not ANY AddOn
	if addOnName == "KarmaBar" then
		--pull variables from storage, or use defaults on first launch
		KarmaBarDB = KarmaBarDB or {}
		self.db = KarmaBarDB
		for k, v in pairs(defaults) do
			if self.db[k] == nil then
				self.db[k] = v
			end
		end
		--[[sets a secure post-hook on the "makes the player jump" function
			When space bar is hit, that calls JumpOrAscendStart, and this hook makes JumpPrinter run afterwards
			just a quick way to verify the AddOn was loaded correctly...
			...since the main feature (ToK) has a 90-second in-game cooldown and jumping has no cooldown
		]]
		hooksecurefunc("JumpOrAscendStart", self.JumpPrinter)
		--call to the function that makes the options menu
		self:InitializeOptions()
		--since we got here, well, our addon is loaded
		--no reason to listen for OTHER addons getting loaded, so unregister for that event
		self:UnregisterEvent(event)
	end
end

--the function that runs when MyGenHandler is passed the event for a successful spellcast
--detects successful Touch of Karma, captures the buff instance ID, and registers for newly needed events
function KarmaBarFrame:UNIT_SPELLCAST_SUCCEEDED(event, _, _, sp2)
	--122470 is Touch of Karma (Naturally. That's the whole point of the AddOn.)
	--SpellName was removed from the payload in 2017, apparently, so we're stuck with the magic number.
	if sp2 == 122470 then
		--show the "Karma is active" sigil
		KarmaBarFrame.UpdateIcon(true)
		--[[A quick word about how Touch of Karma works:
			The monk, seeing incoming damage from an enemy, redirects the damage towards an enemy. Hence, Karma.
			Under the hood, casting spell 122470 actually casts two hidden subspells.
			Each subspell handles one half of the effect.
			One, spell 125174, applies a shielding aura (a buff) to the monk.
			The other applies a damaging aura (a debuff) to the enemy unit that will receive the redirected damage.
		]]
		--get the instance ID of the buff just applied by the buffing subspell of ToK
		karmaFacts = C_UnitAuras.GetPlayerAuraBySpellID(125174)
		mostRecentKarmaID = karmaFacts.auraInstanceID
		--track how much it can absorb
		--the shield begins at half of the player's total health (after other buffs are applied) at the moment of casting
		shieldStrength = UnitHealthMax("player") * .5
		--set the sigil's text field to the shield's initial strength
		KarmaBarFrame.sigil.sigtext:SetText(shieldStrength)
		
		--[[
		--debug: print all karma table data
		for k,v in pairs(karmaFacts) do print(k) print(v) end
		]]
		
		--register to listen for aura updates
		self:UpdateEvent(true, "UNIT_AURA")
		--register to listen for combat events
		self:UpdateEvent(true, "COMBAT_LOG_EVENT_UNFILTERED")
	end
end

--handler function for unit aura update events
--detects when the most recent application of ToK's buff is removed for any reason
--cancels relevant event registrations and hides the sigil
function KarmaBarFrame:UNIT_AURA(event, target, infotable)
	--if it happened to me
	if target == "player" then
		--and what happened included karma dropping off
		for index, value in ipairs(infotable.removedAuraInstanceIDs) do
			if value == mostRecentKarmaID then
				--turn off the icon
				KarmaBarFrame.UpdateIcon(false)
				--stop listening to aura events
				self:UpdateEvent(false, "UNIT_AURA")
				--stop listening to combat events
				self:UpdateEvent(false, "COMBAT_LOG_EVENT_UNFILTERED")
			end
		end
	end
end

--handler function for combat events
--detects when the ToK buff prevents damage, finds how much was absorbed, and tracks it
function KarmaBarFrame:COMBAT_LOG_EVENT_UNFILTERED(event)
	--absorb events return different params depending on whether the absorbed ability was a spell or melee
	--spell data is inserted midway through as 3 fields, so our relevant ones are sometimes offset by three
	--TODO - This was late night code and can probably be cleaned up. 
	local _, subevent, _, _, sourceName, _, _, _, destName, _, _, _, _, _, _, absorbSpellIdForSwing, absorbSpellNameForSwing, _, flex, absorbSpellNameForSpell, _, absorbAmountForSpell = CombatLogGetCurrentEventInfo()
	--above all, we only care about absorbs
	--note: read SPELL_ABSORBED as "A SPELL ABSORBED SOMETHING", not "A SPELL WAS ABSORBED"
	if subevent == "SPELL_ABSORBED" then
		--if aAFS was assigned, we know it's a spell
		if absorbAmountForSpell then
			absorbSpellId = flex
			absorbSpellName = absorbSpellNameForSpell
			absorbAmount = absorbAmountForSpell
		else
			absorbSpellId = absorbSpellIdForSwing
			absorbSpellName = absorbSpellNameForSwing
			absorbAmount = flex
		end
		theMonk = UnitName("player")
		--[[see if the player monk was protected by the shield from the Karma ability (as opposed to any other shield)
			NOTE: the combat log reports the overarching spell ID, not the subspell ID that generates the defensive half of ToK.
			I can only assume this was done since ToK is presented as a single unified effect to players, so it is bundled back up...
			...before being reported to the in-game combat log. So, again, 122470.
		]]
		if destName == theMonk and absorbSpellId == 122470 then
			shieldStrength = shieldStrength - absorbAmount
			--account for the shield used and display the new amount
			KarmaBarFrame.sigil.sigtext:SetText(shieldStrength)
			--the unit aura event will handle things if this caused the shield to be depleted, so no worries here
		end
	end
end
			

--streamlines checkbox creation in options menu
function KarmaBarFrame:CreateCheckbox(option, label, parent, updateFunc)
	--makes a new checkbox frame as a child of the parent arg
	local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
	--sets the label to the supplied label arg
	cb.Text:SetText(label)
	--a simple function to manage changing values
	--sets both the db field and the checkbox state to the specified value
	--also encloses and runs an updateFunc if one was supplied at box creation
	local function UpdateOption(value)
		--set db entry to passed value
		self.db[option] = value
		--set the box's state to passed value
		--[[Note: The checkbox can toggle itself on click without our help, so it might seem odd to do it ourselves...
			...right here in the function we'll later hook to follow the OnClick event for the box...
			...but the point is to make sure that the states stay synced in NON-click updates, like initial creation,...
			...which otherwise defaults to unchecked.]]
		cb:SetChecked(value)
		--if the box had an update function passed into the closure, run it
		if updateFunc then
			updateFunc(value)
		end
	end
	--calls to the simple function we just made
	--since we JUST made the button, we naturally want to make sure it is set to the value stored in the DB
	UpdateOption(self.db[option])
	--hooks the function to the button
	--when the box is clicked, the value changes
	cb:HookScript("Onclick", function(_, btn, down) UpdateOption(cb:GetChecked()) end)
	--listens for OnReset events, so we can reset the button to the stored default if needed
	EventRegistry:RegisterCallback("KarmaBarFrame.OnReset", function() UpdateOption(defaults[option]) end, cb)
	return cb
end

--registering the passed frame for the Options - Addon menu
local function RegisterCanvas(frame)
	local cat = Settings.RegisterCanvasLayoutCategory(frame, frame.name, frame.name)
	cat.ID = frame.name
	Settings.RegisterAddOnCategory(cat)
end

--initialization
function KarmaBarFrame:InitializeOptions()
	--make and name the options frame
	self.panel = CreateFrame("Frame")
	self.panel.name = "KarmaBar"
	--adding the first checkbox
	local howdy = self:CreateCheckbox("hello", "Says hello when you login", self.panel)
	howdy:SetPoint("TOPLEFT", 20, -20)
	--adding the second checkbox
	local sigilOp = self:CreateCheckbox("sigil", "Show the sigil", self.panel, function(value) self:UpdateEvent(value, "UNIT_SPELLCAST_SUCCEEDED") end)
	sigilOp:SetPoint("TOPLEFT", howdy, 0, -30)
	--registering to Options
	local cat = Settings.RegisterCanvasLayoutCategory(self.panel, self.panel.name, self.panel.name)
	cat.ID = self.panel.name
	Settings.RegisterAddOnCategory(cat)
end

--simply prints when the character jumps
--mainly for quick and lazy verification of successful loading during dev
function KarmaBarFrame.JumpPrinter()
	print('yeah, jumped')
end

--makes a frame based on the arguments, then returns it
local function CreateIcon(icon, width, height, parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(width, height)
	f.tex = f:CreateTexture()
	f.tex:SetAllPoints(f)
	f.tex:SetTexture(icon)
	return f
end

--update function passed in when making the sigil checkbox
--toggles display of sigil icon
function KarmaBarFrame.UpdateIcon(value)
	--if icon has not been made yet, make it
	if not KarmaBarFrame.sigil then
		KarmaBarFrame.sigil = CreateIcon("Interface/AddOns/KarmaBar/karma/karma1", 64, 64, UIParent)
		KarmaBarFrame.sigil:SetPoint("CENTER")
		--we also add some text below it
		KarmaBarFrame.sigil.sigtext = UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		KarmaBarFrame.sigil.sigtext:SetPoint("CENTER", UIParent, 0, -40)
		KarmaBarFrame.sigil.sigtext:SetText('placeholder until set by first call')
	end
	--regardless, set display of icon to passed value
	KarmaBarFrame.sigil:SetShown(value)
	KarmaBarFrame.sigil.sigtext:SetShown(value)
end

--handles registering/unregisting for events, generically
function KarmaBarFrame:UpdateEvent(value, event)
	if value then
		self:RegisterEvent(event)
	else
		self:UnregisterEvent(event)
	end
end

--finally, this code sets up and defines the slash commands to open the options pane
SLASH_KARMABAR1 = "/kb"
SLASH_KARMABAR2 = "/karmabar"

SlashCmdList.KARMABAR = function(msg, editBox)
	Settings.OpenToCategory(KarmaBarFrame.panel.name)
end