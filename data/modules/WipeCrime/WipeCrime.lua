-- Copyright © 2008-2015 Pioneer Developers. See AUTHORS.txt for details
-- Licensed under the terms of the GPL v3. See licenses/GPL-3.txt

-- TODO: check spawning of ship

local Engine = import("Engine")
local Lang = import("Lang")
local Game = import("Game")
local Comms = import("Comms")
local Character = import("Character")
local Event = import("Event")
local Serializer = import("Serializer")
local Format = import("Format")
local Timer = import("Timer")
local utils = import("utils")
local ShipDef = import("ShipDef")
local Equipment = import("Equipment")
local Space = import("Space")
local Ship = import("Ship")

local l = Lang.GetResource("module-wipecrime")


-- Global Settings
local max_faction_dist = 50    -- max distance in ly of how far out faction crime can be cleared


-- Global Variables
local scheduled_services = {}  -- services payed for and in process {factionID = {"record", "fine"}}
local crime_types = {TRADING_ILLEGAL_GOODS  = l.TRADING_ILLEGAL_GOODS,
		     WEAPONS_DISCHARGE      = l.WEAPONS_DISCHARGE,
		     PIRACY                 = l.PIRACY,
		     MURDER                 = l.MURDER,
		     DUMPING                = l.DUMPING}

local flavours = {}
for i = 0,0 do
	table.insert(flavours, {
		             title     = l["FLAVOUR_" .. i .. "_TITLE"],
		             message   = l["FLAVOUR_" .. i .. "_MESSAGE"],
	})
end

local ads = {}


-- basic lua helper functions
-- ==========================

local containerContainsValue = function (container, value)
	-- Return true if value is in container and false if not.
	for _,k in pairs(container) do
		if k == value then
			return true
		end
	end
	return false
end


-- mission functions
-- =================

local getNumberOfFlavours = function (str)
	-- Returns the number of flavours of the given string (assuming first flavour has suffix '_1').
	-- Taken from CargoRun.lua.
	local num = 1
	while l[str .. "_" .. num] do
		num = num + 1
	end
	return num - 1
end

local getNearbyFactions = function (system)
	-- Return all represented factions with a certain radius from local system.
	local nearbysystems = system:GetNearbySystems(max_faction_dist)
	local nearbyfactions = {}
	for _,system in pairs(nearbysystems) do
		if not containerContainsValue(nearbyfactions, system.faction) then
			table.insert(nearbyfactions, system.faction)
		end
	end
	return nearbyfactions
end

local getFaction = function (ad, factionid)
	-- Return faction object of supplied faction id.
	local nearbyfactions = getNearbyFactions(ad.station.path:GetStarSystem())
	for _,faction in pairs(nearbyfactions) do
		if faction.id == factionid then return faction end
	end
end

local getNearbySystemPaths = function ()
	-- Return list of nearby system paths with stations sorted by distance from player system (ascending).
	local nearbysystems_raw = Game.system:GetNearbySystems(max_faction_dist, function (s) return #s:GetStationPaths() > 0 end)

	-- determine distance to player system
	local nearbysystems_dist = {}
	for _,system in pairs(nearbysystems_raw) do
		local dist = Game.system:DistanceTo(system)
		table.insert(nearbysystems_dist, {system, dist})
	end

	-- sort systems by distance to player system (ascending)
	local nearbysystems = {}
	table.sort(nearbysystems_dist, function (a,b) return a[2] < b[2] end)
	for _,data in ipairs(nearbysystems_dist) do
		table.insert(nearbysystems, data[1].path)
	end
	return nearbysystems
end

local getFactionDistance = function (ad, factionid)
	-- Return distance [ly] and closest system belonging to supplied faction (with stations).
	local faction = getFaction(ad, factionid)

	-- if current system belongs to faction
	if Game.system.faction == faction then return 0, Game.system.path end

	-- select nearby systems belonging to the supplied faction
	local nearbysystems_raw = Game.system:GetNearbySystems(max_faction_dist, function (system)
		                                                       return system.faction == faction and
		                                                       #system:GetStationPaths() > 0 end)

	-- determine minimum distance to faction
	local min_dist = 0
	local min_systempath
	for _,system in pairs(nearbysystems_raw) do
		local dist = Game.system:DistanceTo(system)
		if dist > min_dist then
			min_dist = dist
			min_systempath = system.path
		end
	end

	return min_dist, min_systempath
end

local getCompletionDate = function (ad, factionid)
	-- Return date when service will be complete. Dependent on faction distance and whether company
	-- ship availability.
	local dist, systempath = getFactionDistance(ad, factionid)
	local time = Game.time + (5 * dist + 4) * Engine.rand:Integer(20,24) * 60 * 60
	if ad.ship_available then
		return time
	else
		return time * 2
	end
end

local getCashToPay = function(service_type, ad, factionid, criminalRecord, crime_fine)
	-- Calculate the fees for service.
	local dist, systempath = getFactionDistance(ad, factionid)

	-- base fee for fine and crime record removal
	local fine
	if service_type == "history" then
		fine = 1000
	else
		fine = crime_fine * 0.5
	end

	-- adjusted for distance to faction
	fine = fine + (0.25 * fine * (dist/max_faction_dist))
	return fine
end

local getAllPlayerCrime = function (ad)
	-- Returns the crime record/fine for each nearby faction - if there is one and if
	-- it has not already been marked for removal.
	-- TODO: Check if "fine" is returned as 0 or nil
	local factionRecords = {}
	local factionOutstandings = {}
	local factions = getNearbyFactions(ad.station.path:GetStarSystem())

	for _,faction in pairs(factions) do

		-- if criminal history exists for faction, save
		local criminalRecord, fine = Game.player:GetCrimeRecord(faction)

		if next(criminalRecord) then

			-- if there is already a service active to remove the crime history (but delayed) then don't offer again
			if scheduled_services[faction.id] and scheduled_services[faction.id].record then break end

			local factionRecord = {factionid      = faction.id,
			                       factionname    = faction.name,
			                       criminalRecord = criminalRecord,
			                       fine           = fine,
			                       cash           = getCashToPay("history", ad, faction.id, criminalRecord, fine)}
			table.insert(factionRecords, factionRecord)
		end

		-- if outstanding fine exists for faction, save
		criminalRecord, fine = Game.player:GetCrimeOutstanding(faction)

		if fine > 0 then

			-- if there is already a service active to remove the fine (but delayed) then don't offer again
			if scheduled_services[faction.id] and scheduled_services[faction.id].fine then break end

			local factionOutstanding = {factionid      = faction.id,
			                            factionname    = faction.name,
			                            criminalRecord = criminalRecord,
			                            fine           = fine,
			                            cash           = getCashToPay("fine", ad, faction.id, criminalRecord, fine)}
			table.insert(factionOutstandings, factionOutstanding)
		end
	end

	return factionRecords, factionOutstandings
end

local getShip = function (station, incoming)
	-- Spawn a ship at the station.
	local shipdefs = utils.build_array(utils.filter(function (_,def) return def.tag == 'SHIP' and
				                                   def.hullMass < 100 and
				                                   def.hyperdriveClass > 0 and
				                                   def.equipSlotCapacity.atmo_shield > 0 and
				                                   def.basePrice > 0
	                                                end, pairs(ShipDef)))
	local shipdef = shipdefs[Engine.rand:Integer(1, #shipdefs)]

	local ship
	if incoming then
		ship = Space.SpawnShipNear(shipdef.id, station, 10000, 10000)
	else
		ship = Space.SpawnShipDocked(shipdef.id, station)
	end

	-- load a hyperdrive
	local default_drive = Equipment.hyperspace['hyperdrive_'..tostring(shipdef.hyperdriveClass)]
	if default_drive then
		ship:AddEquip(default_drive)
	else
		local drive
		for i = 9, 1, -1 do
			drive = Equipment.hyperspace['hyperdrive_'..tostring(i)]
			if shipdef.capacity / 10 > drive.capabilities.mass then
				ship:AddEquip(drive)
				break
			end
		end
		if not drive then
			ship:AddEquip(Equipment.hyperspace['hyperdrive_1'])
		end
	end

	-- add thruster fuel and hypfuel
	ship:SetFuelPercent(100)
	local drive = ship:GetEquip('engine', 1)
	local hypfuel = drive.capabilities.hyperclass ^ 2  -- fuel for max range
	ship:AddEquip(Equipment.cargo.hydrogen, hypfuel)

	-- load a laser
	local max_laser_size
	if default_drive then
		max_laser_size = shipdef.capacity - default_drive.capabilities.mass
	else
		max_laser_size = shipdef.capacity
	end
	local laserdefs = utils.build_array(utils.filter(function (_,laser) return laser:IsValidSlot('laser_front')
				                                    and laser.capabilities.mass <= max_laser_size
			                                    and laser.l10n_key:find("PULSECANNON") end, pairs(Equipment.laser)))
	local laserdef = laserdefs[Engine.rand:Integer(1,#laserdefs)]
	ship:AddEquip(laserdef)

	-- load atmo_shield
	ship:AddEquip(Equipment.misc.atmospheric_shielding)

	-- label
	ship:SetLabel(Ship.MakeRandomLabel())

	-- if incoming then set course for station
	if incoming then ship:AIDockWith(station) end

	return ship
end

local launchShip  -- need to declare here for use in startTimer function
local startTimer = function (ad, timerindex, args)
	-- Start any kind of timer. Timers are sequestered here to allow restarting
	-- them after save/re-load.
	if args.timertype == "hyperjump" then
		Timer:CallAt(args.time, function ()
			             args.ship:HyperjumpTo(args.systempath)
			             ad.timers[timerindex] = nil
		end)
	elseif args.timertype == "launchship" then
		Timer:CallAt(args.time, function ()
			             launchShip(ad, args.ship, args.station)
			             ad.timers[timerindex] = nil
		end)
	elseif args.timertype == "removecrimerecord" then
		Timer:CallAt(args.time, function ()
			             local faction = getFaction(ad, args.factionid)
			             Game.player:ClearCrimeRecordHistory(faction)
			             if scheduled_services[args.factionid].fine then
				             scheduled_services[args.factionid].record = nil
			             else
				             scheduled_services[args.factionid] = nil
			             end
			             ad.timers[timerindex] = nil
		end)
	elseif args.timertype == "removecrimefine" then
		Timer:CallAt(args.time, function ()
			             local faction = getFaction(ad, args.factionid)
			             Game.player:ClearCrimeFine(faction, true)
			             if scheduled_services[args.factionid].record then
				             scheduled_services[args.factionid].fine = nil
			             else
				             scheduled_services[args.factionid] = nil
			             end
			             ad.timers[timerindex] = nil
		end)
	end
end

local removeShip = function (ad, ship)
	-- Remove ship from any script specific containers after hyperjump.
	if ship == ad.ship_available then
		ad.ship_available = nil
	elseif ad.ships_outgoing[ship] then
		table.remove(ad.ships_outgoing, ship)
	end
end

-- declared locally before
function launchShip (ad, ship, station)
	-- Launch the supplied ship and hyperjump to the nearest target system.
	-- If the current system is the same as the target system send
	-- ship to a random base within the system.

	-- assign current target systems to ship and select random target system
	-- if no more target hyp ship away to random close system
	local target_systems, systempath
	if ship == ad.ship_available then
		target_systems = ad.target_systems
		ad.target_systems = {}
		ad.ship_available = nil
	else
		target_systems = ad.ships_outgoing[ship]
	end
	if #target_systems > 0 then
		local i = Engine.rand:Integer(1,#target_systems)
		systempath = target_systems[i]
		table.remove(target_systems, i)
		ad.ships_outgoing[ship] = target_systems
	else
		systempath = nil
	end

	-- if current system is equal to target system
	if systempath == Game.system.path then
		local stationpaths = Game.system:GetStationPaths()
		for i,s in pairs(stationpaths) do
			if s == station.path then table.remove(stationpaths, i) end
			break
		end
		local goal_station_path = stationpaths[Engine.rand:Integer(1,#stationpaths)]
		ship:AIDockWith(Space.GetBody(goal_station_path.bodyIndex))

		-- if no more target system to fly to send ship away
	elseif systempath == nil then
		local nearbysystempaths = getNearbySystemPaths()
		nearbysystempath = nearbysystempaths[1]
		ship:AIEnterLowOrbit(ship:FindNearestTo("STAR"))
		local timer_args = {timertype  = "hyperjump",
		                    time       = Game.time + 10,
		                    ship       = ship,
		                    systempath = nearbysystempath}
		table.insert(ad.timers, timer_args)
		startTimer(ad, #ad.timers, timer_args)

		-- if current system is different from target system
	else
		ship:AIEnterLowOrbit(ship:FindNearestTo("STAR"))
		local timer_args = {timertype  = "hyperjump",
		                    time       = Game.time + 10,
		                    ship       = ship,
		                    systempath = systempath}
		table.insert(ad.timers, timer_args)
		startTimer(ad, #ad.timers, timer_args)
	end
end

local onChat = function (form, ref, option)
	local ad = ads[ref]

	-- get current crime/fine stats every time chat changes
	local factionRecords, factionOutstandings = getAllPlayerCrime(ad)

	-- close chat
	if option == -1 then
		form:Close()
		return

			-- show level-1 chat screen
	elseif option == 0 then
		form:Clear()

		-- if no crime don't offer service
		if #factionRecords == 0 and #factionOutstandings == 0 then
			form:SetFace({ seed = ad.faceseed })
			form:SetTitle(ad.title)
			form:SetMessage(l.WE_HAVE_NO_BUSINESS_WITH_YOU)
			return
		end

		form:SetFace({ seed = ad.faceseed })
		form:SetTitle(ad.title)
		form:SetMessage(ad.message)

		form:AddOption(l.ERASE_CRIME_HISTORY, 1)
		form:AddOption(l.PAY_FINE, 2)
		form:AddOption(l.HOW_CAN_YOU_PULL_THIS_OFF, 3)
		return

			-- how can you pull this of chat (level-2)
	elseif option == 3 then
		form:SetMessage(ad.method_txt)
		return

			-- erase crime history chat (level-2)
	elseif option == 1 then
		form:Clear()
		form:SetTitle(ad.title)

		-- abort if no crime history found
		if #factionRecords == 0 then
			form:SetTitle(ad.title)
			form:SetMessage(l.NO_CRIME_HISTORY)
			form:AddOption(l.BACK_TO_SERVICE_SELECTION, 0)
			return
		end

		-- configure form text depending on factions with crime history
		local message_text = l.ERASE_CRIME_HISTORY_MESSAGE .. "\n"
		for i,factionRecord in pairs(factionRecords) do
			message_text = message_text .. "\n" .. factionRecord.factionname .. ":\n\n"
			for crime,count in pairs(factionRecord.criminalRecord) do
				message_text = message_text .. count.count .. " " .. crime_types[crime] .. "\n"
			end
		end
		form:SetMessage(message_text)

		-- configure options (buttons) depending on factions with outstanding fines
		for i,factionRecord in pairs(factionRecords) do
			local text = string.interp(l.ERASE_CRIME_HISTORY_OPTION,
			                           {faction = factionRecord.factionname,
			                            cash = Format.Money(factionRecord.cash)})
			form:AddOption(text, 100+i)
		end

		form:AddOption(l.BACK_TO_SERVICE_SELECTION, 0)
		return

			-- erase crime fine chat (level-2)
	elseif option == 2 then
		form:Clear()
		form:SetTitle(ad.title)

		-- abort if no fine found
		if #factionOutstandings == 0 then
			form:SetTitle(ad.title)
			form:SetMessage(l.NO_FINE)
			form:AddOption(l.BACK_TO_SERVICE_SELECTION, 0)
			return
		end

		-- configure form text depending on factions with outstanding fines
		local message_text = l.PAY_FINE_MESSAGE .. "\n"
		for i,factionOutstanding in pairs(factionOutstandings) do
			message_text = message_text .. "\n" .. factionOutstanding.factionname .. ":\n\n"
			for crime,count in pairs(factionOutstanding.criminalRecord) do
				message_text = message_text .. count.count .. " " .. crime_types[crime] .. "\n"
			end
		end
		form:SetMessage(message_text)

		-- configure options (buttons) depending on factions with outstanding fines
		for i,factionOutstanding in pairs(factionOutstandings) do
			local text = string.interp(l.PAY_FINE_OPTION,
			                           {faction = factionOutstanding.factionname,
			                            fine = Format.Money(factionOutstanding.fine),
			                            cash = Format.Money(factionOutstanding.cash)})
			form:AddOption(text, 200+i)
		end

		form:AddOption(l.BACK_TO_SERVICE_SELECTION, 0)
		return

			-- erase crime record
	elseif option > 100 and option < 200 then
		form:Clear()
		local factionRecord = factionRecords[option-100]
		local completionDate = getCompletionDate(ad, factionRecord.factionid)

		-- abort if not enough money
		if Game.player:GetMoney() < factionRecord.cash then
			form:SetTitle(ad.title)
			form:SetMessage(l.YOU_DONT_HAVE_ENOUGH_MONEY)
			form:AddOption(l.BACK_TO_SERVICE_SELECTION, 0)
			return
		end

		local text
		if ad.ship_available then
			text = string.interp(l.SEND_IMMEDIATELY .. " " .. l.CRIME_HISTORY_ERASED_BY,
			                     {shiplabel = ad.ship_available.label,
			                      faction = factionRecord.factionname,
			                      date = string.sub(Format.Date(completionDate+24*60*60), 10, -1)})
		else
			if not ad.ship_incoming then ad.ship_incoming = getShip(ad.station, true) end
			text = string.interp(l.SEND_WITH_DELAY .. " " .. l.CRIME_HISTORY_ERASED_BY,
			                     {shiplabel = ad.ship_incoming.label,
			                      faction = factionRecord.factionname,
			                      date = string.sub(Format.Date(completionDate+24*60*60), 10, -1)})
		end
		form:SetTitle(ad.title)
		form:SetMessage(text)

		-- subtract fee from player cash
		Game.player:AddMoney(-factionRecord.cash)

		-- add selected service to scheduled services and closest faction system to target systems
		if not scheduled_services[factionRecord.factionid] then
			scheduled_services[factionRecord.factionid] = {record = true}
		else
			scheduled_services[factionRecord.factionid].record = true
		end
		local dist, systempath = getFactionDistance(ad, factionRecord.factionid)
		table.insert(ad.target_systems, systempath)

		-- send ship if applicable
		if ad.ship_available then
			local timer_args = {timertype  = "launchship",
			                    time       = Game.time + (Engine.rand:Integer(1,5) * 60),
			                    ship       = ad.ship_available,
			                    station    = ad.station}
			table.insert(ad.timers, timer_args)
			startTimer(ad, #ad.timers, timer_args)
		end

		-- after time remove crime record and scheduled service
		local timer_args = {timertype  = "removecrimerecord",
		                    time       = completionDate,
		                    factionid  = factionRecord.factionid}
		table.insert(ad.timers, timer_args)
		startTimer(ad, #ad.timers, timer_args)

		form:AddOption(l.BACK_TO_SERVICE_SELECTION, 0)
		return

			-- pay fine
	elseif option > 200 then
		form:Clear()
		local factionOutstanding = factionOutstandings[option-200]
		local completionDate = getCompletionDate(ad, factionOutstanding.factionid)

		-- abort if not enough money
		if Game.player:GetMoney() < factionOutstanding.cash then
			form:SetTitle(ad.title)
			form:SetMessage(l.YOU_DONT_HAVE_ENOUGH_MONEY)
			return
		end

		local text
		if ad.ship_available then
			text = string.interp(l.SEND_IMMEDIATELY .. " " .. l.FINE_PAYED_BY,
			                     {shiplabel = ad.ship_available.label,
			                      faction = factionOutstanding.factionname,
			                      date = string.sub(Format.Date(completionDate+24*60*60), 10, -1)})
		else
			if not ad.ship_incoming then ad.ship_incoming = getShip(ad.station, true) end
			text = string.interp(l.SEND_WITH_DELAY .. " " .. l.FINE_PAYED_BY,
			                     {shiplabel = ad.ship_incoming.label,
			                      faction = factionOutstanding.factionname,
			                      date = string.sub(Format.Date(completionDate+24*60*60), 10, -1)})
		end
		form:SetTitle(ad.title)
		form:SetMessage(text)

		-- remove fee from player cash
		Game.player:AddMoney(-factionOutstanding.cash)

		-- add selected service to scheduled services and faction to target factions
		if not scheduled_services[factionOutstanding.factionid] then
			scheduled_services[factionOutstanding.factionid] = {fine = true}
		else
			scheduled_services[factionOutstanding.factionid].fine = true
		end
		local dist, systempath = getFactionDistance(ad, factionOutstanding.factionid)
		table.insert(ad.target_systems, systempath)

		-- send ship if applicable
		if ad.ship_available then
			local timer_args = {timertype  = "launchship",
			                    time       = Game.time + (Engine.rand:Integer(1,5) * 60),
			                    ship       = ad.ship_available,
			                    station    = ad.station}
			table.insert(ad.timers, timer_args)
			startTimer(ad, #ad.timers, timer_args)
		end

		-- after time remove fine and scheduled service
		local timer_args = {timertype  = "removecrimefine",
		                    time       = completionDate,
		                    factionid  = factionOutstanding.factionid}
		table.insert(ad.timers, timer_args)
		startTimer(ad, #ad.timers, timer_args)
		form:AddOption(l.BACK_TO_SERVICE_SELECTION, 0)
		return
	end
end

local onDelete = function (ref)
	ads[ref] = nil
end

local onCreateBB = function (station)
	-- DEBUG (add crime for testing) START
	-- factions = getNearbyFactions(station.path:GetStarSystem())
	-- for _,faction in pairs(factions) do
	--   Game.player:AddCrime("MURDER", 1, faction)
	--   Game.player:AddCrime("PIRACY", 2, faction)
	--   Game.player:AddCrime("WEAPONS_DISCHARGE", 3, faction)
	--   Game.player:AddCrime("TRADING_ILLEGAL_GOODS", 4, faction)
	--   Game.player:AddCrime("DUMPING", 5, faction)
	-- end
	-- DEBUG END

	local n = Engine.rand:Integer(1, #flavours)
	local method_txt = string.interp(l["METHOD_" .. Engine.rand:Integer(1, getNumberOfFlavours("METHOD"))],
	                                 {system = Game.system.name})

	-- chance to have ship waiting at station for commands
	local ship
	if Engine.rand:Integer(1,2) == 1 then
		ship = getShip(station, false)
	else
		ship = nil
	end

	local ad = {
		title            = flavours[n].title,
		message          = flavours[n].message,
		method_txt       = method_txt,
		faceseed         = Engine.rand:Integer(),
		ship_incoming    = nil,
		ship_available   = ship,
		ships_outgoing   = {},       -- {ship:{target_systems}}
		target_systems   = {},       -- current target systems without assigned ship
		station          = station,
		timers           = {}        -- all currently set timers
	}

	local ref = station:AddAdvert({
			description = ad.title,
			icon        = "wipecrime",
			onChat      = onChat,
			onDelete    = onDelete})
	ads[ref] = ad
end

local loaded_data

local onGameStart = function ()
	ads = {}
	if not loaded_data then return end

	for _,ad in pairs(loaded_data.ads) do
		local ref = ad.station:AddAdvert({
				description = ad.title,
				icon        = "wipecrime",
				onChat      = onChat,
				onDelete    = onDelete})
		ads[ref] = ad
		for i,timer in pairs(ad.timers) do
			startTimer(ad, i, timer)
		end
	end

	scheduled_services = loaded_data.scheduled_services
	loaded_data = nil
end

local onShipDocked = function (ship, station)
	if ship:IsPlayer() then return end
	for _,ad in pairs(ads) do
		if ship == ad.ship_incoming then
			ad.ship_available = ad.ship_incoming
			ad.ship_incoming = nil
			local timer_args = {timertype  = "launchship",
			                    time       = Game.time + Engine.rand:Integer(30,60),
			                    ship       = ship,
			                    station    = ad.station}
			table.insert(ad.timers, timer_args)
			startTimer(ad, #ad.timers, timer_args)

		elseif ad.ships_outgoing[ship] then
			local timer_args = {timertype  = "launchship",
			                    time       = Game.time + Engine.rand:Integer(30,60),
			                    ship       = ship,
			                    station    = ad.station}
			table.insert(ad.timers, timer_args)
			startTimer(ad, #ad.timers, timer_args)
		end
	end
end

local serialize = function ()
	return {ads = ads, scheduled_services = scheduled_services}
end

local unserialize = function (data)
	loaded_data = data
end

Event.Register("onCreateBB", onCreateBB)
Event.Register("onGameStart", onGameStart)
Event.Register("onShipDocked", onShipDocked)
Serializer:Register("WipeCrime", serialize, unserialize)
