-- Farmboard v1.0.1 - per-character storage bridge
-- Keeps the minimap button position account-wide while storing boards per character.

local legacyDB = type(FarmboardDB) == "table" and FarmboardDB or {}

if type(FarmboardAccountDB) ~= "table" then
    FarmboardAccountDB = {}
end

if type(FarmboardCharDB) ~= "table" then
    FarmboardCharDB = {}
end

local function DeepCopy(value, seen)
    if type(value) ~= "table" then
        return value
    end

    seen = seen or {}
    if seen[value] then
        return seen[value]
    end

    local copy = {}
    seen[value] = copy
    for key, entry in pairs(value) do
        copy[DeepCopy(key, seen)] = DeepCopy(entry, seen)
    end
    return copy
end

-- Preserve the previous account-wide database once as a migration backup.
if FarmboardAccountDB.legacyBackup == nil and next(legacyDB) ~= nil then
    FarmboardAccountDB.legacyBackup = DeepCopy(legacyDB)
end

-- The minimap button remains account-wide, so it stays in the same place on every character.
if type(FarmboardAccountDB.minimap) ~= "table" and type(legacyDB.minimap) == "table" then
    FarmboardAccountDB.minimap = DeepCopy(legacyDB.minimap)
end

-- Import the old shared boards once into the first character loaded after this update.
-- Every other character starts with its own fresh Farmboard afterwards.
if FarmboardAccountDB.characterBoardsMigration ~= 1 then
    if type(FarmboardCharDB.boards) ~= "table" and type(legacyDB.boards) == "table" then
        FarmboardCharDB.boards = DeepCopy(legacyDB.boards)
        FarmboardCharDB.nextBoardID = legacyDB.nextBoardID
        FarmboardCharDB.goalNotificationMigration = legacyDB.goalNotificationMigration
        FarmboardCharDB.importedLegacyBoards = true
    end

    FarmboardAccountDB.characterBoardsMigration = 1
end

-- Farmboard.lua historically reads/writes FarmboardDB everywhere.  This proxy keeps that
-- API intact while routing board data into the character SavedVariables table.
local accountKeys = {
    minimap = true,
}

local proxy = {}
setmetatable(proxy, {
    __index = function(_, key)
        if accountKeys[key] then
            return FarmboardAccountDB[key]
        end
        return FarmboardCharDB[key]
    end,

    __newindex = function(_, key, value)
        if accountKeys[key] then
            FarmboardAccountDB[key] = value
        else
            FarmboardCharDB[key] = value
        end
    end,
})

FarmboardDB = proxy
