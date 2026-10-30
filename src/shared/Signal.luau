--!strict
-- Signal: small event helper (Connect / Fire / Wait / Disconnect).
-- Each handler runs in its own thread, so one erroring handler can't break the others.

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

local Connection = {}
Connection.__index = Connection

function Connection.Disconnect(self: any)
	if not self.Connected then
		return
	end
	self.Connected = false
	local handlers = self._signal._handlers
	local index = table.find(handlers, self)
	if index then
		table.remove(handlers, index)
	end
end

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} :: { any } }, Signal)
end

function Signal.Connect(self: any, fn: (...any) -> ()): Connection
	local connection = setmetatable({ Connected = true, _fn = fn, _signal = self }, Connection)
	table.insert(self._handlers, connection)
	return connection :: any
end

function Signal.Fire(self: any, ...: any)
	for _, connection in table.clone(self._handlers) do
		if connection.Connected then
			task.spawn(connection._fn, ...)
		end
	end
end

-- Yields until the next Fire and returns its arguments.
function Signal.Wait(self: any): ...any
	local thread = coroutine.running()
	local connection
	connection = Signal.Connect(self, function(...)
		connection:Disconnect()
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

return Signal
