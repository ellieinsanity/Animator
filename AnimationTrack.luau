--!nocheck
local TweenService = game:GetService("TweenService")
local Signal = loadstring(game:HttpGet("https://raw.githubusercontent.com/ellieinsanity/Animator/refs/heads/main/Signal.luau"))()
local getLerpAlpha = loadstring(game:HttpGet("https://raw.githubusercontent.com/ellieinsanity/Animator/refs/heads/main/easing.luau"))()

local AnimationTrack = {}
AnimationTrack.__index = AnimationTrack

function AnimationTrack:AdjustSpeed(speed)
	self.Speed = speed
end

function AnimationTrack:AdjustWeight(weight, fadeTime)
	self.Weight = weight
end

function AnimationTrack:GetMarkerReachedSignal(name)
	self._markerReachedSignals = self._markerReachedSignals or {}
	local event = self._markerReachedSignals[name]
	if not event then
		event = Signal.new("MarkerReached")
		self._markerReachedSignals[name] = event
	end
	return event
end

function AnimationTrack:GetTimeOfKeyframe(keyframeName)
	return self._keyframeTimes[keyframeName] or error("Keyframe not found: " .. keyframeName)
end

local Cframe = CFrame.new()

function AnimationTrack:Play(fadeTime, weight, speed)
	fadeTime = fadeTime or 0.1
	speed = speed or 1
	self.Speed = speed
	self.Weight = weight or 1

	if self.IsPlaying then return end
	self.IsPlaying = true

	local startTime = tick()
	self._startTime = startTime

	local function step()
		local now = tick()
		local elapsedTime = now - startTime
		local weight = math.min(elapsedTime / fadeTime, 1) * self.Weight

		if self.Length == 0 then
			for _, jointName in (self._jointNames) do
				self._transforms[jointName] = Cframe
			end
			return self._transforms, weight
		end

		local timePosition = elapsedTime * self.Speed
		if timePosition > self.Length then
			if self.Looped then
				timePosition = timePosition % self.Length
				self:reset()
				self.DidLoop:Fire()
			else
				self:Stop(0.5)
				return nil, 0
			end
		end
		self.TimePosition = timePosition

		for name, time in (self._keyframeTimes) do
			if timePosition >= time and not self._passedKeyframes[name] then
				self._passedKeyframes[name] = true
				self.KeyframeReached:Fire(name)
			end
		end
		for name, time in (self._markerTimes) do
			if timePosition >= time and not self._passedMarkers[name] then
				self._passedMarkers[name] = true
				self._markerReachedSignals[name]:Fire()
			end
		end


		for _, jointName in (self._jointNames) do
			local poses = self._keyframes[jointName]
			if not poses or #poses == 0 then
				self._transforms[jointName] = Cframe
				continue
			elseif #poses == 1 then
				self._transforms[jointName] = poses[1].CFrame
				continue
			end

			local poseIndex = self:findPoseIndex(jointName, timePosition)
			local lastPose = poses[poseIndex]
			local nextPose = poses[poseIndex + 1]

			self._transforms[jointName] = nextPose and self:interpolatePoses(lastPose, nextPose, timePosition) or lastPose.CFrame
		end

		return self._transforms, weight
	end

	self._step = step
end

function AnimationTrack:findPoseIndex(jointName, timePosition)
	local poses = self._keyframes[jointName]
	local low = 1
	local high = #poses
	while low <= high do
		local mid = math.floor((low + high) / 2)
		if poses[mid].time < timePosition then
			low = mid + 1
		else
			high = mid - 1
		end
	end
	return math.max(1, low - 1)
end

function AnimationTrack:interpolatePoses(lastPose, nextPose, timePosition)
	local dt = (timePosition - lastPose.time) / (nextPose.time - lastPose.time)
	return lastPose.CFrame:Lerp(nextPose.CFrame, getLerpAlpha(dt, nextPose.easingStyle, nextPose.easingDirection))
end

function AnimationTrack:reset()
	self._passedKeyframes = {}
	self._passedMarkers = {}
end

function AnimationTrack:_fadeOut(fadeTime:number)
	local startTime = tick()
	local initCFrames = table.clone(self._transforms)

	local function step()
		local elapsed = tick() - startTime
		local a = math.min(elapsed / fadeTime, 1)
		if a == 1 then
			self.Ended:Fire()
			self._step = nil
			return
		end
		local newTransforms = {}
		for jointName, initCF in (initCFrames) do
			newTransforms[jointName] = initCF:Lerp(Cframe, a)
		end
		self._transforms = newTransforms
		return newTransforms, 1
	end
	self._step = step
end


function AnimationTrack:Stop(fadeTime)
	if not self.IsPlaying then return end
	self.IsPlaying = false
	self.Stopped:Fire()
	self._step = nil
	self._startTime = nil
	if (fadeTime or 0) > 0 then
		self:_fadeOut(fadeTime)
	else
		self.Ended:Fire()
	end
end


function AnimationTrack.new(parent, keyframeSequence)
	local self = setmetatable({}, AnimationTrack)
	self.IsPlaying = false
	self.Length = 0
	self.Looped = keyframeSequence.Loop
	self.Speed = 1
	self.TimePosition = 0
	self.Priority = keyframeSequence.Priority
	self.Name = keyframeSequence.Name
	self.Weight = 1
	self.DidLoop = Signal.new("DidLoop")
	self.Ended = Signal.new("Ended")
	self.Stopped = Signal.new("Stopped")
	self.KeyframeReached = Signal.new("KeyframeReached")
	self._parent = parent
	self._keyframeSequence = keyframeSequence
	self._destroyed = false
	self._keyframes = {}
	self._keyframeTimes = {}
	self._markerTimes = {}
	self._jointNames = {}
	self._transforms = {}
	self._step = nil
	self._markerReachedSignals = {}
	self._passedKeyframes = {}
	self._passedMarkers = {}


	for _, keyframe in (keyframeSequence:GetChildren()) do
		self.Length = math.max(self.Length, keyframe.time)
		if keyframe.Name ~= "Keyframe" then
			self._keyframeTimes[keyframe.Name] = keyframe.time
		end
		for _, marker in (keyframe:GetMarkers()) do
			self._markerTimes[marker.Name] = keyframe.time
		end
		local rootPose = keyframe:FindFirstChild("HumanoidRootPart")
		if not rootPose then continue end
		for _, pose in (rootPose:GetDescendants()) do
			if pose:IsA("Pose") and pose.Weight > 0 then
				local keyframes = self._keyframes[pose.Name]
				if not keyframes then
					keyframes = {}
					self._keyframes[pose.Name] = keyframes
					self._transforms[pose.Name] = Cframe
					table.insert(self._jointNames, pose.Name)
				end
				table.insert(keyframes, {time = keyframe.Time, CFrame = pose.CFrame, easingDirection = pose.EasingDirection.Value, easingStyle = pose.EasingStyle.Value})
			end
		end
	end

	for _, jointKeyframes in (self._keyframes) do
		table.sort(jointKeyframes, function(a, b) return a.time < b.time end)
		if self.Looped and #jointKeyframes > 1 then
			local last = table.clone(jointKeyframes[#jointKeyframes])
			last.time = last.time - self.Length
			table.insert(jointKeyframes, 1, last)
		end
	end

	return self
end

return AnimationTrack
