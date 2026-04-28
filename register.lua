g_specializationManager:addSpecialization(
	"bidirPallets", "BiDirPallets",
	Utils.getFilename("BiDirPallets.lua", g_currentModDirectory), nil)

TypeManager.validateTypes = Utils.appendedFunction(TypeManager.validateTypes,
	function(self)
		if self.typeName ~= "vehicle" then return end
		for name, t in pairs(g_vehicleTypeManager.types) do
			if SpecializationUtil.hasSpecialization(FillUnit,   t.specializations)
			   and SpecializationUtil.hasSpecialization(FillVolume, t.specializations) then
				g_vehicleTypeManager:addSpecialization(name,
					BiDirPallets.MOD_NAME .. ".bidirPallets")
			end
		end
	end)
