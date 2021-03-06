﻿-- ToME - Tales of Maj'Eyal
-- Copyright (C) 2009 - 2014 Nicolas Casalini
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.
--
-- Nicolas Casalini "DarkGod"
-- darkgod@te4.org

newTalent{
	name = "Soul Rot",
	kr_name = "영혼의 부패",
	type = {"corruption/vim", 1},
	require = corrs_req1,
	points = 5,
	cooldown = 4,
	vim = 10,
	range = 10,
	proj_speed = 10,
	tactical = { ATTACK = {BLIGHT = 2} },
	requires_target = true,
	getCritChance = function(self, t) return self:combatTalentScale(t, 7, 25, 0.75) end,
	action = function(self, t)
		local tg = {type="bolt", range=self:getTalentRange(t), talent=t, display={particle="bolt_slime"}}
		local x, y = self:getTarget(tg)
		if not x or not y then return nil end
		self:projectile(tg, x, y, DamageType.BLIGHT, self:spellCrit(self:combatTalentSpellDamage(t, 20, 250), t.getCritChance(self, t)), {type="slime"})
		game:playSoundNear(self, "talents/slime")
		return true
	end,
	info = function(self, t)
		return ([[순수한 황폐의 기운을 발사하여, %0.2f 황폐 속성 피해를 줍니다.
		이 마법은 치명타 확률이 다른 마법보다 %0.2f%% 더 높습니다.
		피해량은 주문력의 영향을 받아 증가합니다.]]):
		format(damDesc(self, DamageType.BLIGHT, self:combatTalentSpellDamage(t, 20, 250)), t.getCritChance(self, t))
	end,
}

newTalent{
	name = "Vimsense",
	kr_name = "원혼의 기운",
	type = {"corruption/vim", 2},
	require = corrs_req2,
	points = 5,
	cooldown = 25,
	vim = 25,
	requires_target = true,
	no_npc_use = true,
	getDuration = function(self, t) return math.floor(self:combatTalentScale(t, 4, 8)) end,
	getResistPenalty = function(self, t) return self:combatTalentSpellDamage(t, 10, 45) end, -- Consider reducing this
	action = function(self, t)
		local rad = 10
		self:setEffect(self.EFF_SENSE, t.getDuration(self,t), {
			range = rad,
			actor = 1,
			VimsensePenalty = t.getResistPenalty(self,t), -- Compute resist penalty at time of activation
			on_detect = function(self, x, y)
				local a = game.level.map(x, y, engine.Map.ACTOR)
				if not a or self:reactionToward(a) >= 0 then return end
				a:setTarget(game.player)
				a:setEffect(a.EFF_VIMSENSE, 2, {power=self:hasEffect(self.EFF_SENSE).VimsensePenalty or 0})
			end,
		})
		game:playSoundNear(self, "talents/spell_generic")
		return true
	end,
	info = function(self, t)
		return ([[주변 10 칸 반경의 적들을 %d 턴 동안 감지합니다.
		사악한 기운이 적들을 둘러싸 황폐 속성 저항력을 %d%% 낮추지만, 그 대신 적들도 시전자의 존재를 느끼게 됩니다.
		저항 감소량은 주문력의 영향을 받아 증가합니다.]]):
		format(t.getDuration(self,t), t.getResistPenalty(self,t))
	end,
}

newTalent{
	name = "Leech",
	kr_name = "착취",
	type = {"corruption/vim", 3},
	require = corrs_req3,
	mode = "passive",
	points = 5,
	-- called by _M:onTakeHit function in mod\class\Actor.lua	
	getVim = function(self, t) return self:combatTalentScale(t, 3.7, 6.5, 0.75) end,
	getHeal = function(self, t) return self:combatTalentScale(t, 8, 20, 0.75) end,
	info = function(self, t)
		return ([[원혼의 기운이 깃든 적에게 공격받으면, %0.2f 원기와 %0.2f 생명력이 회복됩니다.]]):
		format(t.getVim(self,t),t.getHeal(self,t))
	end,
}

newTalent{
	name = "Dark Portal",
	kr_name = "어둠의 문",
	type = {"corruption/vim", 4},
	require = corrs_req4,
	points = 5,
	vim = 30,
	cooldown = 15,
	tactical = { ATTACKAREA = {BLIGHT = 1}, DISABLE = 2, ESCAPE = 2 },
	range = 7,
	radius = 3,
	action = function(self, t)
		local tg = {type="ball", radius=self:getTalentRadius(t), range=self:getTalentRange(t), talent=t}
		local x, y = self:getTarget(tg)
		if not x or not y then return nil end
		local actors = {}
		self:project(tg, x, y, function(px, py)
			local target = game.level.map(px, py, Map.ACTOR)
			if not target or target == self then return end
			if not target:canBe("teleport") then game.logSeen("어둠의 문에 끌려가지 않고 저항한 개체(%s)가 있습니다!") return end
			actors[#actors+1] = target
		end)
		local _ _, x, y = self:canProject(tg, x, y)
		game.level.map:particleEmitter(x, y, tg.radius, "circle", {empty_start=8, oversize=1, a=80, appear=8, limit_life=11, speed=5, img="green_demon_fire_circle", radius=tg.radius})
		game.level.map:particleEmitter(x, y, tg.radius, "circle", {oversize=1, a=80, appear=8, limit_life=11, speed=5, img="demon_fire_circle", radius=tg.radius})
		game.level.map:particleEmitter(self.x, self.y, tg.radius, "circle", {appear_size=2, empty_start=8, oversize=1, a=80, appear=11, limit_life=8, speed=5, img="green_demon_fire_circle", radius=tg.radius})
		game.level.map:particleEmitter(self.x, self.y, tg.radius, "circle", {appear_size=2, oversize=1, a=80, appear=8, limit_life=11, speed=5, img="demon_fire_circle", radius=tg.radius})

		for i, a in ipairs(actors) do
			local tx, ty = util.findFreeGrid(self.x, self.y, 20, true, {[Map.ACTOR]=true})
			if tx and ty then a:move(tx, ty, true) end
			if a:canBe("disease") then
				local diseases = {{self.EFF_WEAKNESS_DISEASE, "str"}, {self.EFF_ROTTING_DISEASE,"con"}, {self.EFF_DECREPITUDE_DISEASE,"dex"}}
				local disease = rng.table(diseases)
				a:setEffect(disease[1], 6, {src=self, dam=self:spellCrit(self:combatTalentSpellDamage(t, 12, 80)), [disease[2]]=self:combatTalentSpellDamage(t, 5, 25)})
			end
		end

		local tx, ty = util.findFreeGrid(x, y, 20, true, {[Map.ACTOR]=true})
		if tx and ty then self:teleportRandom(x, y, 0) end

		game:playSoundNear(self, "talents/slime")
		return true
	end,
	info = function(self, t)
		return ([[선택한 지점의 주변 3 칸 반경에 어둠의 문이 열립니다. 해당 영역의 모든 적들은 시전자가 있던 곳으로 이동되며, 시전자는 선택 지점으로 이동합니다.
		어둠의 문을 통과한 모든 적들은 질병에 걸려, 6 턴 동안 매 턴마다 %0.2f 황폐 속성 피해를 받으며 힘, 체격, 민첩 능력치 중 하나가 %d 감소합니다.
		피해량은 주문력의 영향을 받아 증가합니다.]]):format(damDesc(self, DamageType.BLIGHT, self:combatTalentSpellDamage(t, 12, 80)), self:combatTalentSpellDamage(t, 5, 25))
	end,
}
