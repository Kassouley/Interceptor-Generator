local CVar = require("CVar")

local CFunc = {}
CFunc.__index = CFunc

function CFunc:new(attribute)
    local self = setmetatable({}, CFunc)

    self.gen    = attribute[1]:trim()
    self.capture_point = attribute[2]:trim()
    self.ftype  = CVar:new(attribute[3], "retval")
    self.fname  = attribute[4]:trim()
    
    self.fparam = {}
    if attribute[5] ~= "void" and attribute[5] ~= nil then
        -- Extract params
        for i = 5, #attribute, 2 do
            local fparam = CVar:new(attribute[i], attribute[i+1])
            table.insert(self.fparam, fparam)
        end
    end
    return self
end

function CFunc:has_param()
    return #self.fparam > 0
end

function CFunc:return_is_ptr()
    local param = self.ftype
    return param:is_ptr() and not param:is_generic_ptr() and not param:is_opaque(true)
end


function CFunc:params_has_ptr()
    for _, param in ipairs(self.fparam) do
        if param:is_ptr() and not param:is_generic_ptr() and not param:is_opaque(true) then
            return true
        end
    end
    return false
end


function CFunc:uses_pointer()
    return self:params_has_ptr() or self:return_is_ptr()
end


function CFunc:is_void()
    return self.ftype:is_void(true)
end


function CFunc:get_signature_elements()
    local t = {}
    for i, v in ipairs(self.fparam) do
        t[i] = v
    end
    if not self:is_void() or self.ftype:is_generic_ptr() then
        table.insert(t, self.ftype)
    end
    return t
end


function CFunc:get_fname(prefix, suffix)
    prefix = prefix or ""
    suffix = suffix or ""
    return prefix .. self.fname .. suffix
end


function CFunc:get_function_decl(prefix, suffix, more_params)
    return self.ftype.vtype .. " " .. self:get_fname(prefix, suffix) .. "(" .. self:get_fparams_string(more_params) .. ")"
end


function CFunc:capture_point_is_post_call()
    return self:has_param() and self.capture_point == "ARG_AFTER"
end


function CFunc:capture_point_is_pre_call()
    return self:has_param() and self.capture_point == "ARG_BEFORE"
end


function CFunc:get_fargs_string(more_args)
    more_args = more_args or {}
    local strings = {}
    for _, param in ipairs(self.fparam) do
        table.insert(strings, param.name)
    end
    for _, arg in ipairs(more_args) do
        table.insert(strings, arg)
    end
    return table.concat(strings, ", ")
end


function CFunc:get_fparams_string(more_params)
    more_params = more_params or {}
    local strings = {}
    for _, param in ipairs(self.fparam) do
        table.insert(strings, param.pdecl)
    end
    for _, param in ipairs(more_params) do
        table.insert(strings, param)
    end
    return table.concat(strings, ", ")
end

return CFunc