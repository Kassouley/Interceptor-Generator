-- Managing C types and their Lua representations.
-- This module provides utilities for handling C types, cleaning type keywords,
-- counting pointers, and resolving real C types from typedefs and structs.

-- CVar class to represent a C type and perform operations on it
local CVar = {}
CVar.__index = CVar
CVar.__data = {}


CVar.__data.c_types_fmt = {
    ["N/A"]                     = true,
    ["void"]                    = true,
    ["struct"]                  = true,
    ["union"]                   = true,
    ["opaque"]                  = "%p",
    ["function"]                = "%p",
    ["string"]                  = "%s",
    ["enum"]                    = "%d",
    ["char"]                    = "%c",
    ["signed char"]             = "%hhd",
    ["unsigned char"]           = "%hhu",
    ["short"]                   = "%hd",
    ["signed short"]            = "%hd",
    ["unsigned short"]          = "%hu",
    ["short int"]               = "%hd",
    ["signed short int"]        = "%hd",
    ["unsigned short int"]      = "%hu",
    ["int"]                     = "%d",
    ["signed int"]              = "%d",
    ["unsigned int"]            = "%u",
    ["long"]                    = "%ld",
    ["signed long"]             = "%ld",
    ["unsigned long"]           = "%lu",
    ["long int"]                = "%ld",
    ["signed long int"]         = "%ld",
    ["unsigned long int"]       = "%lu",
    ["long long"]               = "%lld",
    ["signed long long"]        = "%lld",
    ["unsigned long long"]      = "%llu",
    ["long long int"]           = "%lld",
    ["signed long long int"]    = "%lld",
    ["unsigned long long int"]  = "%llu",
    ["float"]                   = "%f",
    ["double"]                  = "%lf",
    ["long double"]             = "%Lf",
}

CVar.__data.type_qualifers  = { ["const"] = true, ["volatile"] = true, ["restrict"] = true }

function CVar.set_data(data)
    CVar.__data.typedef_map = data.typedef_csv or {}
    CVar.__data.struct_map = data.struct_csv or {}
end

local function __resolve_typedef(type_str, depth)
    depth = depth or 0
    if depth > 10 then
        return type_str -- prevent infinite recursion
    end

    type_str = type_str:trim()

    -- Prevent full type resolution if already qualified
    if CVar.__data.typedef_map[type_str] and not type_str:match("^(struct|union|enum)%s+") then
        return __resolve_typedef(CVar.__data.typedef_map[type_str], depth + 1)
    end

    -- Handle pointer to typedef function: e.g., "Func_t*" where Func_t = "void (int)"
    local base, stars = type_str:match("^([%a_][%w_]*)%s*(%**)$")
    if base and CVar.__data.typedef_map[base] then
        local resolved_base = __resolve_typedef(CVar.__data.typedef_map[base], depth + 1)
        if resolved_base:match("^%w+%s*%b()%s*$") then
            -- It's a function type like "void (int)", and we are doing "Func_t*"
            if stars and #stars > 0 then
                resolved_base = resolved_base:gsub("%b()", function(params)
                    return "(*" .. string.rep("*", #stars - 1) .. ")" .. params
                end)
            end
            return resolved_base
        else
            -- Normal typedef (not function type), resolve normally
            return resolved_base .. stars
        end
    end

    -- Replace individual typedef words if not prefixed by struct/union/enum
    local resolved = type_str:gsub("([%a_][%w_]*)", function(word)
        -- Check for full tag+identifier pattern like "struct MyType", "union Foo"
        local tag_keywords = { "struct", "union", "enum" }
        for _, tag in ipairs(tag_keywords) do
            if type_str:match(tag .. "%s+" .. word) then
                return word -- already tagged, skip replacing
            end
        end
        -- Replace if it's a known typedef
        if CVar.__data.typedef_map[word] then
            return __resolve_typedef(CVar.__data.typedef_map[word], depth + 1)
        end

        return word
    end)
    return resolved
end


function CVar:is_function()
    return self.ctype:find("%(%*[^)]*%)%(") ~= nil
end


function CVar:is_ptr(ctype)
    ctype = ctype or self.ctype
    local cnt, _ = self:get_ptr_count(ctype)
    return cnt > 0
end


function CVar:is_static_array(exclude_ptr)
    -- Exclude function pointer types
    if self:is_function() then return false end

    if exclude_ptr and self:is_ptr() then
        return false
    end

    return self.ctype:find("%[%d+%]") ~= nil
end


function CVar:is_dynamic_array()
    -- Exclude function pointer types
    if self:is_function() then return false end

    return self.ctype:find("%[%%s*%]") ~= nil
end


function CVar:is_array()
    return self:is_dynamic_array() or self:is_static_array()
end


function CVar:is_struct(exclude_ptr)
    -- Exclude function pointer types to not match struct in function parameters
    if self:is_function() then return false end

    if exclude_ptr and self:is_ptr() then
        return false
    end

    return self.ctype:find("struct%s+") ~= nil
end


function CVar:is_enum(exclude_ptr)
    -- Exclude function pointer types to not match enum in function parameters
    if self:is_function() then return false end

    if exclude_ptr and self:is_ptr() then
        return false
    end

    return self.ctype:find("enum%s+") ~= nil
end


function CVar:is_union(exclude_ptr)
    -- Exclude function pointer types to not match union in function parameters
    if self:is_function() then return false end

    if exclude_ptr and self:is_ptr() then
        return false
    end

    return self.ctype:find("union%s+") ~= nil
end


function CVar:is_opaque(exclude_ptr)
    local cnt, _ = self:get_ptr_count()
    if exclude_ptr and cnt > 1 then
        return false
    end

    if self:is_struct() or self:is_union() then
        return #self.struct_fields == 0 and cnt >= 1
    end
    return false
end


function CVar:is_string(exclude_ptr)
    -- Exclude function pointer types
    if self:is_function() then return false end

    local cnt, pointed_type = self:get_ptr_count()

    if exclude_ptr and cnt > 1 then
        return false
    end

    return pointed_type:match("char") ~= nil and cnt >= 1
end


function CVar:is_generic_ptr()
    -- Exclude function pointer types
    if self:is_function() then return false end

    local cnt, pointed_type = self:get_ptr_count()
    return pointed_type:match("void") ~= nil and cnt == 1
end


function CVar:is_void(exclude_ptr)
    -- Exclude function pointer types
    if self:is_function() then return false end

    if exclude_ptr and self:is_ptr() then
        return false
    end

    return self.ctype:find("void") ~= nil
end

function CVar:is_unknown()
    local base_type = self:get_base_type()
    return CVar.__data.c_types_fmt[base_type] == nil
end


function CVar:get_base_type()
    local ctype = self.ctype

    if self:is_string() then
        return "string"
    elseif self:is_function() then
        return "function"
    elseif self:is_enum() then
        return "enum"
    elseif self:is_opaque() then
        return "opaque"
    elseif self:is_struct() then
        return "struct"
    elseif self:is_union() then
        return "union"
    end

    -- Remove qualifiers
    ctype = self:remove_type_qualifers()

    -- Remove pointers and arrays
    ctype = ctype:gsub("%*+", "")             -- remove pointer stars
    ctype = ctype:gsub("%[[^%]]*%]", "")     -- remove array brackets

    return ctype:trim()
end


function CVar:get_cfmt()
    local base_type = self:get_base_type()

    if base_type == "union" or base_type == "struct" then
        error("Do not use CVar:get_cfmt() method for structure or union variable.\n"..
              "Please check before if variable is structure or union using var:is_struct() or var:is_union() methods.")
    end

    return CVar.__data.c_types_fmt[base_type] or "%p"  -- default fallback
end

function CVar:get_decl(type_str, var_name)
    type_str = type_str or self.vtype
    var_name = var_name or self.name

    local start_pos, end_pos = type_str:find("%(%*[^)]*%)")
    if start_pos and end_pos then
      return type_str:sub(1, end_pos - 1) .. " " .. var_name .. type_str:sub(end_pos)
    end
    
    local pos_array = type_str:find("%[.-%]")
    if pos_array then
        local base_type = type_str:sub(1, pos_array - 1)
        local array_size = type_str:sub(pos_array)
        return base_type .. " " .. var_name .. array_size
    end
    return type_str .. " " .. var_name
end


local function extract_tagged_name(ctype)
    if ctype:find("unnamed") then
        return ctype
    end
    local name = ctype:match("%s*struct%s+([%w_]+)")
            or ctype:match("%s*union%s+([%w_]+)")
            or ctype:match("%s*enum%s+([%w_]+)")
    return name
end


function CVar:__resolve_struct()
    local ctype = self.ctype
    local struct_map = CVar.__data.struct_map[extract_tagged_name(ctype)]
    
    if struct_map then
        for i = 1, #struct_map do
            local pair = struct_map[i]
            local field = CVar:new(pair.type, pair.name)
            table.insert(self.struct_fields, field)
        end
    end
end


function CVar:new(vtype, name)
    local att = setmetatable({}, CVar)
    att.vtype = vtype:trim()
    att.name  = name:trim()

    att.ctype = __resolve_typedef(vtype)
    att.pdecl = att:get_decl()

    att.struct_fields = {}
    if att:is_struct() or att:is_union() then
        att:__resolve_struct()
    end

    return att
end



function CVar:__get_type_qualifers(ctype)
    local qualifiers = {}
    local words = {}

    -- Split the input into words
    for word in ctype:gmatch("%S+") do
        if CVar.__data.type_qualifers[word] then
            table.insert(qualifiers, word)
        else
            table.insert(words, word)
        end
    end

    ctype = table.concat(words, " ")
    return qualifiers, ctype
end


function CVar:get_type_qualifers(ctype)
    ctype = ctype or self.ctype

    -- If the input is function type
    local ret_type, ptr_part, args = ctype:match("(.-)%(%s*%*%s*([^%(%)]*)%s*%)%s*(%b())")
    if ret_type and ptr_part and args then
        local qualifiers, ctype = self:__get_type_qualifers(ptr_part)
        ctype = string.format("%s(*%s)%s", ret_type, ctype, args)
        return qualifiers, ctype
    else
        return self:__get_type_qualifers(ctype)
    end
end

function CVar:get_type_for_struct(type_str)
    type_str = type_str or self.vtype

    local ctype_ptr_count, _ = self:get_ptr_count()
    local vtype_ptr_count, _ = self:get_ptr_count(type_str)

    if not self:is_opaque() and ctype_ptr_count > vtype_ptr_count then
        type_str = self.ctype
    end

    type_str = CVar:remove_type_qualifers(type_str)

    type_str = type_str:gsub("%[%]", "(*)")


    return type_str
end


function CVar:remove_type_qualifers(decl)
    decl = decl or self.ctype
    _, decl = self:get_type_qualifers(decl)
    return decl
end


function CVar:get_array_dim(ctype)
    ctype = ctype or self.ctype

    local dims = {}
    if self:is_array(ctype) then

        -- Match [N] or [] — insert 0 for empty brackets
        for size in ctype:gmatch("%[(.-)%]") do
            local dim = tonumber(size)
            table.insert(dims, dim or 0)
        end

        -- Remove array parts to get the base ctype
        ctype = ctype:gsub("%[.-%]", ""):gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")

    end
    return dims, ctype
end


function CVar:get_pointed_type(ctype)
    local _, pointed_type = self:get_ptr_count(ctype)
    return pointed_type
end

-- Return the type full derefenced : int** -> int, int(*)[3] -> int[3],  int[][3] -> int[3]
function CVar:get_ptr_count(ctype)
    ctype = ctype or self.ctype

    if self:is_function() then
        return 0, ctype
    end
    local ref_cnt = 0
    ctype = ctype:gsub("%s*%(%s*%*%s*%)%s*", function()
        ref_cnt = ref_cnt + 1
        return ""
    end)
    ctype = ctype:gsub("%s*%*%s*", function()
        ref_cnt = ref_cnt + 1
        return ""
    end)
    ctype = ctype:gsub("%s*%[%s*%]%s*", function()
        ref_cnt = ref_cnt + 1
        return ""
    end)
    return ref_cnt, ctype
end

return CVar
