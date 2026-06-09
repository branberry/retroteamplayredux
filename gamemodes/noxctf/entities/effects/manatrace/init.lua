function EFFECT:Init(data)
	self.EndPos = data:GetOrigin()
	local wep = data:GetEntity()

	if wep:IsValid() then
		if wep == MySelf:GetActiveWeapon() then
			local attach
			if MySelf:ShouldDrawLocalPlayer() then
				attach = wep:GetAttachment(data:GetAttachment())
			else
				attach = MySelf:GetViewModel():GetAttachment(data:GetAttachment())
			end
			if attach then
				self.StartPos = attach.Pos
			else
				self.StartPos = data:GetStart()
			end
		elseif wep:IsWeapon() then
			local attach = wep:GetAttachment(data:GetAttachment())
			if attach then
				self.StartPos = attach.Pos
			else
				self.StartPos = data:GetStart()
			end
		else
			self.StartPos = data:GetStart()
		end

		local owner = wep:GetOwner()
		if owner:IsValid() then
			self.Col = owner:GetColor()
		elseif wep.Team and type(wep.Team) == "function" then
			self.Col = team.GetColor(wep:Team())
		else
			self.Col = wep:GetColor()
		end
	else
		self.StartPos = data:GetStart()
	end

	self.Dir = self.EndPos - self.StartPos

	self.TracerTime = math.max(0.05, math.min(0.35, self.EndPos:Distance(self.StartPos) * 0.0001))

	self.DieTime = CurTime() + self.TracerTime
	self.DieTimeTwo = self.DieTime + math.Rand(0.7, 1)
	self.SpriteSize = math.Rand(14, 20)

	self.Col = self.Col or color_white
	local c = self.Col

	self:SetRenderBoundsWS(self.StartPos, self.EndPos, Vector(24, 24, 24))
	self:SetModel("models/Weapons/w_bullet.mdl")
	self:SetMaterial("models/shiny")
	self:SetRenderMode(RENDERMODE_TRANSALPHA)
	self:SetColor(Color(c.r, c.g, c.b, 255))
	self:SetModelScale(1.5, 0)
	self:SetAngles(self.Dir:Angle())
end

function EFFECT:Think()
	return CurTime() < self.DieTimeTwo
end

local matBeam = Material("Effects/laser1")
local matGlow = Material("sprites/glow04_noz")
function EFFECT:Render()
	local ct = CurTime()
	if ct < self.DieTime then
		local fDelta = (self.DieTime - ct) / self.TracerTime
		fDelta = math.Clamp(fDelta, 0, 1)

		render.SetMaterial(matBeam)
		local sinWave = math.sin(fDelta * math.pi)
		local endpos = self.EndPos - self.Dir * (fDelta - sinWave * 0.3)
		render.DrawBeam(endpos, self.EndPos - self.Dir * (fDelta + sinWave * 0.3), 2 + sinWave * 8, 1, 0, self.Col)

		render.SetMaterial(matGlow)
		local siz = math.Rand(16, 24)
		render.DrawSprite(endpos, siz, siz, self.Col)
		self:SetPos(endpos)
	else
		local c = self.Col
		if not self.EndParticles then
			self.EndParticles = true
			local emitter = ParticleEmitter(self.EndPos)
			for i=1, math.max(2, EFFECT_QUALITY * 2) do
				local particle = emitter:Add("noxctf/sprite_nova", self.EndPos)
				particle:SetDieTime(math.Rand(0.3, 0.5))
				particle:SetStartAlpha(255)
				particle:SetEndAlpha(0)
				particle:SetStartSize(1)
				particle:SetEndSize(8)
				particle:SetVelocity(VectorRand():GetNormal() * 800)
				particle:SetAirResistance(1200)
				particle:SetColor(c.r, c.g, c.b)
			end
		end

		local siz = (self.DieTimeTwo - ct) * 32
		render.SetMaterial(matGlow)
		render.DrawSprite(self.EndPos, siz, siz, col)
		self:SetColor(Color(c.r, c.g, c.b, math.min(255, (self.DieTimeTwo - ct) * 510)))
		self:SetPos(self.EndPos)
	end

	self:DrawModel()
end
