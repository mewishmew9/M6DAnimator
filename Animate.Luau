local ASR = {}
local ts = game:GetService("TweenService")

function ASR:LoadMotor(character,bne,sequence)
	local ASR_Motor_Object = {
		Looped = false;
		Active = false;
	}
	
	local t = tick()
	local loaded_keys = load_keys(character,bne,sequence)
	local simu = game:GetService("RunService").PreSimulation:Connect(function()
		if ASR_Motor_Object.Active then
			bne.Transform = get_key_cf(loaded_keys,t);
			if tick()-t>=loaded_keys[#loaded_keys].Time then
				if ASR_Motor_Object.Looped then
					t = tick()
				else
					ASR_Motor_Object:Stop();
				end
			end
		end
	end);
	
	function ASR_Motor_Object:Activate(optional_tick)
		t = optional_tick or tick();
		self.Active = true;
	end;
	
	function ASR_Motor_Object:Stop()
		self.Active = false;
	end;
	
	function ASR_Motor_Object:Dismiss()
		simu:Disconnect();
	end;
	
	return ASR_Motor_Object
end;

function get_key_cf(lk,t,endt)
	local cf = CFrame.new();
	if lk[#lk].Time<tick()-t then
		cf = lk[#lk].Key
	else
		for i,v in pairs(lk) do
			if v.Time<=tick()-t and lk[i+1].Time>=tick()-t then
				cf = v.Key:Lerp(lk[i+1].Key,ts:GetValue((tick() - t - v.Time) / (lk[i+1].Time - v.Time), v.EasingStyle, v.EasingDirection))
			end
		end
	end
	return cf
end

function find_obm(keyframe,char,bne)
	if bne then
		for i,v in pairs(keyframe:GetDescendants()) do
			if v.Name == bne.Part1.Name and v.Parent.Name == bne.Part0.Name then
				return v
			end
		end
	end
end

function load_keys(character,bne,sequence)
	local keys = {}
	for i,v in pairs(sequence:GetChildren()) do
		if v:IsA("Keyframe") then
			local keypart = find_obm(v,character,bne);
			if keypart then
				table.insert(keys,{
					Key = keypart.CFrame;
					EasingDirection = Enum.EasingDirection[keypart.EasingDirection.Name];
					EasingStyle = Enum.EasingStyle[string.gsub(keypart.EasingStyle.Name,"V2","")];
					Time = v.Time;
				});
			end
		end
	end
	table.sort(keys,function(a,b)
		return a.Time<b.Time;
	end);
	return keys
end;

return ASR
