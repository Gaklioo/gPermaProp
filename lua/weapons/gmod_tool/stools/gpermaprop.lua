TOOL.Category = "Construction"
TOOL.Name = "gPermaProp"
TOOL.Command = nil 
TOOL.ConfigName = ""

gPermaProp = gPermaProp or {}
gPermaProp.Database = "gPermaProp_SavedInformation"
gPermaProp.EntityDataTable = "gShelve_Table"
gPermaProp.BlockedMovement = gPermaProp.BlockedMovement or {}

if not sql.TableExists(gPermaProp.Database) then
    sql.Begin()

    local str = string.format("CREATE TABLE %s (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, x REAL, y REAL, z REAL, ax REAL, ay REAL, az REAL, model TEXT, isEnt INTEGER, map TEXT)", gPermaProp.Database)

    sql.Query(str)
    sql.Commit()

    if sql.LastError() then
        print("SQL Error: " .. sql.LastError())
    else
        print("Table gPermaProp_SavedInformation created successfully!")
    end

    print("H")
end

if not sql.TableExists(gPermaProp.EntityDataTable) then
    sql.Begin()

    local str = string.format("CREATE TABLE %s (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, x REAL, y REAL, z REAL, sName TEXT, sAmount INTEGER, UNIQUE (x, y, z, sName))", gPermaProp.EntityDataTable)

    sql.Query(str)
    sql.Commit()

    if sql.LastError() then
        print("SQL Error: " .. sql.LastError())
    else
        print("Table gShelve_Table created successfully!")
    end

    print("H")
end

gPermaProp.AllowedUserGroups = 
{
    ["superadmin"] = true,
    ["senioradmin"] = true, 
    ["needpermapropdone"] = true,
    ["owner"] = true 
}

--Place all allowed props in here
--If prop is entity, it should have a function on server side to save its data
--Perma prop only saves the location and type of thing its saving
--Not the data within the saved item itself
gPermaProp.AllowedProps = 
{
    ["gshelve"] = true,
    ["prop_physics"] = true 
}

--Entity: The entity you are saving
--Coords: Vector of where the saved item is
--Angle: Prop angle
--propModel: model of the prop
function gPermaProp:SaveProp(entity, coords, angle, propModel)
    if not gPermaProp.AllowedProps[entity:GetClass()] then return end

	local x, y, z = coords.x, coords.y, coords.z
	local ax, ay, az = angle.x, angle.y, angle.z
	local entClass = entity:GetClass()

	local str = string.format("INSERT INTO %s (name, x, y, z, ax, ay, az, model, isEnt, map) VALUES ('%s', %f, %f, %f, %f, %f, %f, '%s', %d, '%s')",
		tostring(gPermaProp.Database),
		sql.SQLStr(entClass, true),
		x, y, z,
		ax, ay, az,
		sql.SQLStr(propModel, true),
		0,
		sql.SQLStr(game.GetMap(), true)
	)

	sql.Query(str)

	print("Saved Prop")
end

--Coords: Vector of where item is saved
--Entity: Entity attempting to be saved
--IMPORTANT: Each entity should have a ENT:SaveData() and Ent:LoadData() if they are to be perma propped
--Implemented in your own way, however this are IMPORTANT, if they return nil, its not going to save.
function gPermaProp:SaveEntity(coords, angle, entity)
    if not gPermaProp.AllowedProps[entity:GetClass()] then print("Not Allows") return end
    if not entity.SaveData then print("No Save Data") return end -- Cannot Save Data
    if not entity.LoadData then print("No Load Data") return end -- No reason to store an entity that we cannot load data to. 

	local x, y, z = coords.x, coords.y, coords.z
	local ax, ay, az = angle.x, angle.y, angle.z
	local entClass = entity:GetClass()
	local entModel = entity:GetModel()

	local str = string.format("INSERT INTO %s (name, x, y, z, ax, ay, az, model, isEnt, map) VALUES ('%s', %f, %f, %f, %f, %f, %f, '%s', %d, '%s')",
		gPermaProp.Database,
		sql.SQLStr(entClass, true),
		x, y, z,
		ax, ay, az,
		sql.SQLStr(entModel, true),
		1,
		sql.SQLStr(game.GetMap(), true)
	)

	local res = sql.QueryRow(str)

	if not res then
		print(sql.LastError())
	end

	print("Saved Entity")
end

hook.Add("InitPostEntity", "gPermaProp_LoadStuff", function()
	gPermaProp:LoadEntities()
end)

hook.Add("ShutDown", "gPermaProp_SaveEntity", function()
	for index, _ in pairs(gPermaProp.BlockedMovement) do
		local entIndex = Entity(index)

		if entIndex.SaveData then
			entIndex:SaveData()
		end
	end
end)

hook.Add("PreCleanupMap", "gPermaProp_SaveWipe", function()
	for index, _ in pairs(gPermaProp.BlockedMovement) do
		local entIndex = Entity(index)

		if entIndex.SaveData then
			entIndex:SaveData()
		end
	end
end)

hook.Add("PostCleanupMap", "gPermaProp_LoadWipeMap", function()
	gPermaProp:LoadEntities()
end)

function gPermaProp:LoadEntities()
	local currentMap = game.GetMap()
    local str = string.format("SELECT * FROM %s", gPermaProp.Database)
    local res = sql.Query(str)

    if not res then 
        print("Failure to load props :( " .. (sql.LastError() or "Unknown SQL error"))
        return
    end

    for _, row in pairs(res) do
		if tostring(row.map) != currentMap then return end 
        local entName = row.name
        local entPos = Vector(tonumber(row.x), tonumber(row.y), tonumber(row.z))
        local entAng = Angle(tonumber(row.ax), tonumber(row.ay), tonumber(row.az))
        local entModel = row.model
        local isEnt = tonumber(row.isEnt)

        local ent = ents.Create(entName)

        if not IsValid(ent) then
            print("Failure to create entity " .. entName)
            continue
        end

        ent:SetModel(entModel)
        ent:SetPos(entPos)
        ent:SetAngles(entAng)
        ent:Spawn()

		ent:GetPhysicsObject():EnableMotion(false)
		ent:SetMoveType(MOVETYPE_NONE)
		ent:SetOwner(nil)

		gPermaProp.BlockedMovement[ent:EntIndex()] = true
		gPermaProp:BlockMovement()


        if isEnt == 1 then
            ent:LoadData()
        end
    end
end

if CLIENT then
    language.Add("Tool.gPermaProp.name", "gPermaProp")
	language.Add("Tool.gPermaProp.desc", "Permanently Place Entity/Prop in world")
	language.Add("Tool.gPermaProp.0", "Left Click: Perma Prop, Right Click: Remove Perma Prop")
end

function gPermaProp:BlockMovement()
	for index, _ in pairs(gPermaProp.BlockedMovement) do
		local entIndex = Entity(index)
		if IsValid(entIndex) then
			hook.Add("PhysgunPickup", "gPermaProp_BlockMovement" .. index, function(ply, ent)
				if entIndex == ent then
					return false
				end
			end)
		end
	end
end

function TOOL:LeftClick(trace)
    if (CLIENT) then 
		return true 
	end

	if not gPermaProp.AllowedUserGroups[self:GetOwner():GetUserGroup()] then print("Not Admin") return end -- Uncomment when not testing
	if not IsValid(trace.Entity) then return end
	if not gPermaProp.AllowedProps[trace.Entity:GetClass()] then return end
	if gPermaProp.BlockedMovement[trace.Entity:EntIndex()] then return false end
	local ent = trace.Entity

	local entClass = ent:GetClass()
	local entPos = ent:GetPos()
	local entAng = ent:GetAngles()
	local entModel = ent:GetModel()
	ent:Remove()

	ent = ents.Create(entClass)
	ent:SetModel(entModel)
	ent:SetPos(entPos)
	ent:SetAngles(entAng)
	ent:Spawn()

	local entIndex = ent:EntIndex()

	ent:GetPhysicsObject():EnableMotion(false)
	ent:SetMoveType(MOVETYPE_NONE)
	ent:SetOwner(nil)

	gPermaProp.BlockedMovement[entIndex] = true

	gPermaProp:BlockMovement()

	if entClass == "prop_physics" then
		gPermaProp:SaveProp(ent, entPos, entAng, entModel)
	else -- No need to check here, we check above for if the prop is a savable entity
		gPermaProp:SaveEntity(entPos, entAng, ent)
	end

    return true
end

function TOOL:RightClick(trace)
	if (CLIENT) then 
		return true 
	end

	local ent = trace.Entity
	if not IsValid(ent) then return end
	if not gPermaProp.AllowedProps[ent:GetClass()] then return end
	if not gPermaProp.BlockedMovement[ent:EntIndex()] then return end
	if not gPermaProp.AllowedUserGroups[self:GetOwner():GetUserGroup()] then print("Not Admin") return end

	local index = ent:EntIndex()
	local pos = ent:GetPos()


	local q = string.format("DELETE FROM %s WHERE x = %f AND y = %f AND z = %f and model = '%s'",
		gPermaProp.Database,
		pos.x, pos.y, pos.z,
		ent:GetModel()
	)

	local res = sql.Query(q)

	if not res then
		print("Error deleting prop: " .. sql.LastError())
	end

	gPermaProp.BlockedMovement[ent:EntIndex()] = false 
	hook.Remove("PhysgunPickup", "gBlockMovement" .. index)

	ent:GetPhysicsObject():EnableMotion(true)
	ent:SetMoveType(MOVETYPE_VPHYSICS)

	return true
end
