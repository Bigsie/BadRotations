local oldvalueBr
local oldValuePersonal
local oldValueProfile
local lastUnit = 0

function br.interruptsEngine()
	if not getOptionCheck("IE Active") then return end
	if br.player.interrupts == nil then br.player.interrupts = {} end
	if useInterrupts() then
        br.player.interrupts.enabled = true
    else
        br.player.interrupts.enabled = false
    end
	if not br.player.interrupts.enabled then return end
	if br.player.interrupts.activeList == nil then br.player.interrupts.activeList = {} end
    br.player.interrupts.listUpdated = true

    -- Form activeList for interrupting
    checkForUpdates()
    if not br.player.interrupts.listUpdated then
		if getOptionCheck("Include BR Whitelist") then
            for spellID,v in pairs(br.lists.interruptWhitelist) do
                table.insert(br.player.interrupts.activeList, spellID, v)
			end
		else
			for spellID,_ in pairs(br.lists.interruptWhitelist) do
				if not isTableEmpty(br.player.interrupts.activeList) then
					br.player.interrupts.activeList[spellID] = false
				end
			end
		end
        if getOptionCheck("Include Personal Whitelist") then
            for spellID in string.gmatch(tostring(getOptionValue("SpellIDs to Interrupt")),"([^,]+)") do
                if string.len(string.trim(spellID)) >= 3 then
                    table.insert(br.player.interrupts.activeList, tonumber(spellID), true)
                end
            end
		else
			for spellID in string.gmatch(tostring(getOptionValue("SpellIDs to Interrupt")),"([^,]+)") do
				if not isTableEmpty(br.player.interrupts.activeList) then
					br.player.interrupts.activeList[tonumber(spellID)] = false
				end
			end
		end
        if getOptionCheck("Include Profile Whitelist") and br.player.interrupts.profileWhitelist ~= nil then
            for spellID,_ in pairs(br.player.interrupts.profileWhitelist) do
                table.insert(br.player.interrupts.activeList, tonumber(spellID), true)
            end
		else
			if not isTableEmpty(br.player.interrupts.profileWhitelist) then
				for spellID,_ in pairs(br.player.interrupts.profileWhitelist) do
					if not isTableEmpty(br.player.interrupts.activeList) then
						br.player.interrupts.activeList[spellID] = false
					end
				end
			end
		end
        oldvalueBr = getOptionCheck("Include BR Whitelist")
        oldValuePersonal = getOptionCheck("Include Personal Whitelist")
        oldValueProfile = getOptionCheck("Include Profile Whitelist")
        br.player.interrupts.listUpdated = true
    end

    -- Do the actual interrupting
	if br.player.spell.interrupts == nil then return end -- If no interruptspells are given, get the hell outta here
	local interruptAt = 100 - br.player.ui.value("Interrupts At")
	local range = 0
	br.player.interrupts.enemies = {}

	for _,v in pairs(br.player.spell.interrupts) do
		if canCast(v)then
			if getOptionCheck("Interrupt with " .. GetSpellInfo(v)) then
				br.player.interrupts.currentSpell = v
				range = select(6, GetSpellInfo(br.player.interrupts.currentSpell))
				break
			else
				return
			end
		end
	end

	br.player.interrupts.enemies = br.player.enemies.get(range,nil,false,true)

	for _,unit in pairs(br.player.interrupts.enemies) do
        for spell,_ in pairs(br.player.interrupts.activeList) do
            if isCastingSpell(spell, unit) and canInterrupt(unit) then
                br.player.interrupts.currentUnit = unit
                br.player.interrupts.unitSpell = spell
			end
        end
    end


	if isInCombat("player") and br.player.interrupts.currentUnit ~= nil and br.player.interrupts.unitSpell ~= nil and br.player.interrupts.currentSpell ~= nil then
		if isCastingSpell(br.player.interrupts.unitSpell, br.player.interrupts.currentUnit) and canInterrupt(br.player.interrupts.currentUnit, interruptAt) then
			if (getTimeToLastInterrupt() >= 1 and GetObjectID(lastUnit) == GetObjectID(br.player.interrupts.currentUnit)) or
		      (getTimeToLastInterrupt() < 1 and GetObjectID(lastUnit) ~= GetObjectID(br.player.interrupts.currentUnit)) then
				RunMacroText("/stopcasting")
				local castSuccess = createCastFunction(br.player.interrupts.currentUnit.unit, any, any, any, br.player.interrupts.currentSpell)
				if castSuccess then
					br.addonDebug("Casting ", tostring(GetSpellInfo(br.player.interrupts.currentSpell)))
					lastUnit = br.player.interrupts.currentUnit
				end

			end
		end
	end
end
---------------------
--- Methods below ---
---------------------

-- canInterrupt("target",20)
function canInterrupt(unit,percentint)
	unit = unit or "target"
	-- M+ Affix: Beguiling (Prevents Interrupt) - Queen's Decree: Unstoppable buff
	if UnitBuffID(unit,302417) ~= nil then return false end
	local interruptTarget = getOptionValue("Interrupt Target")
	if interruptTarget == 2 and not GetUnitIsUnit(unit, "target") then
		return false
	elseif interruptTarget == 3 and not GetUnitIsUnit(unit, "focus") then
		return false
	elseif interruptTarget == 4 and getOptionValue("Interrupt Mark") ~= GetRaidTargetIndex(unit) then
		return false
	end
	local castStartTime, castEndTime, interruptID, interruptable = 0, 0, 0, false
	local castDuration, castTimeRemain, castPercent = 0, 0, 0
	local channelDelay = 1 -- Delay to mimick human reaction time for channeled spells
	local castType = "spellcast" -- Handle difference in logic if the spell is cast or being channeles
	if GetUnitExists(unit)
		and UnitCanAttack("player",unit)
		and not UnitIsDeadOrGhost(unit)
	then
		-- Get Cast/Channel Info
		if select(5,UnitCastingInfo(unit)) and not select(8,UnitCastingInfo(unit)) then --Get spell cast time
			castStartTime = select(4,UnitCastingInfo(unit))
			castEndTime = select(5,UnitCastingInfo(unit))
			interruptID = select(9,UnitCastingInfo(unit))
			interruptable = true
			castType = "spellcast"
		elseif select(5,UnitChannelInfo(unit)) and not select(7,UnitChannelInfo(unit)) then -- Get spell channel time
			castStartTime = select(4,UnitChannelInfo(unit))
			castEndTime = select(5,UnitChannelInfo(unit))
			interruptID = select(8,UnitChannelInfo(unit))
			interruptable = true
			castType = "spellchannel"
		end
		-- Assign interrupt time
		if castEndTime > 0 and castStartTime > 0 then
			castDuration = (castEndTime - castStartTime)/1000
			castTimeRemain = ((castEndTime/1000) - GetTime())
			if percentint == nil and castPercent == 0 then
				if castType == "spellcast" then
					castPercent = math.random(25,75) --  I am not sure that this is working,we are doing this check every pulse so its different randoms each time
				end
				if castType == "spellchannel" then
					if castDuration > 60 then
						castPercent = 100
					else
						castPercent = math.random(95, 99)
					end
				end
			elseif percentint == 0 and castPercent == 0 then
				if castType == "spellcast" then
					castPercent = math.random(25,75)
				end
				if castType == "spellchannel" then
					if castDuration > 60 then
						castPercent = 100
					else
						castPercent = math.random(95, 99)
					end
				end
			elseif percentint > 0 then
				if castType == "spellcast" then
					castPercent = percentint
				end
				if castType == "spellchannel" then
					if castDuration > 60 then
						castPercent = 100
					else
						castPercent = math.random(95, 99)
					end
				end
			end
		end
		-- Return when interrupt time is met
		if (br.player.interrupts.activeList[interruptID] or not (br.player.instance=="party" or br.player.instance=="raid") or not br.player.interrupts.activeList[interruptID]) then
			if castType == "spellcast" then
				if math.ceil((castTimeRemain/castDuration)*100) <= castPercent and interruptable == true and getTTD(unit)>castTimeRemain then
					return true
				end
			end
			if castType == "spellchannel" then
				--if (GetTime() - castStartTime/1000) > channelDelay and interruptable == true then
				if (GetTime() - castStartTime/1000) > (channelDelay-0.2 + math.random() * 0.4) and (math.ceil((castTimeRemain/castDuration)*100) <= castPercent or castPercent == 100) and interruptable == true and (getTTD(unit)>castTimeRemain or castPercent == 100) then
					return true
				end
			end
		end
		return false
	end
end

function checkForUpdates()
    if getOptionCheck("Include BR Whitelist") ~= oldvalueBr or getOptionCheck("Include Personal Whitelist") ~= oldValuePersonal
    or getOptionCheck("Include Profile Whitelist") ~= oldValueProfile then br.player.interrupts.listUpdated = false end
end

function getTimeToLastInterrupt()
	if not isTableEmpty(br.lastCast.tracker) then
		for _, v in ipairs(br.lastCast.tracker) do
			for _,value in pairs(br.player.spell.interrupts) do
				if tonumber(value) == tonumber(v) then
					return GetTime() - br.lastCast.castTime[v]
				end
			end
		end
	end
	return 0
end