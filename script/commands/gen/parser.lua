require("string_ext")
local lfs = require("lfs")
local CFunc = require("CFunc")
local CVar  = require("CVar")

local parser = {}

local function parse_function_csv(filename, data)
    local fcnts = {}
    local filename = lfs.get_cleaned_path(filename)
    CVar.set_data(data)  -- Set the data for CVar to use
    -- Read the CSV file
    for line in io.lines(filename) do
        local cells = line:split(";")
        -- Construct function table
        if cells[1] ~= "NOGEN" then
            local f = CFunc:new(cells)
            table.insert(fcnts, f)
        end
    end
    return fcnts
end

local function parse_typedef_csv(filename)
    local typedef = {}
    local filename = lfs.get_cleaned_path(filename)
    for line in io.lines(filename) do
        local parts = line:split(";")
        if #parts == 2 then
            local key = parts[1]:trim()
            local value = parts[2]:trim()
            typedef[key] = value
        end
    end
    return typedef
end

local function parse_struct_csv(filename)
    local struct = {}
    local filename = lfs.get_cleaned_path(filename)
    for line in io.lines(filename) do
        local parts = line:split(";")
        local key = parts[1]
        local values = {}
        for i = 2, #parts, 2 do
            if parts[i] and parts[i + 1] then
                table.insert(values, {type = parts[i]:trim(), name = parts[i+1]:trim()})
            end
        end
        struct[key] = values
    end
    return struct
end

-- Parses CSV data using the provided parser function.
-- @param data The raw CSV data.
-- @param parser_function The function to parse the CSV data.
-- @return The parsed data, or "N/A" if the input data is empty.
local function parse_csv(filename, parser_function)
    return filename == "" and "N/A" or parser_function(filename)
end


function parser.parse_interception_csv(filenames)
    local data_csv = {
        typedef_csv = parse_csv(filenames.typedef_csv, parse_typedef_csv),
        struct_csv = parse_csv(filenames.struct_csv, parse_struct_csv),
    }
    data_csv.function_csv = parse_function_csv(filenames.function_csv, data_csv)
    return data_csv
end


return parser
