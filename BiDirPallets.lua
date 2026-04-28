BiDirPallets = {}
BiDirPallets.MOD_NAME = g_currentModName
BiDirPallets.SPEC_KEY = ("spec_%s.bidirPallets"):format(g_currentModName)

source(g_currentModDirectory .. "events/events.lua")

local EXCLUDED_TYPES = {
	tractor = true, locomotive = true, trainTrailer = true,
	trainTimberTrailer = true, receivingHopper = true, pallet = true,
	baler = true, tedder = true,
}

function BiDirPallets.prerequisitesPresent(specs)
	return SpecializationUtil.hasSpecialization(FillUnit,   specs)
	   and SpecializationUtil.hasSpecialization(FillVolume, specs)
end

function BiDirPallets.registerEventListeners(t)
	for _, ev in ipairs({
		"onLoad", "onUpdate", "saveToXMLFile",
		"onReadStream", "onWriteStream", "onRegisterActionEvents",
	}) do
		SpecializationUtil.registerEventListener(t, ev, BiDirPallets)
	end
end

function BiDirPallets.registerFunctions(t)
	local fns = {
		togglePull   = "togglePull",
		togglePush   = "togglePush",
		cyclePick    = "cyclePick",
		bdpOpenCover = "openCover",
		bdpStartPull = "startPull",
		bdpStopPull  = "stopPull",
		bdpApplyPush = "applyPush",
		bdpApplyPull = "applyPull",
	}
	for fnName, internal in pairs(fns) do
		SpecializationUtil.registerFunction(t, fnName, BiDirPallets[internal])
	end
end

function BiDirPallets.initSpecialization()
	local schema = Vehicle.xmlSchemaSavegame
	local root = "vehicles.vehicle(?).bidirPallets"
	schema:register(XMLValueType.BOOL, root .. "#pullEnabled", "Pull-fill enabled", true)
	schema:register(XMLValueType.BOOL, root .. "#pushEnabled", "Push-fill enabled", false)
end

function BiDirPallets:onLoad(savegame)
	self.spec_bidirPallets = self[BiDirPallets.SPEC_KEY]
	local bd = self.spec_bidirPallets

	bd.pulling          = false
	bd.pushing          = false
	bd.pickIndex        = 1
	bd.lastReqId        = 0
	bd.orderedTriggers  = {}
	bd.knownTriggers    = {}
	bd.canFill          = {}
	bd.hasCovers        = self.spec_cover ~= nil and self.spec_cover.hasCovers or false
	bd.eligible         = not EXCLUDED_TYPES[self.typeName]
	bd.pushAccum        = 0
	bd.pullAccum        = 0

	bd.pullEnabled = bd.eligible
	bd.pushEnabled = false

	if bd.eligible and savegame ~= nil and savegame.xmlFile ~= nil
	   and savegame.xmlFile:hasProperty(savegame.key .. ".bidirPallets") then
		local k = savegame.key .. ".bidirPallets"
		bd.pullEnabled = savegame.xmlFile:getValue(k .. "#pullEnabled", true)
		bd.pushEnabled = savegame.xmlFile:getValue(k .. "#pushEnabled", false)
	end
end

function BiDirPallets:saveToXMLFile(xmlFile, key)
	local bd = self.spec_bidirPallets
	if not bd.eligible then return end
	local k = key:gsub(BiDirPallets.MOD_NAME .. ".", "")
	xmlFile:setValue(k .. "#pullEnabled", bd.pullEnabled)
	xmlFile:setValue(k .. "#pushEnabled", bd.pushEnabled)
end

function BiDirPallets:onReadStream(streamId, conn)
	if conn:getIsServer() and self.spec_bidirPallets.eligible then
		self.spec_bidirPallets.pulling = streamReadBool(streamId)
	end
end

function BiDirPallets:onWriteStream(streamId, conn)
	if not conn:getIsServer() and self.spec_bidirPallets.eligible then
		streamWriteBool(streamId, self.spec_bidirPallets.pulling)
	end
end

local ACTION_DEFS = {
	{ "BIDIR_TOGGLE_PULL", "pull",      true,  true,
		"action_BIDIR_PULL_ON", "action_BIDIR_PULL_OFF" },
	{ "BIDIR_TOGGLE_PUSH", "push",      true,  true,
		"action_BIDIR_PUSH_ON", "action_BIDIR_PUSH_OFF" },
	{ "BIDIR_CYCLE_PICK",  "cyclePick", false, false,
		"action_BIDIR_CYCLE_PICK" },
}

function BiDirPallets:onRegisterActionEvents(_, isActiveIgnoreSel)
	if not self.isClient then return end
	local bd = self.spec_bidirPallets
	self:clearActionEventsTable(bd.actionEvents)
	if not (isActiveIgnoreSel and bd.eligible) then return end

	bd.actionIds = {}
	for _, def in ipairs(ACTION_DEFS) do
		local _, id = self:addActionEvent(bd.actionEvents, def[1], self,
			BiDirPallets.handleAction, false, true, false, true, true, nil)
		g_inputBinding:setActionEventTextPriority(id, GS_PRIO_NORMAL)
		g_inputBinding:setActionEventTextVisibility(id, def[3])
		g_inputBinding:setActionEventActive(id, def[4])
		bd.actionIds[def[2]] = { id = id, on = def[5], off = def[6] }
	end
	BiDirPallets.refreshLabels(self)
end

function BiDirPallets.refreshLabels(self)
	local bd = self.spec_bidirPallets
	local pairs_ = {
		{ "pull", bd.pullEnabled },
		{ "push", bd.pushEnabled },
	}
	for _, p in ipairs(pairs_) do
		local meta = bd.actionIds and bd.actionIds[p[1]]
		if meta ~= nil then
			local k = p[2] and meta.on or meta.off
			g_inputBinding:setActionEventText(meta.id, g_i18n:getText(k))
		end
	end
end

function BiDirPallets:handleAction(actionName)
	if     actionName == "BIDIR_TOGGLE_PULL" then self:togglePull()
	elseif actionName == "BIDIR_TOGGLE_PUSH" then self:togglePush()
	elseif actionName == "BIDIR_CYCLE_PICK"  then self:cyclePick()
	end
end

function BiDirPallets:togglePull()
	local bd = self.spec_bidirPallets
	bd.pullEnabled = not bd.pullEnabled
	if not bd.pullEnabled then bd.pulling = false end
	if bd.pullEnabled and self.spec_fillUnit ~= nil then
		bd.pulling = self.spec_fillUnit.fillTrigger.isFilling
	end
	BiDirPallets.refreshLabels(self)
end

function BiDirPallets:togglePush()
	local bd = self.spec_bidirPallets
	bd.pushEnabled = not bd.pushEnabled
	if not bd.pushEnabled then
		bd.pushing  = false
		bd.pushAccum = 0
	end
	BiDirPallets.refreshLabels(self)
end

function BiDirPallets:cyclePick()
	local bd = self.spec_bidirPallets
	local n  = #bd.orderedTriggers
	if n == 0 then return end
	bd.pickIndex = (bd.pickIndex % n) + 1
end

local function nodeOf(obj)
	local n = (obj.components ~= nil) and obj.components[1].node or obj.nodeId
	if n ~= nil and n ~= 0 and g_currentMission.nodeToObject[n] ~= nil then
		return n
	end
end

local pickColour
do
	local std = {
		pull_active = { 0.10, 1.00, 0.10, 1.0 },
		pull_idle   = { 1.00, 1.00, 0.10, 0.9 },
		pull_bad    = { 1.00, 0.10, 0.10, 0.9 },
		push_active = { 0.20, 0.55, 1.00, 1.0 },
		push_idle   = { 0.85, 0.55, 1.00, 0.9 },
		dim         = { 1.00, 1.00, 1.00, 0.5 },
	}
	local cb = {
		pull_active = { 0.10, 0.50, 1.00, 1.0 },
		pull_idle   = { 1.00, 0.90, 0.00, 0.9 },
		pull_bad    = { 1.00, 0.50, 0.50, 0.9 },
		push_active = { 0.05, 0.85, 0.85, 1.0 },
		push_idle   = { 0.85, 0.85, 0.30, 0.9 },
		dim         = { 1.00, 1.00, 1.00, 0.3 },
	}
	pickColour = function(state, useCb)
		return (useCb and cb or std)[state]
	end
end

local function compareTriggers(a, b)
	if a.sourceObject:getFillUnitFillLevel(1) < b.sourceObject:getFillUnitFillLevel(1) then
		return true
	end
	return a.sourceObject.id > b.sourceObject.id
end

local function vehicleSources(self)
	local out = {}
	for i, fu in ipairs(self.spec_fillUnit.fillUnits) do
		if fu.fillLevel and fu.fillLevel > 0.5 and fu.fillType ~= FillType.UNKNOWN then
			out[#out+1] = { idx=i, fillType=fu.fillType, level=fu.fillLevel, cap=fu.capacity }
		end
	end
	return out
end

function BiDirPallets:onUpdate(dt, isActive, isActiveIgnoreSel, isSelected)
	if not self.isClient or g_dedicatedServer ~= nil then return end
	local bd = self.spec_bidirPallets
	if not (isActiveIgnoreSel and bd.eligible) and not bd.pulling then return end

	local spec = self.spec_fillUnit
	if spec == nil then return end
	local triggers = spec.fillTrigger.triggers

	if bd.pulling ~= spec.fillTrigger.isFilling then
		bd.pulling = spec.fillTrigger.isFilling
		bd.lastTriggerCount = 0
	end

	if #triggers == 0 then
		bd.pickIndex = 1
		bd.orderedTriggers = {}
		bd.knownTriggers   = {}
		BiDirPallets.setCycleVisible(self, false)
		if bd.activeTrigger ~= nil then self:bdpStopPull() end
		bd.pushing = false
		return
	end

	if bd.lastTriggerCount ~= #triggers then
		local was = #bd.orderedTriggers
		for _, tr in ipairs(triggers) do
			if not bd.knownTriggers[tr] then
				bd.orderedTriggers[#bd.orderedTriggers+1] = tr
				bd.knownTriggers[tr] = true
			end
		end
		for i = #bd.orderedTriggers, 1, -1 do
			local kept = false
			for _, tr in ipairs(triggers) do
				if tr == bd.orderedTriggers[i] then kept = true; break end
			end
			if not kept then
				bd.knownTriggers[bd.orderedTriggers[i]] = nil
				table.remove(bd.orderedTriggers, i)
			end
		end
		if was == 0 and #bd.orderedTriggers ~= 0 then
			table.sort(bd.orderedTriggers, compareTriggers)
		end
		if bd.pickIndex > #bd.orderedTriggers then bd.pickIndex = 1 end
	end

	if BiDirSettings.overlayEnabled and bd.hasCovers and (
		bd.lastCoverState  ~= self.spec_cover.state or
		bd.lastPickIndex   ~= bd.pickIndex          or
		bd.lastTriggerCount ~= #triggers ) then
		BiDirPallets.refreshCoverSelection(self)
	end

	if bd.activeTrigger ~= nil and bd.orderedTriggers[bd.pickIndex] ~= nil
	   and bd.orderedTriggers[bd.pickIndex] ~= bd.activeTrigger
	   and bd.activeTrigger.sourceObject ~= nil
	   and bd.activeTrigger.sourceObject.isDeleted then
		BiDirPallets.handleSourceLost(self)
	end

	if BiDirSettings.overlayEnabled and not g_gui:getIsGuiVisible() and isActiveIgnoreSel then
		BiDirPallets.setCycleVisible(self, not bd.pulling)
		BiDirPallets.renderOverlay(self)
	else
		BiDirPallets.setCycleVisible(self, false)
	end

	if bd.pushEnabled then
		BiDirPallets.tickPush(self, dt)
	else
		bd.pushing = false
	end

	if BiDirSettings.multiPallet and bd.pulling then
		BiDirPallets.tickPullMulti(self, dt)
	end

	bd.lastTriggerCount = #triggers
end

function BiDirPallets.setCycleVisible(self, on)
	local bd = self.spec_bidirPallets
	if not bd.actionIds then return end
	local m = bd.actionIds["cyclePick"]
	if m ~= nil then
		g_inputBinding:setActionEventTextVisibility(m.id, on)
		g_inputBinding:setActionEventActive(m.id, on)
	end
end

function BiDirPallets.refreshCoverSelection(self)
	local bd = self.spec_bidirPallets
	local spec = self.spec_fillUnit
	local stateChanged = bd.lastCoverState ~= self.spec_cover.state
	bd.lastCoverState   = self.spec_cover.state
	bd.lastPickIndex    = bd.pickIndex
	bd.lastTriggerCount = #spec.fillTrigger.triggers
	local newCoverOpen = stateChanged and self.spec_cover.state ~= 0

	local openTypes = {}
	if self.spec_cover.state ~= 0 then
		for _, idx in ipairs(self.spec_cover.covers[self.spec_cover.state].fillUnitIndices) do
			local fu = spec.fillUnits[idx]
			if fu.fillLevel < fu.capacity then
				for ft in pairs(fu.supportedFillTypes) do openTypes[ft] = true end
			end
		end
	end

	for index, tr in ipairs(bd.orderedTriggers) do
		if tr.sourceObject ~= nil then
			local src = tr.sourceObject
			local objFt = src.spec_fillUnit.fillUnits[1].fillType
			bd.canFill[src.id] = openTypes[objFt]
			if newCoverOpen and bd.canFill[src.id] then
				newCoverOpen = false
				bd.pickIndex      = index
				bd.activeTrigger  = tr
				spec.fillTrigger.currentTrigger = tr
				spec.fillTrigger.activatable:setFillType(objFt)
			end
		end
	end
end

function BiDirPallets.handleSourceLost(self)
	local bd = self.spec_bidirPallets
	local spec = self.spec_fillUnit
	if not bd.pullEnabled then self:bdpStopPull(); return end

	local nextSrc  = bd.orderedTriggers[bd.pickIndex].sourceObject
	local prevSrc  = bd.activeTrigger.sourceObject
	local nextFt   = nextSrc.spec_fillUnit.fillUnits[1].lastValidFillType
	local prevFt   = prevSrc.spec_fillUnit.fillUnits[1].lastValidFillType

	if nextFt == prevFt then
		if #spec.fillUnits == 1 then bd.canFill[nextSrc.id] = true end
		spec.fillTrigger.activatable:run()
	elseif #bd.orderedTriggers > 0 then
		if #spec.fillUnits == 1 then bd.canFill[nextSrc.id] = nil end
		self:cyclePick()
		if bd.pickIndex == 1 then self:bdpStopPull() end
	end
end

function BiDirPallets.renderOverlay(self)
	local bd = self.spec_bidirPallets
	local useCb = g_gameSettings:getValue(GameSettings.SETTING.USE_COLORBLIND_MODE) or false
	for index, tr in ipairs(bd.orderedTriggers) do
		local src = tr.sourceObject
		if src ~= nil then
			local n = nodeOf(src)
			if n ~= nil then
				local state
				if index == bd.pickIndex then
					if bd.pushEnabled then
						state = (bd.pushing) and "push_active" or "push_idle"
					elseif bd.canFill[src.id] == nil then
						state = "pull_idle"
					elseif bd.canFill[src.id] then
						state = "pull_active"
					else
						state = "pull_bad"
					end
				else
					state = "dim"
				end
				local fl  = src:getFillUnitFillLevel(1) or 0
				local cap = src:getFillUnitCapacity(1) or 0
				local pct = (cap > 0) and (fl / cap * 100) or 0
				local label = (cap > 0)
					and string.format("#%d  %d%%\n%d / %d L", index, pct, fl, cap)
					or  string.format("#%d\n%d L", index, fl)
				local x, y, z = getWorldTranslation(n)
				local size = getCorrectTextSize(0.016)
				Utils.renderTextAtWorldPosition(
					x, y + 1, z, label,
					size, -size * 0.5, pickColour(state, useCb))
			end
		end
	end
end

local function sendTransferEvent(ev)
	if g_server ~= nil then
		ev:run(nil)
	else
		g_client:getServerConnection():sendEvent(ev)
	end
end

local function firstCompatibleSource(p, sources)
	if p.supportedFillTypes == nil then return nil end
	for _, src in ipairs(sources) do
		if p.supportedFillTypes[src.fillType] then return src end
	end
end

function BiDirPallets.tickPush(self, dt)
	local bd = self.spec_bidirPallets
	local sources = vehicleSources(self)
	if #sources == 0 then bd.pushing = false; return end

	local rate = BiDirSettings.pushRate or 600

	bd.pushAccum = bd.pushAccum + (rate * dt / 1000)
	if bd.pushAccum < 0.1 then return end

	bd.pushing = false

	if BiDirSettings.multiPallet then
		local eligible = {}
		for _, tr in ipairs(bd.orderedTriggers) do
			local pallet = tr.sourceObject
			if pallet ~= nil and not pallet.isDeleted then
				local pfu = pallet.spec_fillUnit
				if pfu ~= nil and pfu.fillUnits[1] ~= nil then
					local p = pfu.fillUnits[1]
					local room = (p.capacity or 0) - (p.fillLevel or 0)
					if room > 0.1 then
						local src = firstCompatibleSource(p, sources)
						if src ~= nil then
							eligible[#eligible+1] = { pallet=pallet, room=room, src=src }
						end
					end
				end
			end
		end

		if #eligible == 0 then
			if bd.pushAccum > rate then bd.pushAccum = rate end
			return
		end

		local share = bd.pushAccum / #eligible
		for _, e in ipairs(eligible) do
			local amt = math.min(share, e.room, e.src.level)
			if amt > 0.1 then
				bd.pushAccum = bd.pushAccum - amt
				bd.pushing   = true
				sendTransferEvent(BiDirPushTickEvent.new(self, e.pallet, e.src.idx, amt, e.src.fillType))
			end
		end
		return
	end

	for _, tr in ipairs(bd.orderedTriggers) do
		local pallet = tr.sourceObject
		if pallet ~= nil and not pallet.isDeleted then
			local pfu = pallet.spec_fillUnit
			if pfu ~= nil and pfu.fillUnits[1] ~= nil then
				local p = pfu.fillUnits[1]
				local room = (p.capacity or 0) - (p.fillLevel or 0)
				if room > 0.1 then
					local src = firstCompatibleSource(p, sources)
					if src ~= nil then
						local amt = math.min(bd.pushAccum, room, src.level)
						if amt > 0.1 then
							bd.pushAccum = bd.pushAccum - amt
							bd.pushing   = true
							sendTransferEvent(BiDirPushTickEvent.new(self, pallet, src.idx, amt, src.fillType))
							return
						end
					end
				end
			end
		end
	end

	if bd.pushAccum > rate then bd.pushAccum = rate end
end

function BiDirPallets.tickPullMulti(self, dt)
	local bd = self.spec_bidirPallets
	if not bd.pulling or bd.activeTrigger == nil then return end

	local sp = self.spec_fillUnit
	if sp == nil then return end

	local activeSrc = bd.activeTrigger.sourceObject
	if activeSrc == nil or activeSrc.isDeleted then return end
	local activeFt = activeSrc.spec_fillUnit and activeSrc.spec_fillUnit.fillUnits[1]
	                 and activeSrc.spec_fillUnit.fillUnits[1].lastValidFillType
	if activeFt == nil or activeFt == FillType.UNKNOWN then return end

	local vehFu, vehFuIdx
	for i, fu in ipairs(sp.fillUnits) do
		if fu.supportedFillTypes ~= nil and fu.supportedFillTypes[activeFt]
		   and (fu.fillLevel or 0) < (fu.capacity or 0) then
			vehFu, vehFuIdx = fu, i
			break
		end
	end
	if vehFu == nil then return end

	local rate = BiDirSettings.pushRate or 600
	bd.pullAccum = (bd.pullAccum or 0) + (rate * dt / 1000)
	if bd.pullAccum < 0.1 then return end

	local transferred = false
	for _, tr in ipairs(bd.orderedTriggers) do
		if tr ~= bd.activeTrigger and tr.sourceObject ~= nil and not tr.sourceObject.isDeleted then
			local pallet = tr.sourceObject
			local pfu    = pallet.spec_fillUnit
			if pfu ~= nil and pfu.fillUnits[1] ~= nil
			   and pfu.fillUnits[1].fillType == activeFt then
				local p     = pfu.fillUnits[1]
				local avail = p.fillLevel or 0
				local room  = (vehFu.capacity or 0) - (vehFu.fillLevel or 0)
				if avail > 0.1 and room > 0.1 then
					local amt = math.min(bd.pullAccum, avail, room)
					if amt > 0.1 then
						bd.pullAccum = bd.pullAccum - amt
						sendTransferEvent(BiDirPullTickEvent.new(self, pallet, vehFuIdx, amt, activeFt))
						transferred = true
						if bd.pullAccum < 0.1 then break end
					end
				end
			end
		end
	end

	if not transferred and bd.pullAccum > rate then bd.pullAccum = rate end
end

function BiDirPallets:applyPush(pallet, vehFillUnit, amount, fillType)
	if pallet == nil or pallet.isDeleted then return end

	self:addFillUnitFillLevel(self:getOwnerFarmId(), vehFillUnit,
		-amount, fillType, ToolType.UNDEFINED, nil)

	if pallet.addFillUnitFillLevel ~= nil then
		pallet:addFillUnitFillLevel(pallet:getOwnerFarmId(), 1,
			amount, fillType, ToolType.UNDEFINED, nil)
	end
end

function BiDirPallets:applyPull(pallet, vehFillUnit, amount, fillType)
	if pallet == nil or pallet.isDeleted then return end

	if pallet.addFillUnitFillLevel ~= nil then
		pallet:addFillUnitFillLevel(pallet:getOwnerFarmId(), 1,
			-amount, fillType, ToolType.UNDEFINED, nil)
	end

	self:addFillUnitFillLevel(self:getOwnerFarmId(), vehFillUnit,
		amount, fillType, ToolType.UNDEFINED, nil)
end

function BiDirPallets.dischargeLoad(self, super, xmlFile, key, entry)
	return super(self, xmlFile, key, entry)
end
Dischargeable.loadDischargeNode = Utils.overwrittenFunction(
	Dischargeable.loadDischargeNode, BiDirPallets.dischargeLoad)

function BiDirPallets.fillActivatableRun(self, super)
	local v  = self.vehicle
	local bd = v and v.spec_bidirPallets
	local sp = v and v.spec_fillUnit

	if bd and bd.eligible and bd.orderedTriggers[bd.pickIndex] then
		local src = bd.orderedTriggers[bd.pickIndex].sourceObject
		if src ~= nil then
			if bd.canFill[src.id] == false then
				return super(self)
			else
				v:bdpStartPull(src)
			end
		end
	end

	super(self)

	if bd and bd.eligible then
		if sp.fillTrigger.isFilling then
			bd.activeTrigger = sp.fillTrigger.currentTrigger
			bd.pulling       = true
		else
			bd.pulling = false
		end
	end
end
FillActivatable.run = Utils.overwrittenFunction(FillActivatable.run, BiDirPallets.fillActivatableRun)

function BiDirPallets:openCover(state, fromNet)
	if self.setCoverState then self:setCoverState(state) end
	if self.spec_cover then self.spec_cover.isStateSetAutomatically = true end
	if not fromNet then
		local ev = BiDirCoverEvent.new(self, state)
		if g_server ~= nil then
			g_server:broadcastEvent(ev, nil, nil, self)
		else
			g_client:getServerConnection():sendEvent(ev)
		end
	end
end

function BiDirPallets:stopPull(fromNet)
	local sp = self.spec_fillUnit
	if sp ~= nil then sp.fillTrigger.currentTrigger = nil end
	local bd = self.spec_bidirPallets
	bd.activeTrigger = nil
	bd.pulling       = false
	bd.lastReqId     = 0
	if not fromNet then
		local ev = BiDirPullStopEvent.new(self)
		if g_server ~= nil then
			g_server:broadcastEvent(ev, nil, nil, self)
		else
			g_client:getServerConnection():sendEvent(ev)
		end
	end
end

function BiDirPallets:startPull(pallet, fromNet)
	local sp = self.spec_fillUnit
	local found = false

	for index, tr in ipairs(sp.fillTrigger.triggers) do
		if tr.sourceObject ~= nil and tr.sourceObject.id == pallet.id then
			found = true
			if index ~= 1 then
				table.insert(sp.fillTrigger.triggers, 1, tr)
				table.remove(sp.fillTrigger.triggers, index + 1)
				sp.fillTrigger.currentTrigger = sp.fillTrigger.triggers[1]
			end
			break
		end
	end

	if not found then
		Logging.warning("[BiDirPallets] pallet id %s not in trigger list",
			tostring(pallet.id))
		return
	end

	if not fromNet and self.spec_bidirPallets.lastReqId ~= pallet.id then
		self.spec_bidirPallets.lastReqId = pallet.id
		local ev = BiDirPullStartEvent.new(self, pallet)
		if g_server ~= nil then
			g_server:broadcastEvent(ev, nil, nil, self)
		else
			g_client:getServerConnection():sendEvent(ev)
		end
	end
end

function BiDirPallets:onUnloadAction()
	if self.spec_bidirPallets ~= nil then
		local sp = self.spec_fillUnit
		if sp.fillTrigger.isFilling then
			self:setFillUnitIsFilling(false)
			self.spec_bidirPallets.pulling   = false
			self.spec_bidirPallets.lastReqId = 0
		end
	end
end
FillUnit.actionEventUnload = Utils.prependedFunction(
	FillUnit.actionEventUnload, BiDirPallets.onUnloadAction)

do
	local md = loadXMLFile("modDesc", g_currentModDirectory .. "modDesc.xml")
	local i  = 0
	while true do
		local k = ("modDesc.l10n.text(%d)"):format(i)
		if not hasXMLProperty(md, k) then break end
		local n = getXMLString(md, k .. "#name")
		local t = getXMLString(md, k .. "." .. g_languageShort)
		if n ~= nil then g_i18n:setText(n, t or "") end
		i = i + 1
	end
end
