local ENTER_RAW_MODE = "stty -icanon -echo" -- These names are technically wrong, but whatever, check `man stty`
local ENTER_COOKED_MODE = "stty icanon echo"

local function interpret(code)
    ---@type Instruction[]
    local bytecode = {}

    ---Match an line to an expression, then bind it
    ---@param line string
    ---@param expr string
    ---@param type Types
    ---@param ... "varname"|"operation"|"value"
    local function matcher(line, expr, type, ...)
        local output = { line:match(expr) }
        if #output > 0 then
            local keys = { ... }
            local assembled = {
                type = type,
            }
            for i = 1, #keys do
                assembled[keys[i]] = output[i]
            end
            table.insert(bytecode, assembled)
            return true
        end
        return false
    end

    -- Lexer
    for line in code:gmatch("(.-)\n") do
        -- Trim whitespace at the start of the line
        line = line:match("^[^%w#]*(.+)") or ""

        -- Ignore comments
        if line:match("^#") then goto continue end

        -- I love regex
        -- Yes, this isn't exactly efficient nor flexible, but it's easy and it works
        if matcher(line, "^splat! ([^ ]+)$", "read_line", "varname") then goto continue end
        if matcher(line, "^splat%? ([^ ]+)$", "read_char", "varname") then goto continue end
        if matcher(line, "^veemo ([^ ]+)$", "new_array", "varname") then goto continue end
        if matcher(line, "^veemo ([^ ]+) from: (.+)$", "array_string", "varname", "value") then goto continue end
        if matcher(line, "^veemo# ([^ ]+) ([^ ]+)$", "array_length", "varname", "value") then goto continue end
        if matcher(line, "^veemo ([^ ]+) %-> ([^ ]+) %[([^ ]+)%]$", "array_set", "varname", "operation", "value") then goto continue end
        if matcher(line, "^veemo ([^ ]+) <%- ([^ ]+) %[([^ ]+)%]$", "array_get", "varname", "operation", "value") then goto continue end
        if matcher(line, "^grizzco ([^ ]+)$", "array_execute", "varname") then goto continue end
        if matcher(line, "^grizzco! ([^ ]+) ([^ ]+)$", "array_execute_store", "varname") then goto continue end
        if matcher(line, "^help!woomy ([^ ]+) ([^ ]+)$", "compile_time_set", "varname", "value") then goto continue end
        if matcher(line, "^woomy ([^ ]+) ([^ ]+)$", "set", "varname", "value") then goto continue end
        if matcher(line, "^woomy ([^ ]+) ([^ ]+) ([^ ]+)$", "math", "varname", "operation", "value") then goto continue end
        if matcher(line, "^thisway@ ([^ ]+)$", "goto", "varname") then goto continue end
        if matcher(line, "^thisway! ([^ ]+) ([^ ]+) ([^ ]+)$", "if", "varname", "operation", "value") then goto continue end
        if matcher(line, "^oomy ([^ ]+) ([^ ]+) ([^ ]+)$", "while", "varname", "operation", "value") then goto continue end
        if matcher(line, "^ouch! ([^ ]+)$", "func_def", "varname") then goto continue end
        if matcher(line, "^ouch@ ([^ ]+)$", "func_call", "varname") then goto continue end
        if matcher(line, "^ouch%?$", "func_end") then goto continue end
        if matcher(line, "^booyah! ([^ ]+)$", "print", "varname") then goto continue end
        if matcher(line, "^booyah!! ([^ ]+)$", "print_array", "varname") then goto continue end
        if matcher(line, "^booyah%? ([^ ]+)$", "printc", "varname") then goto continue end
        if matcher(line, "^help!$", "else") then goto continue end
        if matcher(line, "^ngyes$", "end") then goto continue end

        if #line > 0 then
            print("WARNING: Unknown instruction found: " .. line)
        end
        -- I fucking hate lua 5.4
        ::continue::
    end

    ---@alias TypesArray "new_array"|"array_set"|"array_get"|"array_string"|"array_length"|"print_array"
    ---@alias TypesFuncs "func_def"|"func_call"|"func_end"
    ---@alias TypesIf "if"|"end"|"else"
    ---@alias TypesBasics "set"|"math"|"print"|"printc"
    ---@alias TypesAdvanced "while"|"goto"|"compile_time_set"
    ---@alias TypesInput "read_line"|"read_char"
    ---@alias TypesExecute "array_execute"|"array_execute_store"
    ---@alias Types TypesIf|TypesBasics|TypesFuncs|TypesAdvanced|TypesArray|TypesInput|TypesExecute

    ---@class Instruction
    ---@field type Types
    ---@field varname string?
    ---@field operation string?
    ---@field value string?
    ---@field jump_addr number?
    ---@field else_addr number?

    ---@class VirtMachine
    ---@field current_line number
    ---@field memory table
    ---@field bytecode Instruction[]
    local vm = {
        current_line = 1,
        memory = {},
        stack_memory = {},
        function_pointers = {},
        pointer_stack = {},
        bytecode = bytecode,

        ---@param self VirtMachine
        ---@param arr_name string
        new_array = function(self, arr_name)
            self.stack_memory[arr_name] = {}
        end,

        ---@param self VirtMachine
        ---@param arr_name string
        ---@param index number
        ---@param set number
        set_array_value = function(self, arr_name, index, set)
            assert(self.stack_memory[arr_name], "Array has not been created yet!")[index] = set
        end,

        ---@param self VirtMachine
        ---@param arr_name string
        ---@param index number
        ---@return number
        get_array_value = function(self, arr_name, index)
            return assert(assert(self.stack_memory[arr_name], "Array has not been created yet!")[index],
                "Array index has never been set! " .. arr_name)
        end,

        ---@param self VirtMachine
        is_valid = function(self)
            return self:current() ~= nil
        end,

        ---@param self VirtMachine
        inc = function(self)
            self.current_line = self.current_line + 1
        end,

        ---@param self VirtMachine
        dec = function(self)
            self.current_line = self.current_line - 1
        end,

        ---@param self VirtMachine
        ---@return Instruction?
        current = function(self)
            return self.bytecode[self.current_line]
        end,

        ---@param self VirtMachine
        ---@param value string|number
        get_val = function(self, value)
            if value == "@CURRENT_LINE" then return self.current_line end
            if type(value) == "number" then return value end
            if tonumber(value) then return tonumber(value) end
            if #value == 2 and value:sub(1, 1) == "'" then
                local v = assert(value:sub(2, 2):byte(), "Invalid literal, missing character")
                return v
            end
            local v = assert(self.memory[value], "Illegal variable! > " .. value)
            return v
        end,

        ---@param self VirtMachine
        operation = function(self, var_a, operation, var_b)
            local a, b, c = self:get_val(var_a), self:get_val(var_b), nil
            if operation == "+" then
                c = a + b
            elseif operation == "-" then
                c = a - b
            elseif operation == "*" then
                c = a * b
            elseif operation == "/" then
                c = a / b
            elseif operation == ">=" then
                c = a >= b and 1 or 0
            elseif operation == "<=" then
                c = a <= b and 1 or 0
            elseif operation == "&&" then
                c = (a == 1 and b == 1) and 1 or 0
            elseif operation == "||" then
                c = (a == 1 or b == 1) and 1 or 0
            elseif operation == "=" or operation == "==" then
                c = a == b and 1 or 0
            elseif operation == "!" then
                c = a ~= b and 1 or 0
            elseif operation == ">" then
                c = a > b and 1 or 0
            elseif operation == "<" then
                c = a < b and 1 or 0
            end
            return assert(c, "Invalid operation!")
        end,

        ---@param self VirtMachine
        ---@param func_name string
        jump_to_func = function(self, func_name)
            table.insert(self.pointer_stack, self.current_line)
            self.current_line = self.function_pointers[func_name]
        end,

        ---@param self VirtMachine
        return_from_func = function(self)
            assert(self:current().type == "func_end" or self:current().type == "else", "Interpreter error")
            self.current_line = assert(table.remove(self.pointer_stack), "Return from without being in a function")
        end,
    }

    -- Get all function definitions, and store them
    local latest_func_encountered = nil
    for index = 1, #vm.bytecode do
        vm.current_line = index -- needed for vm functions to properly work
        local current = vm.bytecode[index]

        if current.type == "func_def" then
            vm.function_pointers[current.varname] = index
            current.jump_addr = latest_func_encountered
        elseif current.type == "compile_time_set" then
            vm.memory[current.varname] = vm:get_val(current.value)
        end
    end

    -- Iterate the bytecode, save the program counter for the while/if statements
    -- Yes, we can merge this in one loop, but this is a lil more readable
    for base_index = 1, #vm.bytecode do
        vm.current_line = base_index -- needed for vm functions to properly work
        local current = vm.bytecode[base_index]

        if current.type == "else" or current.type == "end" then
            local scope_count = 0
            -- Search backwards for the if/while this 'end' closes
            for index = base_index, 1, -1 do
                local search_item = vm.bytecode[index]
                if search_item.type == "end" then
                    scope_count = scope_count + 1
                end
                if search_item.type == "if" or search_item.type == "while" then
                    scope_count = scope_count - 1
                    if scope_count == 0 then
                        if search_item.type == "if" then
                            local key = current.type == "end" and "jump_addr" or "else_addr"
                            search_item[key] = base_index
                        else
                            current.jump_addr = index - 1 -- Since we increment post loop, we have to subtrack one
                            search_item.jump_addr = base_index
                        end
                        break
                    end
                end
            end
        end
    end
    -- Reset the vm current line
    vm.current_line = 1

    while vm:is_valid() do
        local current = vm:current()
        if current == nil then return end

        if vm.memory["__DEBUG"] == 1 then
            print(("%4d: %s"):format(vm.current_line, current.type))
        end

        if current.type == "set" then
            vm.memory[current.varname] = vm:get_val(current.value)
        elseif current.type == "print" then
            io.stdout:write(vm:get_val(current.varname))
        elseif current.type == "printc" then
            io.stdout:write(string.char(vm:get_val(current.varname)))
        elseif current.type == "math" then
            vm.memory[current.varname] = vm:operation(current.varname, current.operation, current.value)
        -- Program flow
        elseif current.type == "if" then
            local result = vm:operation(current.varname, current.operation, current.value)
            if result == 0 then
                vm.current_line = assert(current.else_addr or current.jump_addr, "Invalid address")
            end
        elseif current.type == "while" then
            local result = vm:operation(current.varname, current.operation, current.value)
            if result == 0 then
                vm.current_line = current.jump_addr
            end
        elseif current.type == "end" then
            if current.jump_addr then
                vm.current_line = current.jump_addr
            end
        elseif current.type == "goto" then
            vm.current_line = vm:get_val(current.varname)
            -- Function handling
        elseif current.type == "func_call" then
            vm:jump_to_func(current.varname)
        elseif current.type == "func_end" then
            vm:return_from_func()
        elseif current.type == "func_def" then
            -- Skip until the end of the function
            while vm:is_valid() do
                vm:inc()
                if vm:current().type == "func_end" then
                    break
                end
            end
            -- Array handling
        elseif current.type == "new_array" then
            vm:new_array(current.varname)
        elseif current.type == "array_set" then
            vm:set_array_value(current.operation, vm:get_val(current.value), vm:get_val(current.varname))
        elseif current.type == "array_get" then
            vm.memory[current.varname] = vm:get_array_value(current.operation, vm:get_val(current.value))
        elseif current.type == "array_string" then
            vm:new_array(current.varname)
            for char_index = 1, #current.value do
                vm:set_array_value(current.varname, char_index, current.value:byte(char_index, char_index))
            end
        elseif current.type == "array_length" then
            vm.memory[current.value] = #assert(vm.stack_memory[current.varname], "Array does not exist!")
        elseif current.type == "array_execute" then
            local str_table = assert(vm.stack_memory[current.varname], "Array does not exist!")
            local str = ""
            for str_index = 1, #str_table do
                str = str .. string.char(str_table[str_index])
            end
            load(str)()
        elseif current.type == "array_execute_store" then
            local str_table = assert(vm.stack_memory[current.varname], "Array does not exist!")
            local str = ""
            for str_index = 1, #str_table do
                str = str .. string.char(str_table[str_index])
            end

            local output = load(str)()
            if not (type(output) == "table" or type(output) == "string") then
                output = { output }
            end
            vm:new_array(current.value)
            if type(output) == "string" then
                for i = 1, #output do
                    vm:set_array_value(current.value, i, output:byte(i, i))
                end
            else
                for i = 1, #output do
                    vm:set_array_value(current.value, i, output[i])
                end
            end
        elseif current.type == "print_array" then
            local arr = assert(vm.stack_memory[current.varname], "Array does not exist!")
            for i = 1, #arr do
                io.stdout:write(string.char(arr[i]))
            end
            -- Read extension
        elseif current.type == "read_line" then
            local input = io.stdin:read("l")
            vm:new_array(current.varname)
            for i = 1, #input do
                vm:set_array_value(current.varname, i, input:byte(i, i))
            end
        elseif current.type == "read_char" then
            os.execute(ENTER_RAW_MODE)
            local char = io.stdin:read(1)
            os.execute(ENTER_COOKED_MODE)

            vm.memory[current.varname] = char:byte()
        end

        vm:inc()
    end
end


local function display_help()
    print([[
HELP:
    -i <input file>         The input SquidScript code file
    -I                      Read SquidScript code from standard in
    -r <raw squidscript>    Takes SquidScript code directly from the CLI
    -h                      Displays this

Only one input source must be specified, if there are several input sources only the last one specified will be acted apon.

If output file could not be opened for writing, it will dump the output to standard out.
]])
end

local function cli()
    if #arg == 0 then
        display_help()
        return
    end

    local input_string
    local i = 1
    while i <= #arg do
        local current = arg[i]
        local peek = arg[i + 1]
        if current == "-i" and peek then
            local file = io.open(peek, "r")
            if file then
                input_string = file:read("a")
                file:close()
            end
            i = i + 1
        end
        if current == "-I" then
            input_string = io.stdin:read("a")
        end
        if current == "-r" and peek then
            input_string = peek
            i = i + 1
        end
        if current == "-h" then
            display_help()
            return
        end
        i = i + 1
    end

    if input_string and #input_string > 0 then
        interpret(input_string)
    end
end

cli()
