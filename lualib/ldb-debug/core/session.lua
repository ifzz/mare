local class = require('ldb-debug/utils/oo').class
local Logger = require('ldb-debug/utils/logger').Logger
local Behavior = require('ldb-debug/core/behavior').Behavior
local Modem = require('ldb-debug/core/modem').Modem
local tablson = require('ldb-debug/core/tablson')

local logger = Logger:new('Session')

local Session = class({

    constructor= function(self, config, iostream)
        self.id = config.id
        self.args = config.args
        self.break_on_start = config.break_on_start

        self.modem = Modem:new(iostream)
        self.modem:on('connect', self:on_modem_connect())
        self.modem:on('command', self:on_modem_command())

        self.behavior = Behavior:new()
        self.handshaked = false
        self.handshaking = false
    end,

    start= function(self)
        self.modem:connect()
        self:send_handshake()
    end,

    on_modem_connect = function(self)
        return function()
            self.handshaked = false
            self.handshaking = false
        end
    end,

    on_modem_command= function(self)
        return function(command)
            local op = command[1]
            local args = command[2]
            logger:log('command: %s', op)
            if op == 'handshaked' then
                self:apply_command_handshake()
                return
            end
            if op == 'message' then
                self:apply_command_message(args)
                return
            end
            logger:error('unhandle command: %s', op)
        end
    end,

    apply_command_handshake= function(self)
        self.handshaked = true
        self.handshaking = false
    end,

    apply_command_message= function(self, message)
        local method = message.method
        local params = message.params
        logger:log('message: %s', method)
        if method == 'setBreakpoints' then
            self.behavior:set_breakpoints(params)
        end
        if method == 'setBlackboxes' then
            self.behavior:set_blackboxes(params)
        end
        if method == 'setMovement' then
            self.behavior:set_movement(params)
        end
        if method == 'execResume' then
            self.behavior:exec_resume()
        end
        if method == 'queryStackScope' then
            self.behavior:query_stack_scope(params)
        end
    end,

    send_heartbeat= function(self)
        self.modem:send_package('heartbeat', nil)
    end,

    send_handshake= function(self)
        if self.handshaking then
            return
        end
        self.handshaking = true
        local url = string.format('/session/%s', self.id)
        self.modem:send_package('handshake', url)
    end,

    send_message= function(self, message)
        if not self.handshaked then
            self:send_handshake()
        end
        self.modem:send_package('message', message)
    end,

    wait_frontend= function(self, timeout)
        if self.modem.iostream:is_opened() then
            self.modem:recv(timeout)
        else
            print('remote closed')
        end
    end,

    console_api= function(self, value, type, stacks)
        local message = {
            method= 'consoleApi',
            params= {
                type= type,
                value= tablson(value),
                stacks= stacks,
            },
        }
        self:send_message(message)
    end,

    debugger_pause= function(self, stacks)
        local message = {
            method= 'debuggerPause',
            params= {
                stacks= stacks,
            },
        }
        self:send_message(message)
    end,

    debugger_resumed= function(self)
        local message = {
            method= 'debuggerResumed',
            params= nil,
        }
        self:send_message(message)
    end,

    stack_scope= function(self, item)
        local message = {
            method= 'stackScope',
            params= {
                id= item.id,
                level= item.level,
                type= item.type,
                value= tablson(item.value),
            }
        }
        self:send_message(message)
    end,
})

return {
    Session= Session,
}
