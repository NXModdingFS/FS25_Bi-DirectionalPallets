BiDirSettings = {}
BiDirSettings.SETTINGS = {}
BiDirSettings.CONTROLS = {}

BiDirSettings.SETTINGS.overlayEnabled = {
	["default"] = 1,
	["values"]  = { true, false },
	["strings"] = {
		g_i18n:getText("bidir_setting_overlay_on"),
		g_i18n:getText("bidir_setting_overlay_off"),
	}
}

BiDirSettings.SETTINGS.pushRate = {
	["default"] = 3,
	["values"]  = { 150, 300, 600, 1000, 1500, 2500 },
	["strings"] = { "150 L/s", "300 L/s", "600 L/s", "1000 L/s", "1500 L/s", "2500 L/s" },
}

BiDirSettings.SETTINGS.multiPallet = {
	["default"] = 2,
	["values"]  = { true, false },
	["strings"] = {
		g_i18n:getText("bidir_setting_multi_on"),
		g_i18n:getText("bidir_setting_multi_off"),
	}
}

BiDirSettings.overlayEnabled = true
BiDirSettings.pushRate       = 600
BiDirSettings.multiPallet    = false

function BiDirSettings.setValue(id, value)
	BiDirSettings[id] = value
end

function BiDirSettings.getValue(id)
	return BiDirSettings[id]
end

function BiDirSettings.getStateIndex(id, value)
	local v = value or BiDirSettings.getValue(id)
	if type(v) == "boolean" then return v and 1 or 2 end
	if type(v) == "number" then
		for i, val in ipairs(BiDirSettings.SETTINGS[id].values) do
			if val == v then return i end
		end
	end
	return BiDirSettings.SETTINGS[id].default
end

BiDirControls = {}

function BiDirControls:onMenuOptionChanged(state, menuOption)
	local id    = menuOption.id
	local s     = BiDirSettings.SETTINGS[id]
	local value = s and s.values[state]
	if value ~= nil then
		BiDirSettings.setValue(id, value)
		BiDirSettings.saveSettings()
	end
end

function BiDirSettings.loadSettings()
	local path = Utils.getFilename("modSettings/BiDirPalletsSettings.xml", getUserProfileAppPath())
	if not fileExists(path) then return end
	local xml = loadXMLFile("BiDirSettingsXML", path)
	if xml == 0 then return end
	local v = getXMLBool(xml, "bidir.settings#overlayEnabled")
	if v ~= nil then BiDirSettings.setValue("overlayEnabled", v) end
	local r = getXMLInt(xml, "bidir.settings#pushRate")
	if r ~= nil then BiDirSettings.setValue("pushRate", r) end
	local m = getXMLBool(xml, "bidir.settings#multiPallet")
	if m ~= nil then BiDirSettings.setValue("multiPallet", m) end
	delete(xml)
end

function BiDirSettings.saveSettings()
	local path = Utils.getFilename("modSettings/BiDirPalletsSettings.xml", getUserProfileAppPath())
	createFolder(getUserProfileAppPath() .. "modSettings/")
	local xml
	if fileExists(path) then
		xml = loadXMLFile("BiDirSettingsXML", path)
	else
		xml = createXMLFile("BiDirSettingsXML", path, "bidir")
	end
	if xml == 0 then
		Logging.warning("[BiDirPallets] failed to open settings xml")
		return
	end
	setXMLBool(xml, "bidir.settings#overlayEnabled", BiDirSettings.overlayEnabled)
	setXMLInt(xml,  "bidir.settings#pushRate",       BiDirSettings.pushRate)
	setXMLBool(xml, "bidir.settings#multiPallet",    BiDirSettings.multiPallet)
	saveXMLFile(xml)
	delete(xml)
end

local function updateFocusIds(element)
	if not element then return end
	element.focusId = FocusManager:serveAutoFocusId()
	for _, child in pairs(element.elements or {}) do
		updateFocusIds(child)
	end
end

function BiDirSettings.injectMenu()
	local inGameMenu = g_gui.screenControllers[InGameMenu]
	if not inGameMenu then return end
	local settingsPage = inGameMenu.pageSettings
	if not settingsPage then return end
	local layout = settingsPage.gameSettingsLayout
	if not layout then return end

	local sectionTitle
	for _, elem in ipairs(layout.elements) do
		if elem.name == "sectionHeader" then
			sectionTitle = elem:clone(layout)
			break
		end
	end
	if sectionTitle then
		sectionTitle:setText(g_i18n:getText("bidir_menu_section_title"))
	else
		sectionTitle = TextElement.new()
		sectionTitle:applyProfile("fs25_settingsSectionHeader", true)
		sectionTitle:setText(g_i18n:getText("bidir_menu_section_title"))
		sectionTitle.name = "sectionHeader"
		layout:addElement(sectionTitle)
	end
	sectionTitle.focusId = FocusManager:serveAutoFocusId()
	table.insert(settingsPage.controlsList, sectionTitle)
	BiDirSettings.CONTROLS["sectionHeader"] = sectionTitle

	local originalBox = settingsPage.multiVolumeVoiceBox
	if not originalBox then return end

	local function createOption(id, titleKey, tooltipKey)
		local box = originalBox:clone(layout)
		box.id = id .. "Box"
		local option = box.elements[1]
		option.id     = id
		option.target = BiDirControls
		option:setCallback("onClickCallback", "onMenuOptionChanged")
		option:setDisabled(false)
		local toolTip = option.elements[1]
		toolTip:setText(g_i18n:getText(tooltipKey))
		box.elements[2]:setText(g_i18n:getText(titleKey))
		option:setTexts(BiDirSettings.SETTINGS[id].strings)
		option:setState(BiDirSettings.getStateIndex(id))
		BiDirSettings.CONTROLS[id] = option
		updateFocusIds(box)
		table.insert(settingsPage.controlsList, box)
	end

	createOption("overlayEnabled", "bidir_menu_overlay",      "bidir_menu_overlay_tooltip")
	createOption("pushRate",       "bidir_menu_push_rate",    "bidir_menu_push_rate_tooltip")
	createOption("multiPallet",    "bidir_menu_multi_pallet", "bidir_menu_multi_pallet_tooltip")

	layout:invalidateLayout()
end

Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, function()
	BiDirSettings.loadSettings()
	BiDirSettings.injectMenu()
end)
