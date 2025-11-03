local ASR = {}
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

--// Evaluate Keyframe Sequence on time
local function lerp_key(keys, time)
	if time >= keys[#keys].Time then
		return keys[#keys].Key
	end

	for i = 1, #keys-1 do
		local k1, k2 = keys[i], keys[i+1]
		if time >= k1.Time and time <= k2.Time then
			local alpha = (time - k1.Time) / (k2.Time - k1.Time)
			alpha = TweenService:GetValue(alpha, k1.EasingStyle, k1.EasingDirection)
			return k1.Key:Lerp(k2.Key, alpha)
		end
	end

	return keys[1].Key
end

local function load_keys(character, joint, sequence)
	local out = {}
	for _, keyframe in ipairs(sequence:GetChildren()) do
		if keyframe:IsA("Keyframe") then
			for _, desc in ipairs(keyframe:GetDescendants()) do
				if desc.Name == joint.Part1.Name and desc.Parent and desc.Parent.Name == joint.Part0.Name then
					table.insert(out,{
						Time = keyframe.Time,
						Key = desc.CFrame,
						EasingStyle = Enum.EasingStyle[string.gsub(desc.EasingStyle.Name,"V2","")],
						EasingDirection = Enum.EasingDirection[desc.EasingDirection.Name],
					})
				end
			end
		end
	end

	table.sort(out, function(a,b) return a.Time < b.Time end)
	return out
end

--// MOTOR CONTROLLER
function ASR:LoadMotor(character, joint, emulator)
	local module = {
		Joint = joint,
		BaseC0 = joint.C0,
		BaseC1 = joint.C1,
		Keyframes = {}, -- sequence → keys
		EmulatorReference = emulator, -- link
	}

	function module:CacheSequence(seq)
		if not self.Keyframes[seq] then
			self.Keyframes[seq] = load_keys(character, self.Joint, seq)
		end
		return self.Keyframes[seq]
	end

	function module:EvaluateActiveAnimations(tracks)
		-- find tracks that animate this joint
		local influencing = {}

		for _,track in ipairs(tracks) do
			if track.IsPlaying then
				local keys = self:CacheSequence(track.Animation)

				if keys and #keys > 0 then
					local elapsed = (tick() - track.StartTime) * track.Speed
					local lastTime = keys[#keys].Time

					if elapsed >= lastTime then
						if track.Looped then
							track.StartTime = tick()
							elapsed = 0
						else
							track.IsPlaying = false
							continue
						end
					end

					local cf = lerp_key(keys, elapsed)

					table.insert(influencing, {
						track = track,
						cf = cf
					})
				end
			end
		end

		-- no animation affects this joint → bind pose
		local bindPose = CFrame.new()
		if #influencing == 0 then
			self.Joint.Transform = bindPose
			return
		end

		-- sort by priority
		table.sort(influencing, function(a,b)
			return a.track.Priority.Value > b.track.Priority.Value
		end)

		-- highest priority group only
		local topPriority = influencing[1].track.Priority.Value
		local blended = influencing[1].cf
		local totalW = influencing[1].track.Weight

		for i = 2, #influencing do
			local itm = influencing[i]
			if itm.track.Priority.Value < topPriority then break end

			-- sum normalized weights
			local w = itm.track.Weight
			totalW += w
			blended = blended:Lerp(itm.cf, w / totalW)
		end

		-- apply absolute weight against bind pose	
		local weight = math.clamp(totalW, 0, 1)
		-- previous final transform calculation
		local finalTransform = bindPose:Lerp(blended, weight)

		-- apply offset if it exists
		local offset = self.EmulatorReference.Offsets[self.Joint.Name]
		if offset then
			finalTransform = finalTransform * offset
		end

		self.Joint.Transform = finalTransform

	end



	return module
end

--// MAIN EMULATOR
function ASR:EmulateAnimator(character:Model, humanoid:Humanoid)
	local self = {
		Tracks = {},
		Joints = {},
		Offsets = {}, -- new table: { ["MotorName"] = CFrame }
	}

	-- load motors
	for _, joint in character:GetDescendants() do
		if joint:IsA("Motor6D") then
			self.Joints[joint.Name] = ASR:LoadMotor(character, joint, self)
		end
	end

	-- create animation track
	function self:LoadAnimation(sequence)
		local track = {
			Animation = sequence,
			Speed = 1,
			Weight = 1,
			Priority = Enum.AnimationPriority.Core,
			IsPlaying = false,
			StartTime = 0,
			Looped = false,

			Play = function(t)
				t.StartTime = tick()
				t.IsPlaying = true
			end,

			Stop = function(t)
				t.IsPlaying = false
			end,

			AdjustSpeed = function(t,s) t.Speed = s end,
			AdjustWeight = function(t,w) t.Weight = w end,
			AdjustPriority = function(t,p) t.Priority = p end,
		}

		table.insert(self.Tracks, track)
		return track
	end

	-- per-frame blending
	RunService.PreSimulation:Connect(function()
		local active = {}

		-- sort tracks by priority
		for _,t in ipairs(self.Tracks) do
			if t.IsPlaying then 
				table.insert(active, t)
			end
		end

		table.sort(active,function(a,b)
			return a.Priority.Value > b.Priority.Value
		end)

		-- apply blending to each joint
		for _,motor in pairs(self.Joints) do
			motor:EvaluateActiveAnimations(active)
		end
	end)

	return self
end

return ASR
