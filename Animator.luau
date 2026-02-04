local RunService = game:GetService("RunService")
local AnimationTrack = loadstring(game:HttpGet("https://raw.githubusercontent.com/ellieinsanity/Animator/refs/heads/main/AnimationTrack.luau"))()

type JointDataType = {
	joint: Motor6D,
	c0: CFrame
}

type AnimatorType = {
	_animations: {AnimationTrack},
	_humanoid: Humanoid,
	_destroyed: boolean,
	_joints: {[string]: JointDataType},
	_transforms: {[string]: CFrame},
	_jointTrackers: {[Instance]: () -> ()},
	_stepped: RBXScriptConnection?,
	_descendantAdded: RBXScriptConnection?,
	_descendantRemoving: RBXScriptConnection?,
	LoadAnimation: (self: AnimatorType, keyframeSequence: KeyframeSequence) -> AnimationTrack,
	GetPlayingAnimations: (self: AnimatorType) -> {string},
	Destroy: (self: AnimatorType) -> (),
	new: (humanoid: Humanoid) -> AnimatorType,
	AnimationMode: {Transform: number, C0: number, Combined: number}
}

local Animator: AnimatorType = {}
Animator.__index = Animator

local AnimationMode = {
	Transform = 0,
	C0 = 1,
	Combined = 2
}

Animator.AnimationMode = AnimationMode

local function createTracker(object: Instance, propertyName: string, onSet: (string) -> (), onUnset: (string?) -> ())
	local currentValue: string?
	local propertyChangedConnection: RBXScriptConnection?
	local partTracker: (() -> ())?

	local function onPropertyChanged(newValue: string)
		onUnset(currentValue)
		currentValue = newValue
		onSet(currentValue)
	end

	if object[propertyName] then
		currentValue = object[propertyName].Name
		if propertyName == "Part1" then
			partTracker = function()
				propertyChangedConnection:Disconnect()
			end
			propertyChangedConnection = (object[propertyName]::Instance):GetPropertyChangedSignal("Name"):Connect(onPropertyChanged)
		end
	end

	local part1ChangedConnection: RBXScriptConnection = object:GetPropertyChangedSignal(propertyName):Connect(function()
		onUnset(currentValue)
		if partTracker then
			partTracker()
			partTracker = nil
		end
		if object[propertyName] then
			currentValue = object[propertyName].Name
			onSet(currentValue)
			if propertyName == "Part1" then
				partTracker = function()
					propertyChangedConnection:Disconnect()
				end
				propertyChangedConnection = (object[propertyName]::Instance):GetPropertyChangedSignal("Name"):Connect(onPropertyChanged)
			end
		end
	end)

	return function()
		part1ChangedConnection:Disconnect()
		if partTracker then
			partTracker()
		end
	end
end


function Animator:LoadAnimation(keyframeSequence: KeyframeSequence): AnimationTrack
	for _, animation in (self._animations) do
		if animation._keyframeSequence == keyframeSequence then
			return animation
		end
	end
	local animation = AnimationTrack.new(self, keyframeSequence)
	table.insert(self._animations, animation)
	return animation
end

function Animator:GetPlayingAnimations(): {string}
	local animationNames: {string} = {}
	for _, animation in (self._animations) do
		if animation.IsPlaying then
			table.insert(animationNames, animation.Name)
		end
	end
	return animationNames
end

function Animator:Destroy()
	self._destroyed = true
	for _, stopTracker in (self._jointTrackers) do stopTracker() end
	self._animations = {}
	self._jointTrackers = {}
	self._stepped:Disconnect()
	self._descendantAdded:Disconnect()
	self._descendantRemoving:Disconnect()
	self._stepped = nil
	self._descendantAdded = nil
	self._descendantRemoving = nil
end



function Animator.new(humanoid: Humanoid): AnimatorType
	local self = setmetatable({}, Animator)
	self._animations = {}
	self.AnimationMode = AnimationMode.Combined
	self._humanoid = humanoid
	self._destroyed = false
	self._joints = {}
	self._transforms = {}
	self._jointTrackers = {}
	self._stepped = nil
	self._descendantAdded = nil
	self._descendantRemoving = nil

	self._stepped = RunService.Stepped:Connect(function(deltaTime)
		local currentTransforms = self._transforms
		local joints = self._joints
		local newTransforms = {}
		local priorities = {}
		for jointName in (joints) do
			priorities[jointName] = 0
		end

		for _, animation in (self._animations) do
			if not animation._step then continue end
			local priority = animation.Priority.Value
			local transforms, weight = animation._step()
			if not transforms then continue end

			for jointName, cf in (transforms) do
				if not joints[jointName] then continue end
				if priority > priorities[jointName] then
					priorities[jointName] = priority
					newTransforms[jointName] = {animation._startTime, cf, weight}
				elseif not newTransforms[jointName] or animation._startTime > newTransforms[jointName][1] then
					newTransforms[jointName] = {animation._startTime, cf, weight}
				end
			end
		end

		for jointName, cfData in (newTransforms) do
			local weight = cfData[3]
			pcall(function()
				newTransforms[jointName] = weight == 1 and cfData[2] or currentTransforms[jointName]:Lerp(cfData[2], weight)
			end)
		end

		for jointName, jointData in (joints) do
			local cf = newTransforms[jointName] or CFrame.new()
			local transform = cf
			local isTransformChanged = transform ~= currentTransforms[jointName]
			if self.AnimationMode == AnimationMode.Transform then
				jointData.joint.Transform = transform
			elseif self.AnimationMode == AnimationMode.C0 then
				pcall(function()
					jointData.joint.C0 = jointData.c0 * transform
				end)
			else
				jointData.joint.C0 = isTransformChanged and transform or jointData.c0 * transform
			end
		end
		self._transforms = newTransforms
	end)

	local function onJointDescendant(joint)
		if joint.ClassName == "Motor6D" then
			local jointData = {joint = joint, c0 = joint.C0}
			if joint.Part1 then
				self._joints[joint.Part1.Name] = jointData
				self._transforms[joint.Part1.Name] = CFrame.new()
			end
			self._jointTrackers[joint] = createTracker(joint, "Part1", function(name)
				self._joints[name] = jointData
				self._transforms[name] = self._transforms[name] or CFrame.new()
			end, function()
				self._joints[joint.Part1.Name] = nil
			end)
		end
	end

	self._descendantAdded = humanoid.Parent.DescendantAdded:Connect(onJointDescendant)
	self._descendantRemoving = humanoid.Parent.DescendantRemoving:Connect(function(joint)
		if joint.ClassName == "Motor6D" then
			if joint.Part1 then
				self._joints[joint.Part1.Name] = nil
			end
			self._jointTrackers[joint]()
			self._jointTrackers[joint] = nil
		end
	end)

	for _, joint in (humanoid.Parent:GetDescendants()) do
		onJointDescendant(joint)
	end

	return self
end

return Animator
