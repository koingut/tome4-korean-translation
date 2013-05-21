﻿-- ToME - Tales of Maj'Eyal
-- Copyright (C) 2009, 2010, 2011, 2012, 2013 Nicolas Casalini
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

require "engine.krtrUtils"

newTalent{
	name = "Dual Weapon Training",
	kr_name = "쌍수 무기 수련",
	type = {"technique/dualweapon-training", 1},
	mode = "passive",
	points = 5,
	require = techs_dex_req1,
	info = function(self, t)
		return ([[보조 무기의 피해 효율이 %d%% 가 됩니다.]]):format(100 / (2 - (math.min(self:getTalentLevel(t), 8) / 6)))
	end,
}

newTalent{
	name = "Dual Weapon Defense",
	kr_name = "쌍수 무기 방어술",
	type = {"technique/dualweapon-training", 2},
	mode = "passive",
	points = 5,
	require = techs_dex_req2,
	info = function(self, t)
		return ([[무기로 공격을 흘려내는 방법을 익혀, 회피도가 %d 증가합니다.
		회피도는 민첩성 능력치의 영향을 받아 증가합니다.]]):format(4 + (self:getTalentLevel(t) * self:getDex()) / 12)
	end,
}

newTalent{
	name = "Precision",
	kr_name = "허점 포착",
	type = {"technique/dualweapon-training", 3},
	mode = "sustained",
	points = 5,
	require = techs_dex_req3,
	no_energy = true,
	cooldown = 10,
	sustain_stamina = 20,
	tactical = { BUFF = 2 },
	on_pre_use = function(self, t, silent) if not self:hasDualWeapon() then if not silent then game.logPlayer(self, "이 기술을 사용하려면 쌍수 무장을 해야 합니다.") end return false end return true end,
	activate = function(self, t)
		local weapon, offweapon = self:hasDualWeapon()
		if not weapon then
			game.logPlayer(self, "쌍수 무장을 하지 않으면 허점 포착을 사용할 수 없습니다!")
			return nil
		end

		return {
			apr = self:addTemporaryValue("combat_apr", 4 + (self:getTalentLevel(t) * self:getDex()) / 20),
		}
	end,
	deactivate = function(self, t, p)
		self:removeTemporaryValue("combat_apr", p.apr)
		return true
	end,
	info = function(self, t)
		return ([[허점을 정확히 노리는 자세를 취해서, 방어도 관통력이 %d 증가합니다.
		방어도 관통력은 민첩 능력치의 영향을 받아 증가합니다.]]):format(4 + (self:getTalentLevel(t) * self:getDex()) / 20)
	end,
}

newTalent{
	name = "Momentum",
	kr_name = "탄력적 공격",
	type = {"technique/dualweapon-training", 4},
	mode = "sustained",
	points = 5,
	cooldown = 30,
	sustain_stamina = 50,
	require = techs_dex_req4,
	tactical = { BUFF = 2 },
	on_pre_use = function(self, t, silent) if not self:hasDualWeapon() then if not silent then game.logPlayer(self, "이 기술을 사용하려면 쌍수 무장을 해야 합니다.") end return false end return true end,
	activate = function(self, t)
		local weapon, offweapon = self:hasDualWeapon()
		if not weapon then
			game.logPlayer(self, "쌍수 무장을 하지 않으면 탄력적 공격을 사용할 수 없습니다!")
			return nil
		end

		return {
			combat_physspeed = self:addTemporaryValue("combat_physspeed", self:getTalentLevel(t) * 0.14),
			stamina_regen = self:addTemporaryValue("stamina_regen", -6),
		}
	end,
	deactivate = function(self, t, p)
		self:removeTemporaryValue("combat_physspeed", p.combat_physspeed)
		self:removeTemporaryValue("stamina_regen", p.stamina_regen)
		return true
	end,
	info = function(self, t)
		local weapon, offweapon = self:hasDualWeapon()
		weapon = weapon or {}
		return ([[공격 속도가 %d%% 증가하지만, 체력을 급격히 소진하게 됩니다. (매 턴마다 체력 6 감소)]]):format(self:getTalentLevel(t) * 14)
	end,
}

------------------------------------------------------
-- Attacks
------------------------------------------------------
newTalent{
	name = "Dual Strike",
	kr_name = "이중 타격",
	type = {"technique/dualweapon-attack", 1},
	points = 5,
	random_ego = "attack",
	cooldown = 12,
	stamina = 15,
	require = techs_dex_req1,
	requires_target = true,
	tactical = { ATTACK = { weapon = 1 }, DISABLE = { stun = 2 } },
	on_pre_use = function(self, t, silent) if not self:hasDualWeapon() then if not silent then game.logPlayer(self, "이 기술을 사용하려면 쌍수 무장을 해야 합니다.") end return false end return true end,
	action = function(self, t)
		local weapon, offweapon = self:hasDualWeapon()
		if not weapon then
			game.logPlayer(self, "쌍수 무장을 하지 않으면 이중 타격을 사용할 수 없습니다!")
			return nil
		end

		local tg = {type="hit", range=self:getTalentRange(t)}
		local x, y, target = self:getTarget(tg)
		if not x or not y or not target then return nil end
		if core.fov.distance(self.x, self.y, x, y) > 1 then return nil end

		-- First attack with offhand
		local speed, hit = self:attackTargetWith(target, offweapon.combat, nil, self:getOffHandMult(offweapon.combat, self:combatTalentWeaponDamage(t, 0.7, 1.5)))

		-- Second attack with mainhand
		if hit then
			if target:canBe("stun") then
				target:setEffect(target.EFF_STUNNED, 2 + self:getTalentLevel(t), {apply_power=self:combatAttack()})
			else
				game.logSeen(target, "%s 기절하지 않았습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			end

			-- Attack after the stun, to benefit from backstabs
			self:attackTargetWith(target, weapon.combat, nil, self:combatTalentWeaponDamage(t, 0.7, 1.5))
		end

		return true
	end,
	info = function(self, t)
		return ([[보조 무기로 공격하여 %d%% 의 무기 피해를 줍니다. 이 공격이 성공하면 대상은 %d 턴 동안 기절하며, 바로 주 무기를 휘둘러 %d%% 의 무기 피해를 줄 수 있습니다.
		기절 확률은 정확도 능력치의 영향을 받아 증가합니다.]])
		:format(100 * self:combatTalentWeaponDamage(t, 0.7, 1.5),
		2 + self:getTalentLevel(t),
		100 * self:combatTalentWeaponDamage(t, 0.7, 1.5))
	end,
}

newTalent{
	name = "Flurry",
	kr_name = "질풍",
	type = {"technique/dualweapon-attack", 2},
	points = 5,
	random_ego = "attack",
	cooldown = 12,
	stamina = 15,
	require = techs_dex_req2,
	requires_target = true,
	tactical = { ATTACK = { weapon = 4 } },
	on_pre_use = function(self, t, silent) if not self:hasDualWeapon() then if not silent then game.logPlayer(self, "이 기술을 사용하려면 쌍수 무장을 해야 합니다.") end return false end return true end,
	action = function(self, t)
		local weapon, offweapon = self:hasDualWeapon()
		if not weapon then
			game.logPlayer(self, "쌍수 무장을 하지 않으면 질풍을 사용할 수 없습니다!")
			return nil
		end

		local tg = {type="hit", range=self:getTalentRange(t)}
		local x, y, target = self:getTarget(tg)
		if not x or not y or not target then return nil end
		if core.fov.distance(self.x, self.y, x, y) > 1 then return nil end
		self:attackTarget(target, nil, self:combatTalentWeaponDamage(t, 0.4, 1.0), true)
		self:attackTarget(target, nil, self:combatTalentWeaponDamage(t, 0.4, 1.0), true)
		self:attackTarget(target, nil, self:combatTalentWeaponDamage(t, 0.4, 1.0), true)

		return true
	end,
	info = function(self, t)
		return ([[질풍과 같은 속도로, 대상을 양손의 무기로 각각 3 번씩 공격합니다. 각 공격마다 %d%% 의 무기 피해를 줍니다.]]):format(100 * self:combatTalentWeaponDamage(t, 0.4, 1.0))
	end,
}

newTalent{
	name = "Sweep",
	kr_name = "휩쓸기",
	type = {"technique/dualweapon-attack", 3},
	points = 5,
	random_ego = "attack",
	cooldown = 8,
	stamina = 30,
	require = techs_dex_req3,
	requires_target = true,
	tactical = { ATTACKAREA = { weapon = 1, cut = 1 } },
	on_pre_use = function(self, t, silent) if not self:hasDualWeapon() then if not silent then game.logPlayer(self, "이 기술을 사용하려면 쌍수 무장을 해야 합니다.") end return false end return true end,
	action = function(self, t)
		local weapon, offweapon = self:hasDualWeapon()
		if not weapon then
			game.logPlayer(self, "쌍수 무장을 하지 않으면 휩쓸기를 사용할 수 없습니다!")
			return nil
		end

		local tg = {type="hit", range=self:getTalentRange(t)}
		local x, y, target = self:getTarget(tg)
		if not x or not y or not target then return nil end
		if core.fov.distance(self.x, self.y, x, y) > 1 then return nil end

		local dir = util.getDir(x, y, self.x, self.y)
		if dir == 5 then return nil end
		local lx, ly = util.coordAddDir(self.x, self.y, util.dirSides(dir, self.x, self.y).left)
		local rx, ry = util.coordAddDir(self.x, self.y, util.dirSides(dir, self.x, self.y).right)
		local lt, rt = game.level.map(lx, ly, Map.ACTOR), game.level.map(rx, ry, Map.ACTOR)

		local hit
		hit = self:attackTarget(target, nil, self:combatTalentWeaponDamage(t, 1, 1.7), true)
		if hit and target:canBe("cut") then target:setEffect(target.EFF_CUT, 3 + self:getTalentLevel(t), {power=self:getDex() * 0.5, src=self}) end

		if lt then
			hit = self:attackTarget(lt, nil, self:combatTalentWeaponDamage(t, 1, 1.7), true)
			if hit and lt:canBe("cut") then lt:setEffect(lt.EFF_CUT, 3 + self:getTalentLevel(t), {power=self:getDex() * 0.5, src=self}) end
		end

		if rt then
			hit = self:attackTarget(rt, nil, self:combatTalentWeaponDamage(t, 1, 1.7), true)
			if hit and rt:canBe("cut") then rt:setEffect(rt.EFF_CUT, 3 + self:getTalentLevel(t), {power=self:getDex() * 0.5, src=self}) end
		end
		print(x,y,target)
		print(lx,ly,lt)
		print(rx,ry,rt)

		return true
	end,
	info = function(self, t)
		return ([[대상과 근처에 있는 적들에게 양손의 무기로 각각 %d%% 의 무기 피해를 주고, 매 턴마다 %d 의 피해를 총 %d 턴 동안 주는 출혈 상태를 일으킵니다.]]):
		format(100 * self:combatTalentWeaponDamage(t, 1, 1.7), self:getDex() * 0.5, 3 + self:getTalentLevel(t))
	end,
}

newTalent{
	name = "Whirlwind",
	kr_name = "회오리",
	type = {"technique/dualweapon-attack", 4},
	points = 5,
	random_ego = "attack",
	cooldown = 8,
	stamina = 30,
	require = techs_dex_req4,
	tactical = { ATTACKAREA = { weapon = 2 } },
	range = 0,
	radius = 1,
	target = function(self, t)
		return {type="ball", radius=self:getTalentRadius(t), range=self:getTalentRange(t)}
	end,
	on_pre_use = function(self, t, silent) if not self:hasDualWeapon() then if not silent then game.logPlayer(self, "이 기술을 사용하려면 쌍수 무장을 해야 합니다.") end return false end return true end,
	action = function(self, t)
		local weapon, offweapon = self:hasDualWeapon()
		if not weapon then
			game.logPlayer(self, "쌍수 무장을 하지 않으면 회오리를 사용할 수 없습니다!")
			return nil
		end

		local tg = self:getTalentTarget(t)
		self:project(tg, self.x, self.y, function(px, py, tg, self)
			local target = game.level.map(px, py, Map.ACTOR)
			if target and target ~= self then
				self:attackTarget(target, nil, self:combatTalentWeaponDamage(t, 1.2, 1.9), true)
			end
		end)

		return true
	end,
	info = function(self, t)
		return ([[한 바퀴 회전하여, 근접한 주변의 적들에게 양손의 무기로 각각 %d%% 의 무기 피해를 줍니다.]]):format(100 * self:combatTalentWeaponDamage(t, 1.2, 1.9))
	end,
}

