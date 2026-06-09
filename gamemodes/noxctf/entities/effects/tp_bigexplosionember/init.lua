function EFFECT:Init(data)
	local dir = data:GetNormal()
	local speed = data:GetScale() * 100

	local max = Vector(3,3,3)
	local min = max * -1
	self:PhysicsInitBox(min,max)
	self:SetCollisionBounds(min,max) 
	self:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)
	local phys = self:GetPhysicsObject()
	if phys:IsValid() then
		phys:Wake()
		phys:ApplyForceCenter(dir * math.random(speed * 0.25, speed))
	end
	self.Living = RealTime() + 4
	self.Emitter = ParticleEmitter(self:GetPos())
	self.Emitter:SetNearClip(24, 32)
	self.NextSmoke = 0
end

function EFFECT:Think()
	self.Emitter:SetPos(self:GetPos())
	local tr = util.TraceLine({start = self:GetPos(), endpos = self:GetPos() + self:GetVelocity():GetNormalized() * 16, mask = MASK_NPCWORLDSTATIC})
	if tr.Hit then
		self.Living = -5
	end

	if self.Living < RealTime() then
		local particle = self.Emitter:Add("effects/fire_cloud1", self:GetPos())
		particle:SetDieTime(1.1)
		particle:SetStartAlpha(255)
		particle:SetEndAlpha(20)
		particle:SetStartSize(90)
		particle:SetEndSize(2)
		particle:SetRoll(math.Rand(0, 360))
		particle:SetRollDelta(math.Rand(-1, 1))
		--self.Emitter:Finish()
		return false
	end

	return true
end

local matFire = Material("effects/fire_cloud1")

function EFFECT:Render()
	render.SetMaterial(matFire)
	local pos = self:GetPos()
	render.DrawSprite(pos, 90, 90, color_white)

	if RealTime() < self.NextSmoke then return end
	self.NextSmoke = RealTime() + math.max(0.03, EFFECT_IQUALITY * 0.05)

	local particle = self.Emitter:Add("particles/smokey", pos + VectorRand() * 8)
	particle:SetVelocity(VectorRand():GetNormalized() * math.Rand(8, 48))
	particle:SetDieTime(math.Rand(0.9, 1.1))
	particle:SetStartAlpha(180)
	particle:SetEndAlpha(0)
	particle:SetStartSize(1)
	particle:SetEndSize(48)
	particle:SetRoll(math.Rand(0, 360))
	particle:SetRollDelta(math.Rand(-3, 3))
	particle:SetColor(20, 20, 20)
end
