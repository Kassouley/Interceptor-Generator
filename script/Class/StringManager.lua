---@diagnostic disable: deprecated
-- Update the package path to include your Lua INI Parser
require("string_ext")
local LIP = require("LIP")
local lfs = require("lfs")
local parser = require("parser")

local StringManager = {}
StringManager.__index = StringManager


-- Constructor for the StringManager object
function StringManager.new(config_data)
    local self = setmetatable({}, StringManager)

    -- Load the INI file into the config table
    self.config = LIP.load(lfs.get_cleaned_path(config_data.details.string))
    self.config.STRING.CURRENT_DOMAIN = "N/A"
    self.config.STRING.HANDLE = "RTLD_NEXT"
    self.config.STRING.HANDLE_PATH = "N/A"
    self.config.STRING.INCLUDE_STR = "N/A"

    self.domain_list = config_data.domain_list
    self.current_domain = nil

    for _, domain in pairs(self.domain_list) do
        local data_csv = parser.parse_interception_csv({
            function_csv = domain.function_csv,
            typedef_csv = domain.typedef_csv,
            struct_csv = domain.struct_csv
        })
        domain.function_data = data_csv.function_csv
    end

    for getter, _ in pairs(self.config) do
        if not self[getter] then
            self[getter] = function(self, id, dont_stop_on_error)
                return self:replace_placeholders(id, getter, dont_stop_on_error)
            end
        end
    end

    return self
end


-- Creates a string for include directives from a table of include paths.
-- @param includes_table A table of include paths.
-- @return A string of include directives formatted for C.
local function get_include_str(includes_table)
    return "\n#include \"" .. table.concat(includes_table, "\"\n#include \"") .. "\"\n"
end

function StringManager:set_domain(domain, domain_name)
    self.current_domain = domain
    self.config.STRING.CURRENT_DOMAIN = domain_name
    self.config.STRING.DOMAIN_DESC = domain.desc
    self.config.STRING.HANDLE = domain.lib == "" and "RTLD_NEXT" or "handle"
    self.config.STRING.HANDLE_PATH = domain.lib == "" and "NULL" or "\""..domain.lib.."\""
    self.config.STRING.INCLUDE_STR = get_include_str(domain.includes)
end



local function split_mod(str)
    local name, mod = str:match("([^|]+)|?(.*)")
    if mod == "" then mod = nil end
    return name, mod
end

-- Function to replace placeholders in a given string
function StringManager:replace_placeholders(str, section_name, dont_stop_on_error)
    local key, mod = split_mod(str)
    local section = nil
    if section_name then
        section = self.config[section_name]
        if not section then 
            error ("No section named "..section_name.." in string config file for "..CurrentFile..".")
        end
    else
        for name, s in pairs(self.config) do
            if s[key] then
                section = s
                section_name = name
                break
            end
        end
        if not section then 
            error ("No section found for "..key.." string for "..CurrentFile..".")
        end
    end

    local result = section[key]

    if result then
        result = result:trim():gsub("{(.-)}", function(inner_key)
            return self:replace_placeholders(inner_key)
        end)
    elseif dont_stop_on_error then
        return nil
    else
        error ("No string found for id "..key.." in "..section_name.." section for "..CurrentFile..".")
    end

    -- Handle any transformation, like 'upper' or 'lower'
    if mod == "upper" then
        return string.upper(result):gsub("\\n", "\n")
    elseif mod == "lower" then
        return string.lower(result):gsub("\\n", "\n")
    else
        return result:gsub("\\n", "\n")
    end
    
end

function StringManager:STRING(id)
    return self:replace_placeholders(id)
end


function StringManager:FOR_EACH_DOMAIN(code)
    local func = assert(loadstring("return "..code)())
    local content_table = {}
    for domain_name, domain in pairs(self.domain_list) do
        if domain.function_csv == "" then
            print("Warning: Skipping " .. domain_name .. ", config file not complete")
        else
            self:set_domain(domain, domain_name)

            local content = func(domain_name, S:STRING("DOMAIN_ID"), domain.is_dlsym_lib)
            table.insert(content_table, content)
        end
    end
    return table.concat(content_table, "\n")
end

function StringManager:FOR_EACH_DOMAIN_FUNCTION(code)
    local content_table = {}
    local func = assert(loadstring("return "..code)())

    for _, f in ipairs(self.current_domain.function_data) do
        local content = func(f)
        table.insert(content_table, content)
    end

    return table.concat(content_table, "\n")
end

function StringManager:DOMAIN(id)
    return self:FILENAME(id)
end

function StringManager:HDR(id)
    return self:FILENAME(id)..'.h'
end

function StringManager:HDR_PATH(id)
    local dir = self:PATH(id, true)
    local file = self:HDR(id)
    if dir then return dir .. "/" .. file end
    return file
end

function StringManager:SRC(id)
    return self:FILENAME(id)..'.c'
end

function StringManager:HEADER(id)
    return self:replace_placeholders(id..'|upper', "FILENAME")..'_H'
end

function StringManager:STRUCT(id)
    return self:TYPE(id):gsub("_t", "_s")
end


function StringManager:UNION(id)
    return self:TYPE(id):gsub("_t", "_u")
end

function StringManager:ENUM(id)
    return self:TYPE(id):gsub("_t", "_e")
end

function StringManager:CALL(id)
    return self:replace_placeholders(id, "FUNC")
end


function StringManager:FUNC_DECL(id)
    local type   = self:replace_placeholders(id..'_TYPE', "FUNC")
    local funame = self:replace_placeholders(id         , "FUNC")
    local args   = self:replace_placeholders(id..'_ARGS', "FUNC")
    return type.." "..funame.."("..args..")"
end


function StringManager:IMPL(id)
    local funame = self:replace_placeholders(id , "FUNC")
    return "__" .. funame .. "_impl"
end


function StringManager:IMPL_DECL(id)
    local type   = self:replace_placeholders(id..'_TYPE', "FUNC")
    local funame = self:replace_placeholders(id         , "FUNC")
    local args   = self:replace_placeholders(id..'_ARGS', "FUNC")
    funame = "__" .. funame .. "_impl"
    return type.." "..funame.."("..args..")"
end

function StringManager:__get_status_message(key)
    local msg_key = key .. "_MSG"
    local message = self:STATUS_MSG(msg_key)
    if not message then error ("Status " .. key .. "doesn't have error message in STATUS_MSG section.") end
    return message
end

function StringManager:STATUS_ENUM_LIST()
    local status_enum = {}
    for status_key, _ in pairs(S.config.STATUS) do
        local status  = self:STATUS(status_key)
        local message = self:__get_status_message(status_key)

        local status_enum_line = string.format("%-45s /**< %s */", status..",", message)
        if status_key == "SUCCESS" then
            table.insert(status_enum, 1, status_enum_line)
        else
            table.insert(status_enum, status_enum_line)
        end
    end
    return table.concat(status_enum, "\n\t")
end

function StringManager:STATUS_MSG_LIST()
    local status_case_msg = {}
    for status_key, _ in pairs(S.config.STATUS) do
        local status  = self:STATUS(status_key)
        local message = self:__get_status_message(status_key)
        local status_case_line = string.format("\t\tcase %-45s: return \"%s\";", status, message)
        if status_key == "SUCCESS" then
            table.insert(status_case_msg, 1, status_case_line)
        else
            table.insert(status_case_msg, status_case_line)
        end
    end
    return table.concat(status_case_msg, "\n")
end

return StringManager
