local Signal = {}
local Connection = {}
Signal.__index = Signal
Connection.__index = Connection

function Connection:Disconnect()
	self.Connected = false
	local index = table.find(self._parent._connections, self)
	if index then
		table.remove(self._parent._connections, index)
	end
end

function Connection.new(parent, callback)
	local self = setmetatable({}, Connection)
	self.Connected = true
	self._callback = callback
	self._parent = parent
	self._once = false
	parent._connections = parent._connections or {}
	table.insert(parent._connections, self)
	return self
end

function Signal:Connect(callback)
	assert(type(callback) == "function", "callback must be a function")
	return Connection.new(self, callback)
end

function Signal:Once(callback)
	assert(type(callback) == "function", "callback must be a function")
	local connection = Connection.new(self, callback)
	connection._once = true
	return connection
end

function Signal:Wait()
	local thread = coroutine.running()
	self._waitingThreads = self._waitingThreads or {}
	table.insert(self._waitingThreads, thread)
	return coroutine.yield()
end

function Signal:Fire(...)
	for _, connection in ipairs(self._connections or {}) do
		coroutine.wrap(connection._callback)(...)
		if connection._once then
			connection:Disconnect()
		end
	end
	for _, thread in ipairs(self._waitingThreads or {}) do
		coroutine.resume(thread, ...)
	end
	self._waitingThreads = {}
end

function Signal:Destroy()
	for _, connection in ipairs(self._connections or {}) do
		connection:Disconnect()
	end
	self._waitingThreads = {}
end

function Signal.new(name)
	local self = setmetatable({}, Signal)
	self._name = name
	return self
end

return Signal
