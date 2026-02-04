local TweenService = game:GetService("TweenService")

local round = math.round
local getValue = TweenService.GetValue
local easingDirections = Enum.EasingDirection:GetEnumItems()

local easingFuncs = {}

for _, poseEasingStyle in Enum.PoseEasingStyle:GetEnumItems() do
	if poseEasingStyle == Enum.PoseEasingStyle.Constant then
		continue
	end
	local directions = {}
	local easingStyle
	if (poseEasingStyle.Name == "CubicV2") then
		easingStyle = Enum.EasingStyle.Cubic
	else
		easingStyle = Enum.EasingStyle[poseEasingStyle.Name]
	end
	for _, direction in easingDirections do

		directions[direction.Value] = function(a)
			return getValue(TweenService, a, easingStyle, direction)
		end
	end
	easingFuncs[poseEasingStyle.Value] = directions
end

easingFuncs[Enum.PoseEasingStyle.Constant.Value] = {
	[0] = round,
	[1] = round,
	[2] = round,
}

local function getLerpAlpha(a, poseEasingStyleValue, poseEasingDirectionValue)
	return easingFuncs[poseEasingStyleValue][poseEasingDirectionValue](a)
end

return getLerpAlpha
