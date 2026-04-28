local function makeEvent(name)
	local cls = {}
	cls.__name = name
	cls._mt = Class(cls, Event)
	InitEventClass(cls, name)
	cls.emptyNew = function() return Event.new(cls._mt) end
	return cls
end

BiDirCoverEvent = makeEvent("BiDirCoverEvent")

function BiDirCoverEvent.new(vehicle, state)
	local e = BiDirCoverEvent.emptyNew()
	e.vehicle, e.state = vehicle, state
	return e
end

function BiDirCoverEvent:writeStream(s, c)
	if c:getIsServer() then
		NetworkUtil.writeNodeObject(s, self.vehicle)
		streamWriteInt32(s, self.state)
	end
end

function BiDirCoverEvent:readStream(s, c)
	if not c:getIsServer() then
		self.vehicle = NetworkUtil.readNodeObject(s)
		self.state   = streamReadInt32(s)
	end
	self:run(c)
end

function BiDirCoverEvent:run(c)
	if not c:getIsServer() and self.vehicle ~= nil then
		self.vehicle:bdpOpenCover(self.state, true)
	end
end

BiDirPullStartEvent = makeEvent("BiDirPullStartEvent")

function BiDirPullStartEvent.new(vehicle, pallet)
	local e = BiDirPullStartEvent.emptyNew()
	e.vehicle, e.pallet = vehicle, pallet
	return e
end

function BiDirPullStartEvent:writeStream(s, c)
	if c:getIsServer() then
		NetworkUtil.writeNodeObject(s, self.vehicle)
		NetworkUtil.writeNodeObject(s, self.pallet)
		local has = self.vehicle.spec_bidirPallets ~= nil
		streamWriteBool(s, has)
		if has then
			streamWriteBool(s, self.vehicle.spec_bidirPallets.pulling)
			streamWriteInt32(s, self.vehicle.spec_bidirPallets.pickIndex)
		end
	end
end

function BiDirPullStartEvent:readStream(s, c)
	if not c:getIsServer() then
		self.vehicle = NetworkUtil.readNodeObject(s)
		self.pallet  = NetworkUtil.readNodeObject(s)
		if streamReadBool(s) and self.vehicle ~= nil then
			self.vehicle.spec_bidirPallets.pulling   = streamReadBool(s)
			self.vehicle.spec_bidirPallets.pickIndex = streamReadInt32(s)
		end
	end
	self:run(c)
end

function BiDirPullStartEvent:run(c)
	if not c:getIsServer() and self.vehicle ~= nil and self.pallet ~= nil then
		self.vehicle:bdpStartPull(self.pallet, true)
	end
end

BiDirPullStopEvent = makeEvent("BiDirPullStopEvent")

function BiDirPullStopEvent.new(vehicle)
	local e = BiDirPullStopEvent.emptyNew()
	e.vehicle = vehicle
	return e
end

function BiDirPullStopEvent:writeStream(s, c)
	if c:getIsServer() then NetworkUtil.writeNodeObject(s, self.vehicle) end
end

function BiDirPullStopEvent:readStream(s, c)
	if not c:getIsServer() then
		self.vehicle = NetworkUtil.readNodeObject(s)
		if self.vehicle ~= nil then
			local bd = self.vehicle.spec_bidirPallets
			if bd ~= nil then
				bd.pulling = false
				bd.activeTrigger = nil
			end
			if self.vehicle.spec_fillUnit ~= nil then
				self.vehicle.spec_fillUnit.fillTrigger.currentTrigger = nil
			end
		end
	end
	self:run(c)
end

function BiDirPullStopEvent:run(c)
	if not c:getIsServer() and self.vehicle ~= nil then
		self.vehicle:bdpStopPull(true)
	end
end

BiDirPushTickEvent = makeEvent("BiDirPushTickEvent")

function BiDirPushTickEvent.new(vehicle, pallet, vehFillUnit, amount, fillType)
	local e = BiDirPushTickEvent.emptyNew()
	e.vehicle     = vehicle
	e.pallet      = pallet
	e.vehFillUnit = vehFillUnit
	e.amount      = amount
	e.fillType    = fillType
	return e
end

function BiDirPushTickEvent:writeStream(s, c)
	NetworkUtil.writeNodeObject(s, self.vehicle)
	NetworkUtil.writeNodeObject(s, self.pallet)
	streamWriteUInt8(s,  self.vehFillUnit)
	streamWriteFloat32(s, self.amount)
	streamWriteUIntN(s,  self.fillType, FillTypeManager.SEND_NUM_BITS)
end

function BiDirPushTickEvent:readStream(s, c)
	self.vehicle     = NetworkUtil.readNodeObject(s)
	self.pallet      = NetworkUtil.readNodeObject(s)
	self.vehFillUnit = streamReadUInt8(s)
	self.amount      = streamReadFloat32(s)
	self.fillType    = streamReadUIntN(s, FillTypeManager.SEND_NUM_BITS)
	self:run(c)
end

function BiDirPushTickEvent:run(c)
	if g_server ~= nil then
		if self.vehicle ~= nil and self.pallet ~= nil then
			self.vehicle:bdpApplyPush(self.pallet, self.vehFillUnit, self.amount, self.fillType)
		end
		g_server:broadcastEvent(self, false, c, self.vehicle)
	else
		if self.vehicle ~= nil and self.pallet ~= nil then
			self.vehicle:bdpApplyPush(self.pallet, self.vehFillUnit, self.amount, self.fillType)
		end
	end
end

BiDirPullTickEvent = makeEvent("BiDirPullTickEvent")

function BiDirPullTickEvent.new(vehicle, pallet, vehFillUnit, amount, fillType)
	local e = BiDirPullTickEvent.emptyNew()
	e.vehicle     = vehicle
	e.pallet      = pallet
	e.vehFillUnit = vehFillUnit
	e.amount      = amount
	e.fillType    = fillType
	return e
end

function BiDirPullTickEvent:writeStream(s, c)
	NetworkUtil.writeNodeObject(s, self.vehicle)
	NetworkUtil.writeNodeObject(s, self.pallet)
	streamWriteUInt8(s,   self.vehFillUnit)
	streamWriteFloat32(s, self.amount)
	streamWriteUIntN(s,   self.fillType, FillTypeManager.SEND_NUM_BITS)
end

function BiDirPullTickEvent:readStream(s, c)
	self.vehicle     = NetworkUtil.readNodeObject(s)
	self.pallet      = NetworkUtil.readNodeObject(s)
	self.vehFillUnit = streamReadUInt8(s)
	self.amount      = streamReadFloat32(s)
	self.fillType    = streamReadUIntN(s, FillTypeManager.SEND_NUM_BITS)
	self:run(c)
end

function BiDirPullTickEvent:run(c)
	if g_server ~= nil then
		if self.vehicle ~= nil and self.pallet ~= nil then
			self.vehicle:bdpApplyPull(self.pallet, self.vehFillUnit, self.amount, self.fillType)
		end
		g_server:broadcastEvent(self, false, c, self.vehicle)
	else
		if self.vehicle ~= nil and self.pallet ~= nil then
			self.vehicle:bdpApplyPull(self.pallet, self.vehFillUnit, self.amount, self.fillType)
		end
	end
end
