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

require "engine.krtrUtils"

-- The basic stuff used to damage a grid
setDefaultProjector(function(src, x, y, type, dam, tmp, no_martyr)
	if not game.level.map:isBound(x, y) then return 0 end

	local add_dam = 0
	if src:attr("all_damage_convert") and src.all_damage_convert ~= type then
		local ndam = dam * src.all_damage_convert_percent / 100
		dam = dam - ndam
		local nt = src.all_damage_convert
		src.all_damage_convert = nil
		add_dam = DamageType:get(nt).projector(src, x, y, nt, ndam, tmp, no_martyr)
		src.all_damage_convert = nt
		if dam <= 0 then return add_dam end
	end

	if src:attr("elemental_mastery") then
		local ndam = dam * src.elemental_mastery
		local old = src.elemental_mastery
		src.elemental_mastery = nil
		dam = 0
		dam = dam + DamageType:get(DamageType.FIRE).projector(src, x, y, DamageType.FIRE, ndam, tmp, no_martyr)
		dam = dam + DamageType:get(DamageType.COLD).projector(src, x, y, DamageType.COLD, ndam, tmp, no_martyr)
		dam = dam + DamageType:get(DamageType.LIGHTNING).projector(src, x, y, DamageType.LIGHTNING, ndam, tmp, no_martyr)
		dam = dam + DamageType:get(DamageType.ARCANE).projector(src, x, y, DamageType.ARCANE, ndam, tmp, no_martyr)
		src.elemental_mastery = old
		return dam
	end
	
	if src:attr("twilight_mastery") then
		local ndam = dam * src.twilight_mastery
		local old = src.twilight_mastery
		src.twilight_mastery = nil
		dam = 0
		dam = dam + DamageType:get(DamageType.LIGHT).projector(src, x, y, DamageType.LIGHT, ndam, tmp, no_martyr)
		dam = dam + DamageType:get(DamageType.DARKNESS).projector(src, x, y, DamageType.DARKNESS, ndam, tmp, no_martyr)
		src.twilight_mastery = old
		return dam
	end

	local terrain = game.level.map(x, y, Map.TERRAIN)
	if terrain then terrain:check("damage_project", src, x, y, type, dam) end

	local target = game.level.map(x, y, Map.ACTOR)
	if target then
		local rsrc = src.resolveSource and src:resolveSource() or src
		local rtarget = target.resolveSource and target:resolveSource() or target

		print("[PROJECTOR] starting dam", dam)

		if src.turn_procs and src.turn_procs.is_crit and target:attr("ignore_direct_crits") and rng.percent(target:attr("ignore_direct_crits")) then
			dam = dam / src.turn_procs.crit_power
			print("[PROJECTOR] crit power reduce dam", dam)
			game.logSeen(target, "%s 치명타 피해를 저항했습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
		elseif src.turn_procs and src.turn_procs.is_crit and src.turn_procs.shadowstrike_crit and src.x then
			local d = core.fov.distance(src.x, src.y, x, y)
			if d > 3 then
				local reduc = math.scale(d, 3, 10, 0, 1)
				dam = dam * (src.turn_procs.crit_power - reduc * src.turn_procs.shadowstrike_crit) / src.turn_procs.crit_power
				print("[PROJECTOR] shadowstrike crit power reduce dam on range", dam, d, reduc, "::", src.turn_procs.crit_power, "=>", src.turn_procs.crit_power - reduc * src.turn_procs.shadowstrike_crit)
			end
		end

		local hd = {"DamageProjector:base", src=src, x=x, y=y, type=type, dam=dam, tmp=tmp, no_martyr=no_martyr}
		if src:triggerHook(hd) then dam = hd.dam if hd.stopped then return hd.stopped end end

		-- Difficulty settings
		if game.difficulty == game.DIFFICULTY_EASY and rtarget.player then
			dam = dam * 0.7
		end
		print("[PROJECTOR] after difficulty dam", dam)
		
		if src.__global_accuracy_damage_bonus then
			dam = dam * src.__global_accuracy_damage_bonus
			print("[PROJECTOR] after staff accuracy damage bonus", dam)
		end

		-- Daze
		if src:attr("dazed") then
			dam = dam * 0.5
		end

		-- Preemptive shielding
		if target.isTalentActive and target:isTalentActive(target.T_PREMONITION) then
			local t = target:getTalentFromId(target.T_PREMONITION)
			t.on_damage(target, t, type)
		end

		local lastdam = dam
		-- Item-granted damage ward talent
		if target:hasEffect(target.EFF_WARD) then
			local e = target.tempeffect_def[target.EFF_WARD]
			dam = e.absorb(type, dam, target.tmp[target.EFF_WARD], target, src)
			if dam ~= lastdam then
				game:delayedLogDamage(src, target, 0, ("%s(보호로 인해 %d 피해 감소)#LAST#"):format(DamageType:get(type).text_color or "#aaaaaa#", lastdam-dam), false) 
			end
		end

		-- Block talent from shields
		if dam > 0 and target:attr("block") then
			local e = target.tempeffect_def[target.EFF_BLOCKING]
			lastdam = dam
			dam = e.do_block(type, dam, target.tmp[target.EFF_BLOCKING], target, src)
			if lastdam - dam > 0 then game:delayedLogDamage(src, target, 0, ("%s(방어로 인해 %d 피해 감소)#LAST#"):format(DamageType:get(type).text_color or "#aaaaaa#", lastdam-dam), false) end 
		end
		if dam > 0 and target.isTalentActive and target:isTalentActive(target.T_FORGE_SHIELD) then
			local t = target:getTalentFromId(target.T_FORGE_SHIELD)
			lastdam = dam
			dam = t.doForgeShield(type, dam, t, target, src)
			if lastdam - dam > 0 then game:delayedLogDamage(src, target, 0, ("%s(방어로 인해 %d 피해 감소)#LAST#"):format(DamageType:get(type).text_color or "#aaaaaa#", lastdam-dam), false) end 
		end

		-- Increases damage
		local mind_linked = false
		if src.inc_damage then
			local inc
			if src.combatGetDamageIncrease then inc = src:combatGetDamageIncrease(type)
			else inc = (src.inc_damage.all or 0) + (src.inc_damage[type] or 0) end
			if src.getVim and src:attr("demonblood_dam") then inc = inc + ((src.demonblood_dam or 0) * (src:getVim() or 0)) end

			-- Increases damage for the entity type (Demon, Undead, etc)
			if target.type and src and src.inc_damage_actor_type then
				local increase = 0
				for k, v in pairs(src.inc_damage_actor_type) do
					if target:checkClassification(tostring(k)) then increase = math.max(increase, v) end
				end
				if increase and increase~= 0 then
					print("[PROJECTOR] before inc_damage_actor_type", dam + (dam * inc / 100))
					inc = inc + increase
					print("[PROJECTOR] after inc_damage_actor_type", dam + (dam * inc / 100))
				end
			end

			-- Increases damage to sleeping targets
			if target:attr("sleep") and src.attr and src:attr("night_terror") then
				inc = inc + src:attr("night_terror")
				print("[PROJECTOR] after night_terror", dam + (dam * inc / 100))
			end
			-- Increases damage to targets with Insomnia
			if src.attr and src:attr("lucid_dreamer") and target:hasEffect(target.EFF_INSOMNIA) then
				inc = inc + src:attr("lucid_dreamer")
				print("[PROJECTOR] after lucid_dreamer", dam + (dam * inc / 100))
			end
			-- Mind Link
			if type == DamageType.MIND and target:hasEffect(target.EFF_MIND_LINK_TARGET) then
				local eff = target:hasEffect(target.EFF_MIND_LINK_TARGET)
				if eff.src == src or eff.src == src.summoner then
					mind_linked = true
					inc = inc + eff.power
					print("[PROJECTOR] after mind_link", dam + (dam * inc / 100))
				end
			end

			dam = dam + (dam * inc / 100)
		end

		-- Rigor mortis
		if src.necrotic_minion and target:attr("inc_necrotic_minions") then
			dam = dam + dam * target:attr("inc_necrotic_minions") / 100
			print("[PROJECTOR] after necrotic increase dam", dam)
		end

		-- Blast the iceblock
		if src.attr and src:attr("encased_in_ice") then
			local eff = src:hasEffect(src.EFF_FROZEN)
			eff.hp = eff.hp - dam
			local srcname = src.x and src.y and game.level.map.seens(src.x, src.y) and (src.kr_name or src.name):capitalize() or "무엇인가"
			if eff.hp < 0 and not eff.begone then
				game.logSeen(src, "%s 얼음덩어리를 박살냈습니다.", srcname:capitalize():addJosa("가"))
				game:onTickEnd(function() src:removeEffect(src.EFF_FROZEN) end)
				eff.begone = game.turn
			else
				local dtn = DamageType:get(type).kr_name or DamageType:get(type).name --@ 다음줄 사용 - 너무 길어져서 변수로 뺌 
				game:delayedLogDamage(src, eff.ice, dam, ("%s%d %s#LAST#"):format(DamageType:get(type).text_color or "#aaaaaa#", math.ceil(dam), dtn))
				if eff.begone and eff.begone < game.turn and eff.hp < 0 then
					game.logSeen(src, "%s 얼음덩어리를 박살냈습니다.", srcname:capitalize():addJosa("가"))
					src:removeEffect(src.EFF_FROZEN)
				end
			end
			return 0 + add_dam
		end

		-- dark vision increases damage done in creeping dark
		if src and src ~= target and game.level.map:checkAllEntities(x, y, "creepingDark") then
			local dark = game.level.map:checkAllEntities(x, y, "creepingDark")
			if dark.summoner == src and dark.damageIncrease > 0 and not dark.projecting then
				local source = src.__project_source or src
				dam = dam + (dam * dark.damageIncrease / 100)
				game:delayedLogMessage(source, target, "dark_strike"..(source.uid or ""), "#Source1# 어둠 속에서 #Target3# 공격했습니다 (피해 %+d%%%%%%%%).", dark.damageIncrease) -- resolve %% 3 levels deep
			end
		end
		lastdam = dam
		-- Static reduce damage for psionic kinetic shield
		if target.isTalentActive and target:isTalentActive(target.T_KINETIC_SHIELD) then
			local t = target:getTalentFromId(target.T_KINETIC_SHIELD)
			dam = t.ks_on_damage(target, t, type, dam)
		end
		-- Static reduce damage for psionic spiked kinetic shield
		if target:attr("kinspike_shield") then
			local t = target:getTalentFromId(target.T_KINETIC_SHIELD)
			dam = t.kss_on_damage(target, t, type, dam)
		end
		-- Static reduce damage for psionic thermal shield
		if target.isTalentActive and target:isTalentActive(target.T_THERMAL_SHIELD) then
			local t = target:getTalentFromId(target.T_THERMAL_SHIELD)
			dam = t.ts_on_damage(target, t, type, dam)
		end
		-- Static reduce damage for psionic spiked thermal shield
		if target:attr("thermspike_shield") then
			local t = target:getTalentFromId(target.T_THERMAL_SHIELD)
			dam = t.tss_on_damage(target, t, type, dam)
		end
		-- Static reduce damage for psionic charged shield
		if target.isTalentActive and target:isTalentActive(target.T_CHARGED_SHIELD) then
			local t = target:getTalentFromId(target.T_CHARGED_SHIELD)
			dam = t.cs_on_damage(target, t, type, dam)
		end
		-- Static reduce damage for psionic spiked charged shield
		if target:attr("chargespike_shield") then
			local t = target:getTalentFromId(target.T_CHARGED_SHIELD)
			dam = t.css_on_damage(target, t, type, dam)
		end
		if dam ~= lastdam then
			game:delayedLogDamage(src, target, 0, ("%s(정신 보호막으로 인해 피해 %d 감소)#LAST#"):format(DamageType:get(type).text_color or "#aaaaaa#", lastdam-dam), false) 
		end
		
		--target.T_STONE_FORTRESS could be checked/applied here (ReduceDamage function in Dwarven Fortress talent)

		-- Damage Smearing
		if dam > 0 and type ~= DamageType.TEMPORAL and target:hasEffect(target.EFF_DAMAGE_SMEARING) then
			local smear = dam
			local type = DamageType.TEMPORAL
			target:setEffect(target.EFF_SMEARED, 6, {src=src, power=smear/6, no_ct_effect=true})
			game:delayedLogDamage(src, target, 0, ("%s(피해 분산으로 인해 피해 %d 감소)#LAST#"):format(DamageType:get(type).text_color or "#aaaaaa#", dam), false) 
			dam = 0
		end

		-- affinity healing, we store it to apply it after damage is resolved
		local affinity_heal = 0
		if target.damage_affinity then
			affinity_heal = math.max(0, dam * ((target.damage_affinity.all or 0) + (target.damage_affinity[type] or 0)) / 100)
		end

		-- reduce by resistance to entity type (Demon, Undead, etc)
		-- Summoned, Unnatural, Unliving still go into this table, we just parse them differently in checkClassification
		if target.resists_actor_type and src and src.type then
			local res = 0

			for k, v in pairs(target.resists_actor_type) do
				if src:checkClassification(tostring(k)) then res = math.max(res, v) end
			end

			res = math.min(res, target.resists_cap_actor_type or 90)

			if res ~= 0 then
				print("[PROJECTOR] before entity", src.type, "resists dam", dam)
				if res >= 100 then dam = 0
				elseif res <= -100 then dam = dam * 2
				else dam = dam * ((100 - res) / 100)
				end
				print("[PROJECTOR] after entity", src.type, "resists dam", dam)
			end
		end

		-- Reduce damage with resistance
		if target.resists then
			local pen = 0
			if src.resists_pen then pen = (src.resists_pen.all or 0) + (src.resists_pen[type] or 0) end
			local dominated = target:hasEffect(target.EFF_DOMINATED)
			if dominated and dominated.src == src then pen = pen + (dominated.resistPenetration or 0) end
			if target:attr("sleep") and src.attr and src:attr("night_terror") then pen = pen + src:attr("night_terror") end
			local res = target:combatGetResist(type)
			pen = util.bound(pen, 0, 100)
			if res > 0 then	res = res * (100 - pen) / 100 end
			print("[PROJECTOR] res", res, (100 - res) / 100, " on dam", dam)
			if res >= 100 then dam = 0
			elseif res <= -100 then dam = dam * 2
			else dam = dam * ((100 - res) / 100)
			end
		end
		print("[PROJECTOR] after resists dam", dam)

		-- Reduce damage with resistance against self
		if src == target and target.resists_self then
			local res = (target.resists_self[type] or 0) + (target.resists_self.all or 0)
			print("[PROJECTOR] res", res, (100 - res) / 100, " on dam", dam)
			if res >= 100 then dam = 0
			elseif res <= -100 then dam = dam * 2
			else dam = dam * ((100 - res) / 100)
			end
			print("[PROJECTOR] after self-resists dam", dam)
		end

		--Vim based defence
		if target:attr("demonblood_def") and target.getVim then
			local demon_block = math.min(dam*0.5,target.demonblood_def*(target:getVim() or 0))
			dam= dam - demon_block
			target:incVim((-demon_block)/20)
		end

		-- Static reduce damage
		if dam > 0 and target.isTalentActive and target:isTalentActive(target.T_ANTIMAGIC_SHIELD) then
			local t = target:getTalentFromId(target.T_ANTIMAGIC_SHIELD)
			lastdam = dam
			dam = t.on_damage(target, t, type, dam)
			if lastdam - dam  > 0 then game:delayedLogDamage(src, target, 0, ("%s(반마법 보호막으로 인해 %d 피해 감소)#LAST#"):format(DamageType:get(type).text_color or "#aaaaaa#", lastdam - dam), false) end 
		end

		if dam > 0 and target.isTalentActive and target:isTalentActive(target.T_ENERGY_DECOMPOSITION) then
			local t = target:getTalentFromId(target.T_ENERGY_DECOMPOSITION)
			lastdam = dam
			dam = t.on_damage(target, t, type, dam)
			if lastdam - dam  > 0 then game:delayedLogDamage(src, target, 0, ("%s(에너지 분해로 인해 %d 피해 감소)#LAST#"):format(DamageType:get(type).text_color or "#aaaaaa#", lastdam - dam), false) end 
		end

		-- Flat damage reduction ("armour")
		if dam > 0 and target.flat_damage_armor then
			local dec = math.min(dam, (target.flat_damage_armor.all or 0) + (target.flat_damage_armor[type] or 0))
			if dec > 0 then game:delayedLogDamage(src, target, 0, ("%s(방어구로 인해 %d 피해 감소)#LAST#"):format(DamageType:get(type).text_color or "#aaaaaa#", dec), false) end 
			dam = math.max(0, dam - dec)
			print("[PROJECTOR] after flat damage armor", dam)
		end

		-- roll with it damage reduction
		if type == DamageType.PHYSICAL and target:knowTalent(target.T_ROLL_WITH_IT) and not target:attr("never_move") then
			dam = dam * target:callTalent(target.T_ROLL_WITH_IT, "getMult")
			print("[PROJECTOR] after Roll With It dam", dam)
		end

		if src:attr("stunned") then
			dam = dam * 0.4
			print("[PROJECTOR] stunned dam", dam)
		end
		if src:attr("invisible_damage_penalty") then
			dam = dam * util.bound(1 - (src.invisible_damage_penalty / (src.invisible_damage_penalty_divisor or 1)), 0, 1)
			print("[PROJECTOR] invisible dam", dam)
		end
		if src:attr("numbed") then
			dam = dam - dam * src:attr("numbed") / 100
			print("[PROJECTOR] numbed dam", dam)
		end

		-- Curse of Misfortune: Unfortunate End (chance to increase damage enough to kill)
		if src and src.hasEffect and src:hasEffect(src.EFF_CURSE_OF_MISFORTUNE) then
			local eff = src:hasEffect(src.EFF_CURSE_OF_MISFORTUNE)
			local def = src.tempeffect_def[src.EFF_CURSE_OF_MISFORTUNE]
			dam = def.doUnfortunateEnd(src, eff, target, dam)
		end

		if src:attr("crushing_blow") and (dam * (1.25 + (src.combat_critical_power or 0)/200)) > target.life then
			dam = dam * (1.25 + (src.combat_critical_power or 0)/200)
			game.logPlayer(src, "당신은 완파 공격으로 상대방을 끝장냈습니다!")
		end

		if target:attr("resist_unseen") and not target:canSee(src) then
			dam = dam * (1 - math.min(target.resist_unseen,100)/100)
		end

		-- Sanctuary: reduces damage if it comes from outside of Gloom
		if target.isTalentActive and target:isTalentActive(target.T_GLOOM) and target:knowTalent(target.T_SANCTUARY) then
			if tmp and tmp.sanctuaryDamageChange then
				-- projectile was targeted outside of gloom
				dam = dam * (100 + tmp.sanctuaryDamageChange) / 100
				print("[PROJECTOR] Sanctuary (projectile) dam", dam)
			elseif src and src.x and src.y then
				-- assume instantaneous projection and check range to source
				local t = target:getTalentFromId(target.T_GLOOM)
				if core.fov.distance(target.x, target.y, src.x, src.y) > target:getTalentRange(t) then
					t = target:getTalentFromId(target.T_SANCTUARY)
					dam = dam * (100 + t.getDamageChange(target, t)) / 100
					print("[PROJECTOR] Sanctuary (source) dam", dam)
				end
			end
		end

		-- Chant of Fortress, reduces damage from attackers over range 2
		if target.isTalentActive and target:isTalentActive(target.T_CHANT_OF_FORTRESS) and target:knowTalent(target.T_CHANT_OF_FORTRESS) then
			if src and src.x and src.y then
				-- assume instantaneous projection and check range to source
				local t = target:getTalentFromId(target.T_CHANT_OF_FORTRESS)
				if core.fov.distance(target.x, target.y, src.x, src.y) > 2 then
					t = target:getTalentFromId(target.T_CHANT_OF_FORTRESS)
					dam = dam * (100 + t.getDamageChange(target, t)) / 100
					print("[PROJECTOR] Chant of Fortress (source) dam", dam)
				end
			end
		end

		-- Psychic Projection
		if src.attr and src:attr("is_psychic_projection") and not game.zone.is_dream_scape then
			if (target.subtype and target.subtype == "ghost") or mind_linked then
				dam = dam
			else
				dam = 0
			end
		end

		if src.necrotic_minion_be_nice and src.summoner == target then 
			dam = dam * (1 - src.necrotic_minion_be_nice)
		end

		print("[PROJECTOR] final dam after static checks", dam)

		local hd = {"DamageProjector:final", src=src, x=x, y=y, type=type, dam=dam, tmp=tmp, no_martyr=no_martyr}
		if src:triggerHook(hd) then dam = hd.dam if hd.stopped then return hd.stopped end end
		if target.fireTalentCheck then
			local ret = target:fireTalentCheck("callbackOnTakeDamage", src, x, y, type, dam, tmp, no_martyr)
			if ret then
				if ret.dam then dam = ret.dam end
				if ret.stopped then return ret.stopped end
			end
		end

		print("[PROJECTOR] final dam after hooks and callbacks", dam)


		local source_talent = src.__projecting_for and src.__projecting_for.project_type and (src.__projecting_for.project_type.talent_id or src.__projecting_for.project_type.talent) and src.getTalentFromId and src:getTalentFromId(src.__projecting_for.project_type.talent or src.__projecting_for.project_type.talent_id)
		local dead
		dead, dam = target:takeHit(dam, src, {damtype=type, source_talent=source_talent})

		-- Log damage for later
		if not DamageType:get(type).hideMessage then
			local visible, srcSeen, tgtSeen = game:logVisible(src, target)
				if visible then -- don't log damage that the player doesn't know about
					local source = src.__project_source or src
				local dtn = DamageType:get(type).kr_name or DamageType:get(type).name --@ 두줄뒤와 네줄뒤 사용 : 너무 길어져서 변수로 뺌
				if src.turn_procs and src.turn_procs.is_crit then
					game:delayedLogDamage(source, target, dam, ("#{bold}#%s%d %s#{normal}##LAST#"):format(DamageType:get(type).text_color or "#aaaaaa#", dam, dtn), true)
				else
					game:delayedLogDamage(source, target, dam, ("%s%d %s#LAST#"):format(DamageType:get(type).text_color or "#aaaaaa#", dam, dtn), false)
				end
			end
		end

		if dam > 0 and src.attr and src:attr("martyrdom") and not no_martyr then
			game:delayedLogMessage(src, target, "martyrdom", "#CRIMSON##Source#의 피해가 자기 자신에게도 고난을 가합니다!") 
			DamageType.defaultProjector(target, src.x, src.y, type, dam * src.martyrdom / 100, tmp, true)
		end
		if target.attr and target:attr("reflect_damage") and not no_martyr and src.x and src.y then
			game:delayedLogMessage(target, src, "reflect_damage"..(src.uid or ""), "#CRIMSON##Source#의 피해가 #Target#에게 반사됩니다!") 
			DamageType.defaultProjector(target, src.x, src.y, type, dam * target.reflect_damage / 100, tmp, true)
		end

		if target.knowTalent and target:knowTalent(target.T_RESOLVE) then local t = target:getTalentFromId(target.T_RESOLVE) t.on_absorb(target, t, type, dam) end

		if target ~= src and target.attr and target:attr("damage_resonance") and not target:hasEffect(target.EFF_RESONANCE) then
			target:setEffect(target.EFF_RESONANCE, 5, {damtype=type, dam=target:attr("damage_resonance")})
		end

		if not target.dead and dam > 0 and type == DamageType.MIND and src and src.knowTalent and src:knowTalent(src.T_MADNESS) then
			local t = src:getTalentFromId(src.T_MADNESS)
			t.doMadness(target, t, src)
		end

		-- Curse of Nightmares: Nightmare
		if not target.dead and dam > 0 and src and target.hasEffect and target:hasEffect(src.EFF_CURSE_OF_NIGHTMARES) then
			local eff = target:hasEffect(target.EFF_CURSE_OF_NIGHTMARES)
			eff.isHit = true -- handle at the end of the turn
		end

		if not target.dead and dam > 0 and target:attr("elemental_harmony") and not target:hasEffect(target.EFF_ELEMENTAL_HARMONY) then
			if type == DamageType.FIRE or type == DamageType.COLD or type == DamageType.LIGHTNING or type == DamageType.ACID or type == DamageType.NATURE then
				target:setEffect(target.EFF_ELEMENTAL_HARMONY, target:callTalent(target.T_ELEMENTAL_HARMONY, "duration"), {power=target:attr("elemental_harmony"), type=type, no_ct_effect=true})
			end
		end

		if not target.dead and dam > 0 and src.knowTalent and src:knowTalent(src.T_ENDLESS_WOES) then
			src:triggerTalent(src.T_ENDLESS_WOES, nil, target, type, dam)
		end

		-- damage affinity healing
		if not target.dead and affinity_heal > 0 then
			target:heal(affinity_heal, src)
			local dtn = DamageType:get(type).kr_name or DamageType:get(type).name --@ 다음줄 사용 : 너무 길어져서 변수로 뺌
			game:delayedLogMessage(target, nil, "Affinity"..type, "#Source1# "..(DamageType:get(type).text_color or "#aaaaaa#")..dtn.."#LAST# 피해로부터 #LIGHT_GREEN# 치료#LAST#되었습니다!")
		end

		if dam > 0 and src.damage_log and src.damage_log.weapon then
			src.damage_log[type] = (src.damage_log[type] or 0) + dam
			if src.turn_procs and src.turn_procs.weapon_type then
				src.damage_log.weapon[src.turn_procs.weapon_type.kind] = (src.damage_log.weapon[src.turn_procs.weapon_type.kind] or 0) + dam
				src.damage_log.weapon[src.turn_procs.weapon_type.mode] = (src.damage_log.weapon[src.turn_procs.weapon_type.mode] or 0) + dam
			end
		end

		if dam > 0 and target.damage_intake_log and target.damage_intake_log.weapon then
			target.damage_intake_log[type] = (target.damage_intake_log[type] or 0) + dam
			if src.turn_procs and src.turn_procs.weapon_type then
				target.damage_intake_log.weapon[src.turn_procs.weapon_type.kind] = (target.damage_intake_log.weapon[src.turn_procs.weapon_type.kind] or 0) + dam
				target.damage_intake_log.weapon[src.turn_procs.weapon_type.mode] = (target.damage_intake_log.weapon[src.turn_procs.weapon_type.mode] or 0) + dam
			end
		end

		if dam > 0 and source_talent then
			local t = source_talent

			if src:attr("spellshock_on_damage") and target:checkHit(src:combatSpellpower(), target:combatPhysicalResist(), 0, 95, 15) and not target:hasEffect(target.EFF_SPELLSHOCKED) then
				target:crossTierEffect(target.EFF_SPELLSHOCKED, src:combatSpellpower())
			end

			if src.__projecting_for then
				if src.talent_on_spell and next(src.talent_on_spell) and t.is_spell and not src.turn_procs.spell_talent then
					for id, d in pairs(src.talent_on_spell) do
						if rng.percent(d.chance) and t.id ~= d.talent then
							src.turn_procs.spell_talent = true
							local old = src.__projecting_for
							src:forceUseTalent(d.talent, {ignore_cd=true, ignore_energy=true, force_target=target, force_level=d.level, ignore_ressources=true})
							src.__projecting_for = old
						end
					end
				end

				if src.talent_on_wild_gift and next(src.talent_on_wild_gift) and t.is_nature and not src.turn_procs.wild_gift_talent then
					for id, d in pairs(src.talent_on_wild_gift) do
						if rng.percent(d.chance) and t.id ~= d.talent then
							src.turn_procs.wild_gift_talent = true
							local old = src.__projecting_for
							src:forceUseTalent(d.talent, {ignore_cd=true, ignore_energy=true, force_target=target, force_level=d.level, ignore_ressources=true})
							src.__projecting_for = old
						end
					end
				end

				if src.talent_on_mind and next(src.talent_on_mind) and t.is_mind and not src.turn_procs.mind_talent then
					for id, d in pairs(src.talent_on_mind) do
						if rng.percent(d.chance) and t.id ~= d.talent then
							src.turn_procs.mind_talent = true
							local old = src.__projecting_for
							src:forceUseTalent(d.talent, {ignore_cd=true, ignore_energy=true, force_target=target, force_level=d.level, ignore_ressources=true})
							src.__projecting_for = old
						end
					end
				end

				if not target.dead and (t.is_spell or t.is_mind) and not src.turn_procs.meteoric_crash and src.knowTalent and src:knowTalent(src.T_METEORIC_CRASH) then
					src.turn_procs.meteoric_crash = true
					src:triggerTalent(src.T_METEORIC_CRASH, nil, target)
				end

				if not target.dead and t.is_spell and target.knowTalent then
					if target:knowTalent(target.T_SPELL_FEEDBACK) then
						target:triggerTalent(target.T_SPELL_FEEDBACK, nil, src, t)
					end
					if target:knowTalent(target.T_NATURE_S_DEFIANCE) then
						target:triggerTalent(target.T_NATURE_S_DEFIANCE, nil, src, t)
					end
				end
				if t.is_spell and src.knowTalent and src:knowTalent(src.T_BORN_INTO_MAGIC) then
					src:triggerTalent(target.T_BORN_INTO_MAGIC, nil, type)
				end
				
				if not target.dead and src.isTalentActive and src:isTalentActive(src.T_UNSTOPPABLE_NATURE) and t.is_nature and not src.turn_procs.unstoppable_nature then
					src:callTalent(src.T_UNSTOPPABLE_NATURE, "freespit", target)
					src.turn_procs.unstoppable_nature = true
				end
			end
		end

		if src.turn_procs and src.turn_procs.is_crit then
			if src.knowTalent and src:knowTalent(src.T_ELEMENTAL_SURGE) then
				src:triggerTalent(src.T_ELEMENTAL_SURGE, nil, target, type, dam)
			end

			src.turn_procs.is_crit = nil
		end

		if src.turn_procs and not src.turn_procs.dazing_damage and src.hasEffect and src:hasEffect(src.EFF_DAZING_DAMAGE) then
			if target:canBe("stun") then
				local power = math.max(src:combatSpellpower(), src:combatMindpower(), src:combatPhysicalpower())
				target:setEffect(target.EFF_DAZED, 2, {})
			end
			src:removeEffect(src.EFF_DAZING_DAMAGE)
			src.turn_procs.dazing_damage = true
		end

		if src.turn_procs and not src.turn_procs.blighted_soil and src:attr("blighted_soil") and rng.percent(src:attr("blighted_soil")) then
			local tid = rng.table{src.EFF_ROTTING_DISEASE, src.EFF_DECREPITUDE_DISEASE, src.EFF_DECREPITUDE_DISEASE}
			if not target:hasEffect(tid) then
				local l = game.zone:level_adjust_level(game.level, game.zone, "object")
				local p = math.ceil(4 + l / 2)
				target:setEffect(tid, 8, {str=p, con=p, dex=p, dam=5 + l / 2, src=src})
				src.turn_procs.blighted_soil = true
			end
		end

		return dam + add_dam
	end
	return 0 + add_dam
end)

local function tryDestroy(who, inven, dam, destroy_prop, proof_prop, msg)
	do return end -- Disabled for now
	if not inven then return end

	local reduction = 1

	for i = #inven, 1, -1 do
		local o = inven[i]
		if o[destroy_prop] and not o[proof_prop] then
			for j, test in ipairs(o[destroy_prop]) do
				if dam >= test[1] and rng.percent(test[2] * reduction) then
					game.logPlayer(who, msg, o:getName{do_color=true, no_count=true})
					local obj = who:removeObject(inven, i)
					obj:removed()
					break
				end
			end
		end
	end
end

newDamageType{
	name = "cosmetic", type = "COSMETIC", text_color = "#WHITE#",
	kr_name = "미용",
	projector = function(src, x, y, type, dam)
	end,
	death_message = {"미용 효과로"},
}

newDamageType{
	name = "physical", type = "PHYSICAL",
	kr_name = "물리",
	death_message = {"공격받아", "맞아서", "잘려", "중상을 입어", "할퀴어져", "출혈상으로", "관통되어", "해부되어", "배가 갈라져", "참수되어", "찔려", "꿰뚫려", "사족이 찢겨나가", "찌부러져", "박살나", "부수어져", "쪼개어져", "강타를 맞고", "맞아", "절단되어", "괴롭힘을 당하다가", "꼬치가 되어", "짓이겨져", "난폭하게", "잘게 잘려", "피분수를 뿜으며", "쓰러져", "썰려", "구멍나", "난도질되어", "내장이 꺼내어져"},
}

-- Arcane is basic (usually) unresistable damage
newDamageType{
	name = "arcane", type = "ARCANE", text_color = "#PURPLE#",
	kr_name = "마법",
	antimagic_resolve = true,
	death_message = {"폭발하여", "힘을 빼앗겨", "마나로 찢겨", "마법으로", "내파되어"},
}
-- The elemental damages
newDamageType{
	name = "fire", type = "FIRE", text_color = "#LIGHT_RED#",
	antimagic_resolve = true,
	kr_name = "화염",
	projector = function(src, x, y, type, dam)
		if src.fire_convert_to then
			if src.fire_convert_to[2] >= 100 then
				return DamageType:get(src.fire_convert_to[1]).projector(src, x, y, src.fire_convert_to[1], dam * src.fire_convert_to[2] / 100)
			else
				local old = src.fire_convert_to
				src.fire_convert_to = nil
				dam = DamageType:get(old[1]).projector(src, x, y, old[1], dam * old[2] / 100) + 
				       DamageType:get(type).projector(src, x, y, type, dam * (100 - old[2]) / 100)
				src.fire_convert_to = old
				return dam
			end
		end
		local realdam = DamageType.defaultProjector(src, x, y, type, dam)
		if realdam > 0 then
			local a = game.level.map(x, y, Map.ACTOR)
			if src.player and a and not a.training_dummy then world:gainAchievement("PYROMANCER", src, realdam) end
		end
		return realdam
	end,
	death_message = {"화상으로 인해", "바싹 말라", "불 타", "산화되어", "타올라", "튀겨져", "연소되어", "구워져", "천천히 익어", "익어서"},
}
newDamageType{
	name = "cold", type = "COLD", text_color = "#1133F3#",
	kr_name = "냉기",
	antimagic_resolve = true,
	projector = function(src, x, y, type, dam)
		local realdam = DamageType.defaultProjector(src, x, y, type, dam)
		if realdam > 0 then
			local a = game.level.map(x, y, Map.ACTOR)
			if src.player and a and not a.training_dummy then world:gainAchievement("CRYOMANCER", src, realdam) end
		end
		if realdam > 0 and src:attr("cold_freezes") and rng.percent(src.cold_freezes) then
			DamageType:get(DamageType.FREEZE).projector(src, x, y, DamageType.FREEZE, {dur=2, hp=70+dam*1.5})
		end
		return realdam
	end,
	death_message = {"얼어붙어", "온기를 빼앗겨", "얼음에 갇혀", "차가워져", "얼어붙은 다음 산산조각 나서"},
}
newDamageType{
	name = "lightning", type = "LIGHTNING", text_color = "#ROYAL_BLUE#",
	kr_name = "전기",
	antimagic_resolve = true,
	projector = function(src, x, y, type, dam)
		local realdam = DamageType.defaultProjector(src, x, y, type, dam)
		return realdam
	end,
	death_message = {"감전되어", "전기충격을 받아", "번갯불로", "전류가 흘러", "지져져서", "공격당하여"},
}

-- Acid, few specific interactions currently aside from damage types later derived from this
newDamageType{
	name = "acid", type = "ACID", text_color = "#GREEN#",
	kr_name = "산성",
	antimagic_resolve = true,
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		local realdam = DamageType.defaultProjector(src, x, y, type, dam)
		if realdam > 0 and target and src.knowTalent and src:knowTalent(src.T_NATURAL_ACID) then
			local t = src:getTalentFromId(src.T_NATURAL_ACID)
			src:setEffect(src.EFF_NATURAL_ACID, t.getDuration(src, t), {})
		end
		return realdam
	end,
	death_message = {"용해되어", "부식되어", "끓어올라", "녹아"},
}

-- Nature & Blight: Opposing damage types
newDamageType{
	name = "nature", type = "NATURE", text_color = "#LIGHT_GREEN#",
	kr_name = "자연",
	antimagic_resolve = true,
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		local realdam = DamageType.defaultProjector(src, x, y, type, dam)
		if realdam > 0 and target and src.knowTalent and src:knowTalent(src.T_CORROSIVE_NATURE) then
			local t = src:getTalentFromId(src.T_CORROSIVE_NATURE)
			src:setEffect(src.EFF_CORROSIVE_NATURE, t.getDuration(src, t), {})
		end
		return realdam
	end,
	death_message = {"점액으로 뒤덮혀", "생명력을 빼앗겨", "환경 보호를 위해", "자연의 법칙에 따라"},
}

newDamageType{
	name = "blight", type = "BLIGHT", text_color = "#DARK_GREEN#",
	kr_name = "황폐",
	antimagic_resolve = true,
	projector = function(src, x, y, type, dam, extra)
		local realdam = DamageType.defaultProjector(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		-- Spread diseases if possible
		if realdam > 0 and target and target:attr("diseases_spread_on_blight") and (not extra or not extra.from_disease) then
			src:callTalent(src.T_EPIDEMIC, "do_spread", target, realdam)
		end
		return realdam
	end,
	death_message = {"질병으로", "천연두로", "감염되어", "전염병으로", "유독성 황폐 물질로 쇠약해져", "썩어가며", "더럽혀져"},
}

-- Light damage
newDamageType{
	name = "light", type = "LIGHT", text_color = "#YELLOW#",
	kr_name = "빛",
	antimagic_resolve = true,
	death_message = {"방사능으로", "시들어", "정화되어", "태양열로 구워져", "발작을 일으키며", "햇빛에 타올라"},
}

-- Darkness damage
newDamageType{
	name = "darkness", type = "DARKNESS", text_color = "#GREY#",
	kr_name = "어둠",
	antimagic_resolve = true,
	death_message = {"그림자에 먹혀", "흐릿해지면서", "공허에 삼켜져"},
	projector = function(src, x, y, type, dam, extra)
		local realdam = DamageType.defaultProjector(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		-- Darken
		if realdam > 0 and src:attr("darkness_darkens") then
			game.level.map.lites(x, y, false)
			if src.x and src.y then game.level.map.lites(src.x, src.y, false) end
		end
		return realdam
	end,
}

-- Mind damage
-- Most uses of this have their damage effected by mental save and do not trigger cross tiers, ie, melee items
newDamageType{
	name = "mind", type = "MIND", text_color = "#YELLOW#",
	kr_name = "정신",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		local thought_form
		if target and src and target.summoner and target.summoner == src and target.type and target.type == "thought-form" then thought_form = true end
		if target and not thought_form then
			local mindpower, mentalresist, alwaysHit, crossTierChance
			if _G.type(dam) == "table" then dam, mindpower, mentalresist, alwaysHit, crossTierChance = dam.dam, dam.mindpower, dam.mentalresist, dam.alwaysHit, dam.crossTierChance end
			local hit_power = mindpower or src:combatMindpower()
			if alwaysHit or target:checkHit(hit_power, mentalresist or target:combatMentalResist(), 0, 95, 15) then
				if crossTierChance and rng.percent(crossTierChance) then
					target:crossTierEffect(target.EFF_BRAINLOCKED, src:combatMindpower())
				end
				return DamageType.defaultProjector(src, x, y, type, dam)
			else
				game.logSeen(target, "%s 정신 공격을 저항했습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
				return DamageType.defaultProjector(src, x, y, type, dam / 2)
			end
		end
		return 0
	end,
	death_message = {"불안감으로", "정신적 괴롭힘을 당하여", "정신적 폭행으로"},
}

-- Cold damage+turn energy drain, used exclusively by the Wintertide weapon
-- If you use this for something else make sure to note it has no power check or sanity check on how much turn energy is drained
newDamageType{
	name = "winter", type = "WINTER",
	kr_name = "겨울",
	projector = function(src, x, y, type, dam)
		local srcx, srcy = dam.x, dam.y
		local base = dam
		dam = dam.dam
		if not base.st then
			DamageType:get(DamageType.COLD).projector(src, x, y, DamageType.COLD, dam)
		else
			DamageType:get(base.st).projector(src, x, y, base.st, dam)
		end
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			local energyDrain = (game.energy_to_act * 0.2)
			target.energy.value = target.energy.value - energyDrain
		end
	end,
}

-- Temporal damage
newDamageType{
	name = "temporal", type = "TEMPORAL", text_color = "#LIGHT_STEEL_BLUE#",
	kr_name = "시간",
	antimagic_resolve = true,
	death_message = {"뒤틀린 시간으로", "시간적인 왜곡으로", "모든 시공간으로 분산되어", "괴리적으로", "(아무도 알아채지 못한) 복제된 시간으로 교체되어", "조상이 사라져", "시간 팽창으로"},
}

-- Temporal + Stun
newDamageType{
	name = "temporal stun", type = "TEMPORALSTUN",
	kr_name = "시간의 기절",
	projector = function(src, x, y, type, dam)
		DamageType:get(DamageType.TEMPORAL).projector(src, x, y, DamageType.TEMPORAL, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			if target:canBe("stun") then
				target:setEffect(target.EFF_STUNNED, 4, {apply_power=src:combatSpellpower()})
			else
				game.logSeen(target, "%s 기절하지 않았습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}

-- Lite up the room
newDamageType{
	name = "lite", type = "LITE", text_color = "#YELLOW#",
	kr_name = "조명 반경",
	projector = function(src, x, y, type, dam)
		-- Dont lit magically unlit grids
		local g = game.level.map(x, y, Map.TERRAIN+1)
		if g and g.unlit then
			if g.unlit <= dam then game.level.map:remove(x, y, Map.TERRAIN+1)
			else return end
		end

		game.level.map.lites(x, y, true)
	end,
}

-- Break stealth
newDamageType{
	name = "illumination", type = "BREAK_STEALTH",
	kr_name = "조명",
	projector = function(src, x, y, type, dam)
		-- Dont lit magically unlit grids
		local a = game.level.map(x, y, Map.ACTOR)
		if a then
			a:setEffect(a.EFF_LUMINESCENCE, math.ceil(dam.turns), {power=dam.power, no_ct_effect=true})
		end
	end,
}

-- Silence
newDamageType{
	name = "silence", type = "SILENCE",
	kr_name = "침묵",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			if target:canBe("silence") then
				target:setEffect(target.EFF_SILENCED, math.ceil(dam.dur), {apply_power=dam.power_check or src:combatMindpower() * 0.7})
			else
				game.logSeen(target, "%s 침묵되지 않았습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}

-- Silence
newDamageType{
	name = "arcane silence", type = "ARCANE_SILENCE", text_color = "#PURPLE#",
	kr_name = "마법적 침묵",
	projector = function(src, x, y, type, dam)
		local chance = 100
		if _G.type(dam) == "table" then dam, chance = dam.dam, dam.chance end

		local target = game.level.map(x, y, Map.ACTOR)
		local realdam = DamageType:get(DamageType.ARCANE).projector(src, x, y, DamageType.ARCANE, dam)
		if target then
			if rng.percent(chance) and target:canBe("silence") then
				target:setEffect(target.EFF_SILENCED, 3, {apply_power=src:combatSpellpower()})
			else
				game.logSeen(target, "%s 침묵되지 않았습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
		return realdam
	end,
}

-- Silence
newDamageType{
	name = "silence", type = "RANDOM_SILENCE",
	kr_name = "침묵",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and rng.percent(dam) then
			if target:canBe("silence") then
				target:setEffect(target.EFF_SILENCED, 4, {apply_power=src:combatAttack()*0.7, no_ct_effect=true})
			else
				game.logSeen(target, "%s 침묵되지 않았습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}

-- Blinds
newDamageType{
	name = "blindness", type = "BLIND",
	kr_name = "실명",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			if target:canBe("blind") then
				target:setEffect(target.EFF_BLINDED, math.ceil(dam), {apply_power=src:combatSpellpower()})
			else
				game.logSeen(target, "%s 실명되지 않았습니다", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}
newDamageType{
	name = "blindness", type = "BLINDPHYSICAL",
	kr_name = "실명",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			if target:canBe("blind") then
				target:setEffect(target.EFF_BLINDED, math.ceil(dam), {apply_power=src:combatAttack()})
			else
				game.logSeen(target, "%s 실명되지 않았습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}
newDamageType{
	name = "blinding ink", type = "BLINDING_INK",
	kr_name = "먹물 발사",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			if target:canBe("blind") then
				target:setEffect(target.EFF_BLINDED, math.ceil(dam), {apply_power=src:combatPhysicalpower(), apply_save="combatPhysicalResist"})
			else
				game.logSeen(target, "%s 실명되지 않았습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}
newDamageType{
	name = "blindness", type = "BLINDCUSTOMMIND",
	kr_name = "실명",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			if target:canBe("blind") then
				target:setEffect(target.EFF_BLINDED, math.ceil(dam.turns), {apply_power=dam.power, apply_save="combatMentalResist", no_ct_effect=true})
			else
				game.logSeen(target, "%s 실명되지 않았습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}

-- Lite + Light damage
newDamageType{
	name = "bright light", type = "LITE_LIGHT",
	kr_name = "강렬한 빛",
	projector = function(src, x, y, type, dam)
		DamageType:get(DamageType.LITE).projector(src, x, y, DamageType.LITE, 1)
		return DamageType:get(DamageType.LIGHT).projector(src, x, y, DamageType.LIGHT, dam)
	end,
}

-- Fire damage + DOT
newDamageType{
	name = "fire burn", type = "FIREBURN", text_color = "#LIGHT_RED#",
	kr_name = "지속성 화염",
	projector = function(src, x, y, type, dam)
		local dur = 3
		local perc = 50
		if _G.type(dam) == "table" then dam, dur, perc = dam.dam, dam.dur, (dam.initial or perc) end
		local init_dam = dam * perc / 100
		if init_dam > 0 then DamageType:get(DamageType.FIRE).projector(src, x, y, DamageType.FIRE, init_dam) end
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			-- Set on fire!
			dam = dam - init_dam
			target:setEffect(target.EFF_BURNING, dur, {src=src, power=dam / dur, no_ct_effect=true})
		end
		return init_dam
	end,
}
newDamageType{
	name = "fire burn", type = "GOLEM_FIREBURN",
	kr_name = "지속성 화염",
	projector = function(src, x, y, type, dam)
		local realdam = 0
		local target = game.level.map(x, y, Map.ACTOR)
		if target and target ~= src and target ~= src.summoner then
			realdam = DamageType:get(DamageType.FIREBURN).projector(src, x, y, DamageType.FIREBURN, dam)
		end
		return realdam
	end,
}

-- Darkness + Fire
newDamageType{
	name = "shadowflame", type = "SHADOWFLAME",
	kr_name = "어둠의 불꽃",
	projector = function(src, x, y, type, dam)
		DamageType:get(DamageType.FIRE).projector(src, x, y, DamageType.FIRE, dam / 2)
		DamageType:get(DamageType.DARKNESS).projector(src, x, y, DamageType.DARKNESS, dam / 2)
	end,
}

-- Darkness + Stun
newDamageType{
	name = "darkness", type = "DARKSTUN",
	kr_name = "어둠",
	projector = function(src, x, y, type, dam)
		DamageType:get(DamageType.DARKNESS).projector(src, x, y, DamageType.DARKNESS, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			-- try to stun
			if target:canBe("stun") then
				target:setEffect(target.EFF_STUNNED, 4, {apply_power=src:combatSpellpower()})
			else
				game.logSeen(target, "%s 어둠을 저항했습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}

-- Darkness but not over minions
newDamageType{
	name = "darkness", type = "MINION_DARKNESS",
	kr_name = "어둠",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and (not target.necrotic_minion or target.summoner ~= src) then
			DamageType:get(DamageType.DARKNESS).projector(src, x, y, DamageType.DARKNESS, dam)
		end
	end,
}

-- Fore but not over minions
newDamageType{
	name = "fire", type = "FIRE_FRIENDS",
	kr_name = "화염",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and target.summoner ~= src then
			DamageType:get(DamageType.FIRE).projector(src, x, y, DamageType.FIRE, dam)
		end
	end,
}

-- Cold + Stun
newDamageType{
	name = "cold", type = "COLDSTUN",
	kr_name = "냉기",
	projector = function(src, x, y, type, dam)
		DamageType:get(DamageType.COLD).projector(src, x, y, DamageType.COLD, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			if target:canBe("stun") then
				target:setEffect(target.EFF_STUNNED, 4, {apply_power=src:combatSpellpower()})
			else
				game.logSeen(target, "%s 기절하지 않았습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}

-- Fire DOT + Stun
newDamageType{
	name = "flameshock", type = "FLAMESHOCK",
	kr_name = "화염의 기절",
	projector = function(src, x, y, type, dam)
		if _G.type(dam) == "number" then dam = {dam=dam, dur=4} end
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			-- Set on fire!
			if target:canBe("stun") then
				target:setEffect(target.EFF_BURNING_SHOCK, dam.dur, {src=src, power=dam.dam / dam.dur, apply_power=dam.apply_power or src:combatSpellpower()})
			else
				game.logSeen(target, "%s 타오르는 화염을 저항했습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}

-- Cold damage + freeze chance
newDamageType{
	name = "ice", type = "ICE", text_color = "#1133F3#",
	kr_name = "얼어붙은 냉기",
	projector = function(src, x, y, type, dam)
		local chance = 25
		if _G.type(dam) == "table" then chance, dam = dam.chance, dam.dam end
		local realdam = DamageType:get(DamageType.COLD).projector(src, x, y, DamageType.COLD, dam)
		if rng.percent(chance) then
			DamageType:get(DamageType.FREEZE).projector(src, x, y, DamageType.FREEZE, {dur=2, hp=70+dam*1.5})
		end
		return realdam
	end,
}

-- Cold damage + freeze chance, increased if wet
newDamageType{
	name = "ice storm", type = "ICE_STORM", text_color = "#1133F3#",
	kr_name = "얼음 폭풍",
	projector = function(src, x, y, type, dam)
		local chance = 25

		local target = game.level.map(x, y, Map.ACTOR)
		if target and target:hasEffect(target.EFF_WET) then dam = dam * 1.3 chance = 50 end

		local realdam = DamageType:get(DamageType.COLD).projector(src, x, y, DamageType.COLD, dam)
		if rng.percent(chance) then
			DamageType:get(DamageType.FREEZE).projector(src, x, y, DamageType.FREEZE, {dur=2, hp=70+dam*1.5})
		end
		return realdam
	end,
}

-- Increased cold damage + freeze chance if wet
newDamageType{
	name = "glacial vapour", type = "GLACIAL_VAPOUR", text_color = "#1133F3#",
	kr_name = "차가운 증기",
	projector = function(src, x, y, type, dam)
		local chance = 0
		local target = game.level.map(x, y, Map.ACTOR)
		if target and target:hasEffect(target.EFF_WET) then dam = dam * 1.3 chance = 15 end
		local realdam = DamageType:get(DamageType.COLD).projector(src, x, y, DamageType.COLD, dam)
		if rng.percent(chance) then
			DamageType:get(DamageType.FREEZE).projector(src, x, y, DamageType.FREEZE, {dur=2, hp=70+dam*1.2})
		end
		return realdam
	end,
}

-- Cold damage + freeze ground
newDamageType{
	name = "cold ground", type = "COLDNEVERMOVE",
	kr_name = "얼어붙은 땅",
	projector = function(src, x, y, type, dam)
		if _G.type(dam) == "number" then dam = {dam=dam, dur=4} end
		DamageType:get(DamageType.COLD).projector(src, x, y, DamageType.COLD, dam.dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			if target:canBe("pin") and target:canBe("stun") and not target:attr("fly") and not target:attr("levitation") then
				target:setEffect(target.EFF_FROZEN_FEET, dam.dur, {apply_power=math.max(src:combatSpellpower(), src:combatMindpower())})
			end

			if dam.shatter_reduce and target:hasEffect(target.EFF_WET) then
				src:alterTalentCoolingdown(src.T_SHATTER, -dam.shatter_reduce)
			end
		end
	end,
}

-- Freezes target, checks for spellresistance and stun resistance
newDamageType{
	name = "freeze", type = "FREEZE",
	kr_name = "빙결",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			-- Freeze it, if we pass the test
			local sx, sy = game.level.map:getTileToScreen(x, y)
			if target:canBe("stun") then
				target:setEffect(target.EFF_FROZEN, dam.dur, {hp=dam.hp * 1.5, apply_power=math.max(src:combatSpellpower(), src:combatMindpower()), min_dur=1})
				game.flyers:add(sx, sy, 30, (rng.range(0,2)-1) * 0.5, -3, "얼어붙음!", {0,255,155})
			else
				game.flyers:add(sx, sy, 30, (rng.range(0,2)-1) * 0.5, -3, "저항함!", {0,255,155})
				game.logSeen(target, "%s 저항했습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}

-- Dim vision
newDamageType{
	name = "sticky smoke", type = "STICKY_SMOKE",
	kr_name = "끈적이는 연기",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			if target:canBe("blind") then
				target:setEffect(target.EFF_DIM_VISION, 7, {sight=dam, apply_power=src:combatAttack()})
			else
				game.logSeen(target, "%s 저항했습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}

-- Acid damage + blind chance
newDamageType{
	name = "acid blind", type = "ACID_BLIND", text_color = "#GREEN#",
	kr_name = "실명형 산성",
	projector = function(src, x, y, type, dam)
		local realdam = DamageType:get(DamageType.ACID).projector(src, x, y, DamageType.ACID, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and rng.percent(25) then
			if target:canBe("blind") then
				target:setEffect(target.EFF_BLINDED, 3, {src=src, apply_power=math.max(src:combatAttack(), src:combatSpellpower(), src:combatMindpower())})
			else
				game.logSeen(target, "%s 저항했습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
		return realdam
	end,
}

-- Darkness damage + blind chance
newDamageType{
	name = "blinding darkness", type = "DARKNESS_BLIND",
	kr_name = "실명의 어둠",
	projector = function(src, x, y, type, dam)
		local realdam = DamageType:get(DamageType.DARKNESS).projector(src, x, y, DamageType.DARKNESS, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and rng.percent(25) then
			if target:canBe("blind") then
				target:setEffect(target.EFF_BLINDED, 3, {src=src, apply_power=src:combatSpellpower()})
			else
				game.logSeen(target, "%s 저항했습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
		return realdam
	end,
}

-- Light damage + blind chance
newDamageType{
	name = "blinding light", type = "LIGHT_BLIND", text_color = "#YELLOW#",
	kr_name = "실명의 빛",
	projector = function(src, x, y, type, dam)
		local realdam = DamageType:get(DamageType.LIGHT).projector(src, x, y, DamageType.LIGHT, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and rng.percent(25) then
			if target:canBe("blind") then
				target:setEffect(target.EFF_BLINDED, 3, {src=src, apply_power=src:combatSpellpower()})
			else
				game.logSeen(target, "%s 저항했습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
		return realdam
	end,
}

-- Lightning damage + daze chance
newDamageType{
	name = "dazing lightning", type = "LIGHTNING_DAZE", text_color = "#ROYAL_BLUE#",
	kr_name = "혼절의 번개",
	projector = function(src, x, y, type, dam)
		if _G.type(dam) == "number" then dam = {dam=dam, daze=25} end
		dam.daze = dam.daze or 25
		local realdam = DamageType:get(DamageType.LIGHTNING).projector(src, x, y, DamageType.LIGHTNING, dam.dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and dam.daze > 0 and rng.percent(dam.daze) then
			if target:canBe("stun") then
				game:onTickEnd(function() target:setEffect(target.EFF_DAZED, 3, {src=src, apply_power=dam.power_check or math.max(src:combatSpellpower(), src:combatMindpower(), src:combatAttack())}) end) -- Do it at the end so we don't break our own daze
				if src:isTalentActive(src.T_HURRICANE) then
					local t = src:getTalentFromId(src.T_HURRICANE)
					t.do_hurricane(src, t, target)
				end
			else
				game.logSeen(target, "%s 저항했습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
				if dam.shock then
					target:setEffect(target.EFF_SHOCKED, dam.shock, {apply_power=src:combatSpellpower()})
				end
			end
		end
		return realdam
	end,
}

-- Cold/physical damage + repulsion; checks for spell power against physical resistance
newDamageType{
	name = "cold repulsion", type = "WAVE",
	kr_name = "냉기 파동",
	projector = function(src, x, y, type, dam)
		local srcx, srcy = dam.x, dam.y
		local base = dam
		dam = dam.dam
		if not base.st then
			DamageType:get(DamageType.COLD).projector(src, x, y, DamageType.COLD, dam / 2)
			DamageType:get(DamageType.PHYSICAL).projector(src, x, y, DamageType.PHYSICAL, dam / 2)
		else
			DamageType:get(base.st).projector(src, x, y, base.st, dam)
		end
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			if base.apply_wet then
				target:setEffect(target.EFF_WET, base.apply_wet, {})
			end

			if target:checkHit(base.power or src:combatSpellpower(), target:combatPhysicalResist(), 0, 95, 15) and target:canBe("knockback") then
				target:knockback(srcx, srcy, base.dist or 1)
				target:crossTierEffect(target.EFF_OFFBALANCE, base.power or src:combatSpellpower())
				game.logSeen(target, "%s 밀려났습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			else
				game.logSeen(target, "%s 파동을 저항했습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}

-- Bloodspring damage + repulsion; checks for spell power against physical resistance
newDamageType{
	name = "bloodspring", type = "BLOODSPRING",
	kr_name = "피분수",
	projector = function(src, x, y, type, dam)
		local srcx, srcy = dam.x, dam.y
		local base = dam
		dam = dam.dam
		DamageType:get(base.st).projector(src, x, y, base.st, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			if target:checkHit(base.power or src:combatSpellpower(), target:combatPhysicalResist(), 0, 95, 15) and target:canBe("knockback") then
				target:knockback(srcx, srcy, base.dist or 1)
				target:crossTierEffect(target.EFF_OFFBALANCE, base.power or src:combatSpellpower())
				game.logSeen(target, "%s 밀려났습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			else
				game.logSeen(target, "%s 피분수를 저항했습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}

-- Fireburn damage + repulsion; checks for spell power against physical resistance
newDamageType{
	name = "fire repulsion", type = "FIREKNOCKBACK",
	kr_name = "화염 파동",
	projector = function(src, x, y, type, dam, tmp)
		local target = game.level.map(x, y, Map.ACTOR)
		if _G.type(dam) ~= "table" then dam = {dam=dam, dist=3} end
		tmp = tmp or {}
		if target and not tmp[target] then
			tmp[target] = true
			DamageType:get(DamageType.FIREBURN).projector(src, x, y, DamageType.FIREBURN, dam.dam)
			if target:checkHit(src:combatSpellpower(), target:combatPhysicalResist(), 0, 95, 15) and target:canBe("knockback") then
				target:knockback(src.x, src.y, dam.dist)
				target:crossTierEffect(target.EFF_OFFBALANCE, src:combatSpellpower())
				game.logSeen(target, "%s 밀려났습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			else
				game.logSeen(target, "%s 충격을 저항했습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}

-- Fireburn damage + repulsion; checks for mind power against physical resistance
newDamageType{
	name = "burning repulsion", type = "FIREKNOCKBACK_MIND",
	kr_name = "정신적 화염 파동",
	projector = function(src, x, y, type, dam, tmp)
		local target = game.level.map(x, y, Map.ACTOR)
		if _G.type(dam) ~= "table" then dam = {dam=dam, dist=3} end
		tmp = tmp or {}
		if target and not tmp[target] then
			tmp[target] = true
			DamageType:get(DamageType.FIREBURN).projector(src, x, y, DamageType.FIREBURN, dam.dam)
			if target:checkHit(src:combatMindpower(), target:combatPhysicalResist(), 0, 95, 15) and target:canBe("knockback") then
				target:knockback(src.x, src.y, dam.dist)
				target:crossTierEffect(target.EFF_OFFBALANCE, src:combatMindpower())
				game.logSeen(target, "%s 밀려났습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			else
				game.logSeen(target, "%s 충격을 저항했습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}

-- Darkness damage + repulsion; checks for spell power against mental resistance
newDamageType{
	name = "darkness repulsion", type = "DARKKNOCKBACK",
	kr_name = "어둠 파동",
	projector = function(src, x, y, type, dam, tmp)
		local target = game.level.map(x, y, Map.ACTOR)
		if _G.type(dam) ~= "table" then dam = {dam=dam, dist=3} end
		tmp = tmp or {}
		if target and not tmp[target] then
			tmp[target] = true
			DamageType:get(DamageType.DARKNESS).projector(src, x, y, DamageType.DARKNESS, dam.dam)
			if target:checkHit(src:combatSpellpower(), target:combatMentalResist(), 0, 95, 15) and target:canBe("knockback") then
				target:knockback(src.x, src.y, dam.dist)
				target:crossTierEffect(target.EFF_BRAINLOCKED, src:combatSpellpower())
				game.logSeen(target, "%s 밀려났습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			else
				game.logSeen(target, "%s 어둠을 저항했습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}

-- Physical damage + repulsion; checks for spell power against physical resistance
newDamageType{
	name = "physical repulsion", type = "SPELLKNOCKBACK",
	kr_name = "물리적 파동",
	projector = function(src, x, y, type, dam, tmp)
		local target = game.level.map(x, y, Map.ACTOR)
		local realdam = 0
		if _G.type(dam) ~= "table" then dam = {dam=dam, dist=3} end
		tmp = tmp or {}
		if target and not tmp[target] then
			tmp[target] = true
			realdam = DamageType:get(DamageType.PHYSICAL).projector(src, x, y, DamageType.PHYSICAL, dam.dam)
			if target:checkHit(src:combatSpellpower(), target:combatPhysicalResist(), 0, 95, 15) and target:canBe("knockback") then
				target:knockback(src.x, src.y, dam.dist)
				target:crossTierEffect(target.EFF_OFFBALANCE, src:combatSpellpower())
				game.logSeen(target, "%s 밀려났습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			else
				game.logSeen(target, "%s 충격을 저항했습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
		return realdam
	end,
}

-- Physical damage + repulsion; checks for mind power against physical resistance
newDamageType{
	name = "physical repulsion", type = "MINDKNOCKBACK",
	kr_name = "물리적 파동",
	projector = function(src, x, y, type, dam, tmp)
		local target = game.level.map(x, y, Map.ACTOR)
		tmp = tmp or {}
		if target and not tmp[target] then
			tmp[target] = true
			DamageType:get(DamageType.PHYSICAL).projector(src, x, y, DamageType.PHYSICAL, dam)
			if target:checkHit(src:combatMindpower() * 0.8, target:combatPhysicalResist(), 0, 95, 15) and target:canBe("knockback") then
				target:knockback(src.x, src.y, 3)
				target:crossTierEffect(target.EFF_OFFBALANCE, src:combatMindpower())
				game.logSeen(target, "%s 밀려났습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			else
				game.logSeen(target, "%s 충격을 저항했습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}

-- Physical damage + repulsion; checks for attack power against physical resistance
newDamageType{
	name = "physical repulsion", type = "PHYSKNOCKBACK",
	kr_name = "물리적 파동",
	projector = function(src, x, y, type, dam, tmp)
		local target = game.level.map(x, y, Map.ACTOR)
		tmp = tmp or {}
		if _G.type(dam) ~= "table" then dam = {dam=dam, dist=3} end
		if target and not tmp[target] then
			tmp[target] = true
			DamageType:get(DamageType.PHYSICAL).projector(src, x, y, DamageType.PHYSICAL, dam.dam)
			if target:checkHit(src:combatPhysicalpower(), target:combatPhysicalResist(), 0, 95, 15) and target:canBe("knockback") then
				target:knockback(dam.x or src.x, dam.y or src.y, dam.dist)
				target:crossTierEffect(target.EFF_OFFBALANCE, src:combatPhysicalpower())
				game.logSeen(target, "%s 밀려났습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			else
				game.logSeen(target, "%s 밀려나지 않았습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}

-- Fear check + repulsion; checks for mind power against physical resistance
newDamageType{
	name = "fear repulsion", type = "FEARKNOCKBACK",
	kr_name = "두려움의 파동",
	projector = function(src, x, y, type, dam, tmp)
		local target = game.level.map(x, y, Map.ACTOR)
		tmp = tmp or {}
		if target and not tmp[target] then
			tmp[target] = true
			if target:checkHit(src:combatMindpower(), target:combatPhysicalResist(), 0, 95, 15) and target:canBe("fear") then
				target:knockback(dam.x, dam.y, dam.dist)
				target:crossTierEffect(target.EFF_BRAINLOCKED, src:combatMindpower())
				game.logSeen(target, "%s 밀려났습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			else
				game.logSeen(target, "%s 위협적인 광경을 저항했습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}

-- Poisoning damage
newDamageType{
	name = "poison", type = "POISON", text_color = "#LIGHT_GREEN#",
	kr_name = "중독",
	projector = function(src, x, y, t, dam)
		local power
		if type(dam) == "table" then
			power = dam.apply_power
			dam = dam.dam
		end
		local realdam = DamageType:get(DamageType.NATURE).projector(src, x, y, DamageType.NATURE, dam / 6)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and target:canBe("poison") then
			target:setEffect(target.EFF_POISONED, 5, {src=src, power=dam / 6, apply_power=power or (src.combatAttack and src:combatAttack()) or 0})
		end
		return realdam
	end,
}

-- Inferno: fire and maybe remove stuff
newDamageType{
	name = "cleansing fire", type = "INFERNO",
	kr_name = "정화의 불길",
	projector = function(src, x, y, type, dam)
		local realdam = DamageType:get(DamageType.FIRE).projector(src, x, y, DamageType.FIRE, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and src:attr("cleansing_flames") and rng.percent(src:attr("cleansing_flames")) then
			local effs = {}
			local status = (src:reactionToward(target) >= 0) and "detrimental" or "beneficial"
			for eff_id, p in pairs(target.tmp) do
				local e = target.tempeffect_def[eff_id]
				if e.status == status and (e.type == "magical" or e.type == "physical") then
					effs[#effs+1] = {"effect", eff_id}
				end
			end
			if #effs > 0 then
				local eff = rng.tableRemove(effs)
				target:removeEffect(eff[2])
			end
		end
		return realdam
	end,
}

-- Spydric poison: prevents movement
-- Very special, does not have a power check
newDamageType{
	name = "spydric poison", type = "SPYDRIC_POISON",
	kr_name = "속박형 독",
	projector = function(src, x, y, type, dam)
		if _G.type(dam) == "number" then dam = {dam=dam, dur=3} end
		DamageType:get(DamageType.NATURE).projector(src, x, y, DamageType.NATURE, dam.dam / dam.dur)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and target:canBe("poison") then
			target:setEffect(target.EFF_SPYDRIC_POISON, dam.dur, {src=src, power=dam.dam / dam.dur, no_ct_effect=true})
		end
	end,
}

-- Crippling poison: failure to act
newDamageType{
	name = "crippling poison", type = "CRIPPLING_POISON", text_color = "#LIGHT_GREEN#",
	kr_name = "무력화 독",
	projector = function(src, x, y, type, dam)
		if _G.type(dam) == "number" then dam = {dam=dam, dur=3} end
		DamageType:get(DamageType.NATURE).projector(src, x, y, DamageType.NATURE, dam.dam / dam.dur)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and target:canBe("poison") then
			target:setEffect(target.EFF_CRIPPLING_POISON, dam.dur, {src=src, power=dam.dam / dam.dur, no_ct_effect=true})
		end
	end,
}

-- Insidious poison: prevents healing
newDamageType{
	name = "insidious poison", type = "INSIDIOUS_POISON", text_color = "#LIGHT_GREEN#",
	kr_name = "잠식형 독",
	projector = function(src, x, y, type, dam)
		if _G.type(dam) == "number" then dam = {dam=dam, dur=7, heal_factor=dam} end
		DamageType:get(DamageType.NATURE).projector(src, x, y, DamageType.NATURE, dam.dam / dam.dur)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and target:canBe("poison") then
			target:setEffect(target.EFF_INSIDIOUS_POISON, dam.dur, {src=src, power=dam.dam / dam.dur, heal_factor=dam.heal_factor, no_ct_effect=true})
		end
	end,
}

-- Bleeding damage
newDamageType{
	name = "bleed", type = "BLEED",
	kr_name = "출혈",
	projector = function(src, x, y, type, dam)
		DamageType:get(DamageType.PHYSICAL).projector(src, x, y, DamageType.PHYSICAL, dam / 6)
		dam = dam - dam / 6
		local target = game.level.map(x, y, Map.ACTOR)
		if target and target:canBe("cut") then
			-- Set on fire!
			target:setEffect(target.EFF_CUT, 5, {src=src, power=dam / 5, no_ct_effect=true})
		end
	end,
}

-- Physical damage + bleeding % of it
newDamageType{
	name = "physical bleed", type = "PHYSICALBLEED",
	kr_name = "물리적 출혈",
	projector = function(src, x, y, type, dam)
		local realdam = DamageType:get(DamageType.PHYSICAL).projector(src, x, y, DamageType.PHYSICAL, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if realdam > 0 and target and target:canBe("cut") then
			target:setEffect(target.EFF_CUT, 5, {src=src, power=dam * 0.1, no_ct_effect=true})
		end
	end,
}

-- Slime damage
newDamageType{
	name = "nature slow", type = "SLIME", text_color = "#LIGHT_GREEN#",
	kr_name = "자연적 감속",
	projector = function(src, x, y, type, dam)
		if _G.type(dam) == "number" then dam = {dam=dam, power=0.15} end
		DamageType:get(DamageType.NATURE).projector(src, x, y, DamageType.NATURE, dam.dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			target:setEffect(target.EFF_SLOW, 3, {power=dam.power, no_ct_effect=true})
		end
	end,
}


newDamageType{
	name = "dig", type = "DIG",
	kr_name = "굴착",
	projector = function(src, x, y, typ, dam)
		local feat = game.level.map(x, y, Map.TERRAIN)
		if feat then
			if feat.dig then
				local newfeat_name, newfeat, silence = feat.dig, nil, false
				if type(feat.dig) == "function" then newfeat_name, newfeat, silence = feat.dig(src, x, y, feat) end
				newfeat = newfeat or game.zone.grid_list[newfeat_name]
				if newfeat then
					game.level.map(x, y, Map.TERRAIN, newfeat)
					src.dug_times = (src.dug_times or 0) + 1
					game.nicer_tiles:updateAround(game.level, x, y)
					if not silence then
						game.logSeen({x=x,y=y}, "%s %s 변했습니다.", (feat.kr_name or feat.name):capitalize():addJosa("가"), (newfeat.kr_name or newfeat.name):addJosa("로"))
					end
				end
			end
		end
	end,
}

-- Slowness
newDamageType{
	name = "slow", type = "SLOW",
	kr_name = "감속",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			-- Freeze it, if we pass the test
			local sx, sy = game.level.map:getTileToScreen(x, y)
			target:setEffect(target.EFF_SLOW, 7, {power=dam, apply_power=src:combatSpellpower()})
		end
	end,
}

newDamageType{
	name = "congeal time", type = "CONGEAL_TIME",
	kr_name = "얼어붙은 시간",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			-- Freeze it, if we pass the test
			local sx, sy = game.level.map:getTileToScreen(x, y)
			target:setEffect(target.EFF_CONGEAL_TIME, 7, {slow=dam.slow, proj=dam.proj, apply_power=src:combatSpellpower()})
		end
	end,
}

-- Time prison, invulnerability and stun
newDamageType{
	name = "time prison", type = "TIME_PRISON",
	kr_name = "시간의 감옥",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			-- Freeze it, if we pass the test
			local sx, sy = game.level.map:getTileToScreen(x, y)
			if src == target then
				target:setEffect(target.EFF_TIME_PRISON, dam, {no_ct_effect=true})
				target:setEffect(target.EFF_CONTINUUM_DESTABILIZATION, 100, {power=src:combatSpellpower(0.3), no_ct_effect=true})
			elseif target:checkHit(src:combatSpellpower() - (target:attr("continuum_destabilization") or 0), target:combatSpellResist(), 0, 95, 15) then
				target:setEffect(target.EFF_TIME_PRISON, dam, {apply_power=src:combatSpellpower() - (target:attr("continuum_destabilization") or 0), apply_save="combatSpellResist", no_ct_effect=true})
				target:setEffect(target.EFF_CONTINUUM_DESTABILIZATION, 100, {power=src:combatSpellpower(0.3), no_ct_effect=true})
			else
				game.logSeen(target, "%s 시간의 감옥을 저항했습니다.", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}

-- Confusion
newDamageType{
	name = "confusion", type = "CONFUSION",
	kr_name = "혼란",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			if target:canBe("confusion") then
				target:setEffect(target.EFF_CONFUSED, dam.dur, {power=dam.dam, apply_power=(dam.power_check or src.combatSpellpower)(src)})
			else
				game.logSeen(target, "%s 저항했습니다.", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}

-- Confusion
newDamageType{
	name = "% chance of confusion", type = "RANDOM_CONFUSION",
	kr_name = "% 확률로 혼란",
	projector = function(src, x, y, type, dam)
		if _G.type(dam) == "number" then dam = {dam=dam} end
		local target = game.level.map(x, y, Map.ACTOR)
		if target and rng.percent(dam.dam) then
			if target:canBe("confusion") then
				target:setEffect(target.EFF_CONFUSED, 4, {power=75, apply_power=(dam.power_check or src.combatSpellpower)(src), no_ct_effect=true})
			else
				game.logSeen(target, "%s 저항했습니다.", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}

-- Confusion
newDamageType{
	name = "% chance of confusion", type = "RANDOM_CONFUSION_PHYS",
	kr_name = "% 확률로 혼란",
	projector = function(src, x, y, type, dam)
		if _G.type(dam) == "number" then dam = {dam=dam} end
		local target = game.level.map(x, y, Map.ACTOR)
		if target and rng.percent(dam.dam) then
			if target:canBe("confusion") then
				target:setEffect(target.EFF_CONFUSED, 4, {power=75, apply_power=src:combatPhysicalpower(), no_ct_effect=true})
			else
				game.logSeen(target, "%s 저항했습니다.", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}

newDamageType{
	name = "% chance of gloom effects", type = "RANDOM_GLOOM",
	kr_name = "% 확률로 침울 효과",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and rng.percent(dam) then
			if not src:checkHit(src:combatMindpower(), target:combatMentalResist()) then return end
			local effect = rng.range(1, 3)
			if effect == 1 then
				-- confusion
				if target:canBe("confusion") and not target:hasEffect(target.EFF_GLOOM_CONFUSED) then
					target:setEffect(target.EFF_GLOOM_CONFUSED, 2, {power=70})
				end
			elseif effect == 2 then
				-- stun
				if target:canBe("stun") and not target:hasEffect(target.EFF_GLOOM_STUNNED) then
					target:setEffect(target.EFF_GLOOM_STUNNED, 2, {})
				end
			elseif effect == 3 then
				-- slow
				if target:canBe("slow") and not target:hasEffect(target.EFF_GLOOM_SLOW) then
					target:setEffect(target.EFF_GLOOM_SLOW, 2, {power=0.3})
				end
			end
		end
	end,
}

----------------------------------------------------------------
-- Item-specific damage types
----------------------------------------------------------------
-- Each uses the highest of Accuracy, Spellpower, or Mindpower for apply_power but typically uses the most thematic power for other effects
-- tdesc is only used in item tooltips and replaces the normal melee_project display

-- Name:  item - theme - debuff/effect

-- Log entries are pretty limited currently because it can be quite spammy with the default messages already
newDamageType{
	name = "item mind gloom", type = "ITEM_MIND_GLOOM",
	kr_name = "물체부여된 정신적 침울함",
	tdesc = function(dam, oldDam)
		parens = ""
		dam = dam or 0
		if oldDam then
			diff = dam - oldDam
			if diff > 0 then
				parens = (" (#LIGHT_GREEN#+%d%%#LAST#)"):format(diff)
			elseif diff < 0 then
				parens = (" (#RED#%d%%#LAST#)"):format(diff)
			end
		end
		return ("* #LIGHT_GREEN#%d%%#LAST# 확률로 #YELLOW#임의의 광기#LAST#를 발생 %s")
			:format(dam, parens)
	end,
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and rng.percent(dam) then
			local check = math.max(src:combatAttack(), src:combatSpellpower(), src:combatMindpower())
			if not src:checkHit(check, target:combatMentalResist()) then return end
			local effect = rng.range(1, 3)
			if effect == 1 then
				-- confusion
				if target:canBe("confusion") and not target:hasEffect(target.EFF_GLOOM_CONFUSED) then
					target:setEffect(target.EFF_GLOOM_CONFUSED, 2, {power=25, no_ct_effect=true} )
				end
			elseif effect == 2 then
				-- stun
				if target:canBe("stun") and not target:hasEffect(target.EFF_GLOOM_STUNNED) then
					target:setEffect(target.EFF_GLOOM_STUNNED, 2, {no_ct_effect=true})
				end
			elseif effect == 3 then
				-- slow
				if target:canBe("slow") and not target:hasEffect(target.EFF_GLOOM_SLOW) then
					target:setEffect(target.EFF_GLOOM_SLOW, 2, {power=0.3, no_ct_effect=true})
				end
			end
		end
	end,
}

newDamageType{
	name = "item darkness numbing", type = "ITEM_DARKNESS_NUMBING",
	kr_name = "물체부여된 마비의 어둠",
	tdesc = function(dam, oldDam)
		parens = ""
		dam = dam or 0
		if oldDam then
			diff = dam - oldDam
			if diff > 0 then
				parens = (" (#LIGHT_GREEN#+%d%%#LAST#)"):format(diff)
			elseif diff < 0 then
				parens = (" (#RED#%d%%#LAST#)"):format(diff)
			end
		end
		return ("* #LIGHT_GREEN#%d%%#LAST# 확률로 #GREY#공격력 감소#LAST# 발생 %s")
			:format(dam, parens)
	end,
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and rng.percent(dam) then
				local check = math.max(src:combatAttack(), src:combatSpellpower(), src:combatMindpower())
				local reduction = 15
				target:setEffect(target.EFF_ITEM_NUMBING_DARKNESS, 4, {reduce = reduction, apply_power=check, no_ct_effect=true})
		end
	end,
}

newDamageType{
	name = "item temporal energize", type = "ITEM_TEMPORAL_ENERGIZE",
	kr_name = "물체부여된 시간의 기운",
	tdesc = function(dam, oldDam)
		parens = ""
		dam = dam or 0
		if oldDam then
			diff = dam - oldDam
			if diff > 0 then
				parens = (" (#LIGHT_GREEN#+%d%%#LAST#)"):format(diff)
			elseif diff < 0 then
				parens = (" (#RED#%d%%#LAST#)"):format(diff)
			end
		end
		return ("* #LIGHT_GREEN#%d%%#LAST# 확률로 #LIGHT_STEEL_BLUE#한 턴의 10%%#LAST# 만큼 추가 시간 획득 %s")
			:format(dam, parens)
	end,
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and src and src.name and rng.percent(dam) then
				if src.turn_procs and src.turn_procs.item_temporal_energize and src.turn_procs.item_temporal_energize > 3 then
					game.logSeen(src, "#LIGHT_STEEL_BLUE#%s 이번 턴에 더이상 추가 시간을 얻을 수 없습니다! ", (src.kr_name or src.name):capitalize():addJosa("는"))
				return
				end

				local energy = (game.energy_to_act * 0.1)
				src.energy.value = src.energy.value + energy
				--game.logSeen(target, "Time seems to bend and quicken energizing %s!", src.name:capitalize())

				src.turn_procs.item_temporal_energize = 1 + (src.turn_procs.item_temporal_energize or 0)
		end
	end,
}

newDamageType{
	name = "item acid corrode", type = "ITEM_ACID_CORRODE", text_color = "#GREEN#",
	kr_name = "물체부여된 산성 부식",
	tdesc = function(dam, oldDam)
		parens = ""
		dam = dam or 0
		if oldDam then
			diff = dam - oldDam
			if diff > 0 then
				parens = (" (#LIGHT_GREEN#+%d%%#LAST#)"):format(diff)
			elseif diff < 0 then
				parens = (" (#RED#%d%%#LAST#)"):format(diff)
			end
		end
		return ("* #LIGHT_GREEN#%d%%#LAST# 확률로 #GREEN#방어구 부식#LAST# 발생 %s")
			:format(dam, parens)
	end,
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and rng.percent(dam) then
			local check = math.max(src:combatAttack(), src:combatSpellpower(), src:combatMindpower())
			--local param = { atk=dam/3, armor=dam/3, defense=dam/3, src=src, apply_power = check, no_ct_effect=true }
			target:setEffect(target.EFF_ITEM_ACID_CORRODE, 5, {pct = 0.3, no_ct_effect = true, apply_power = check})
		end
	end,
}

newDamageType{
	name = "item light blind", type = "ITEM_LIGHT_BLIND",
	kr_name = "물체부여된 실명의 빛",
	tdesc = function(dam, oldDam)
		parens = ""
		dam = dam or 0
		if oldDam then
			diff = dam - oldDam
			if diff > 0 then
				parens = (" (#LIGHT_GREEN#+%d%%#LAST#)"):format(diff)
			elseif diff < 0 then
				parens = (" (#RED#%d%%#LAST#)"):format(diff)
			end
		end
		return ("* #LIGHT_GREEN#%d%%#LAST# 확률로 #YELLOW#실명#LAST# 발생 %s")
			:format(dam, parens)
	end,
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and rng.percent(dam) then
			if target:canBe("blind") then
				local check = math.max(src:combatAttack(), src:combatSpellpower(), src:combatMindpower())
				target:setEffect(target.EFF_BLINDED, 4, {apply_power=(check), no_ct_effect=true})
			else
				--game.logSeen(target, "%s resists the blinding light!", target.name:capitalize())
			end
		end
	end,
}

newDamageType{
	name = "item lightning daze", type = "ITEM_LIGHTNING_DAZE",
	kr_name = "물체부여된 혼절의 번개",
	tdesc = function(dam, oldDam)
		parens = ""
		dam = dam or 0
		if oldDam then
			diff = dam - oldDam
			if diff > 0 then
				parens = (" (#LIGHT_GREEN#+%d%%#LAST#)"):format(diff)
			elseif diff < 0 then
				parens = (" (#RED#%d%%#LAST#)"):format(diff)
			end
		end
		return ("* #LIGHT_GREEN#%d%%#LAST# 확률로 #ROYAL_BLUE#혼절#LAST# 발생 %s")
			:format(dam, parens)
	end,
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and rng.percent(dam) then
			if target:canBe("stun") then
				local check = math.max(src:combatAttack(), src:combatSpellpower(), src:combatMindpower())
				--game:onTickEnd(function() target:setEffect(target.EFF_DAZED, 3, {src=src, apply_power=dam.power_check or math.max(src:combatSpellpower(), src:combatMindpower(), src:combatAttack())}) end) -- Do it at the end so we don't break our own daze
				game:onTickEnd(function() target:setEffect(target.EFF_DAZED, 4, {apply_power=check, no_ct_effect=true}) end)
			else
				--game.logSeen(target, "%s resists the daze!", target.name:capitalize())
			end
		end
	end,
}

newDamageType{
	name = "item blight disease", type = "ITEM_BLIGHT_DISEASE", text_color = "#DARK_GREEN#",
	kr_name = "물체부여된 황폐의 질병",
	tdesc = function(dam, oldDam)
		parens = ""
		dam = dam or 0
		if oldDam then
			diff = dam - oldDam
			if diff > 0 then
				parens = (" (#LIGHT_GREEN#+%d%%#LAST#)"):format(diff)
			elseif diff < 0 then
				parens = (" (#RED#%d%%#LAST#)"):format(diff)
			end
		end
		return ("* #LIGHT_GREEN#%d%%#LAST# 확률로 #DARK_GREEN#질병#LAST# 발생 %s")
			:format(dam, parens)
	end,
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and  rng.percent(dam) and target:canBe("disease") then
			local check = math.max(src:combatSpellpower(), src:combatMindpower(), src:combatAttack())
			local disease_power = math.min(30, dam / 2)
			target:setEffect(target.EFF_ITEM_BLIGHT_ILLNESS, 5, {reduce = disease_power})
		end
	end,
}

newDamageType{
	name = "item manaburn arcane", type = "ITEM_ANTIMAGIC_MANABURN", text_color = "#PURPLE#",
	kr_name = "물체부여된 마법 원천력 태우기",
	tdesc = function(dam, oldDam)
		parens = ""
		dam = dam or 0
		if oldDam then
			diff = dam - oldDam
			if diff > 0 then
				parens = (" (#LIGHT_GREEN#+%d#LAST#)"):format(diff)
			elseif diff < 0 then
				parens = (" (#RED#%d#LAST#)"):format(diff)
			end
		end
		return ("* #DARK_ORCHID#%d 마법 원천력#LAST#을 불태움 %s")
			:format(dam or 0, parens)
	end,
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			-- Note:  Standardize this conversion somewhere in Actor.lua
			local mana = dam
			local vim = dam / 2
			local positive = dam / 4
			local negative = dam / 4

			mana = math.min(target:getMana(), mana)
			vim = math.min(target:getVim(), vim)
			positive = math.min(target:getPositive(), positive)
			negative = math.min(target:getNegative(), negative)

			target:incMana(-mana)
			target:incVim(-vim)
			target:incPositive(-positive)
			target:incNegative(-negative)

			local dam = math.max(mana, vim * 2, positive * 4, negative * 4)
			return DamageType:get(DamageType.ARCANE).projector(src, x, y, DamageType.ARCANE, dam)
		end
		return 0
	end,
}

newDamageType{
	name = "item nature slow", type = "ITEM_NATURE_SLOW", text_color = "#LIGHT_GREEN#",
	kr_name = "물체부여된 자연적 감속",
	tdesc = function(dam, oldDam)
		parens = ""
		dam = dam or 0
		if oldDam then
			diff = dam - oldDam
			if diff > 0 then
				parens = (" (#LIGHT_GREEN#+%d%%#LAST#)"):format(diff)
			elseif diff < 0 then
				parens = (" (#RED#%d%%#LAST#)"):format(diff)
			end
		end
		return ("* 전체 속도 #LIGHT_GREEN#%d%%#LAST# 감소 %s")
			:format(dam, parens)
	end,
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			target:setEffect(target.EFF_SLOW, 3, {power= math.min(60, dam / 100), no_ct_effect=true})
		end
	end,
}

-- Reduces all offensive powers by 20%
newDamageType{
	name = "item antimagic scouring", type = "ITEM_ANTIMAGIC_SCOURING", text_color = "#ORCHID#",
	kr_name = "물체부여된 반마법 세척",
	tdesc = function(dam, oldDam)
		parens = ""
		dam = dam or 0
		if oldDam then
			diff = dam - oldDam
			if diff > 0 then
				parens = (" (#LIGHT_GREEN#+%d%%#LAST#)"):format(diff)
			elseif diff < 0 then
				parens = (" (#RED#%d%%#LAST#)"):format(diff)
			end
		end
		return ("* #LIGHT_GREEN#%d%%#LAST# 확률로 #ORCHID#공격력 %d%% 감소#LAST# %s") --@ "reduce power"를 "공격력 감소"로 번역 : 확인 필요
			:format(dam, 20, parens)
	end,
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			target:setEffect(target.EFF_ITEM_ANTIMAGIC_SCOURED, 3, {pct = 0.2, no_ct_effect=true})
		end
	end,
}




------------------------------------------------------------------------------------

-- gBlind
newDamageType{
	name = "blinding", type = "RANDOM_BLIND",
	kr_name = "실명",
	projector = function(src, x, y, type, dam)
		if _G.type(dam) == "number" then dam = {dam=dam} end
		local target = game.level.map(x, y, Map.ACTOR)
		if target and rng.percent(dam.dam) then
			if target:canBe("blind") then
				target:setEffect(target.EFF_BLINDED, 4, {apply_power=(dam.power_check or math.max(src:combatSpellpower(), src:combatPhysicalpower())), no_ct_effect=true})
			else
				game.logSeen(target, "%s 실명을 저항했습니다.", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}

-- Physical + Blind
newDamageType{
	name = "blinding physical", type = "SAND",
	kr_name = "물리적 실명",
	projector = function(src, x, y, type, dam)
		DamageType:get(DamageType.PHYSICAL).projector(src, x, y, DamageType.PHYSICAL, dam.dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			if target:canBe("blind") then
				target:setEffect(target.EFF_BLINDED, dam.dur, {apply_power=src:combatPhysicalpower(), apply_save="combatPhysicalResist"})
			else
				game.logSeen(target, "%s 수면의 폭풍을 저항했습니다.", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}

-- Physical + Pinned
newDamageType{
	name = "physical pinning", type = "PINNING",
	kr_name = "물리적 속박",
	projector = function(src, x, y, type, dam)
		DamageType:get(DamageType.PHYSICAL).projector(src, x, y, DamageType.PHYSICAL, dam.dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			if target:canBe("pin") then
				target:setEffect(target.EFF_PINNED, dam.dur, {apply_power=src:combatPhysicalpower()})
			else
				game.logSeen(target, "%s 속박을 저항했습니다.", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}

-- Drain Exp
newDamageType{
	name = "regressive blight", type = "DRAINEXP",
	kr_name = "퇴행하는 황폐",
	projector = function(src, x, y, type, dam)
		if _G.type(dam) == "number" then dam = {dam=dam} end
		local realdam = DamageType:get(DamageType.BLIGHT).projector(src, x, y, DamageType.BLIGHT, dam.dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			if target:checkHit((dam.power_check or src.combatSpellpower)(src), (dam.resist_check or target.combatMentalResist)(target), 0, 95, 15) then
				target:gainExp(-dam.dam*2)
				src:logCombat(target, "#Source1# #Target#의 경험치를 떨어뜨립니다!")
			else
				game.logSeen(target, "%s 저항했습니다.", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
		return realdam
	end,
}

-- Drain Life
newDamageType{
	name = "draining blight", type = "DRAINLIFE", text_color = "#DARK_GREEN#",
	kr_name = "흡수하는 황폐",
	projector = function(src, x, y, type, dam)
		if _G.type(dam) == "number" then dam = {dam=dam, healfactor=0.4} end
		local target = game.level.map(x, y, Map.ACTOR) -- Get the target first to make sure we heal even on kill
		local realdam = DamageType:get(DamageType.BLIGHT).projector(src, x, y, DamageType.BLIGHT, dam.dam)
		if target and realdam > 0 then
			src:heal(realdam * dam.healfactor, target)
			src:logCombat(target, "#Source1# #Target#의 생명력을 빼앗아갑니다!")
		end
		return realdam
	end,
}

-- Drain Vim
newDamageType{
	name = "vim draining blight", type = "DRAIN_VIM", text_color = "#DARK_GREEN#",
	kr_name = "원기를 흡수하는 황폐",
	projector = function(src, x, y, type, dam)
		if _G.type(dam) == "number" then dam = {dam=dam, vim=0.2} end
		local target = game.level.map(x, y, Map.ACTOR)
		local realdam = DamageType:get(DamageType.BLIGHT).projector(src, x, y, DamageType.BLIGHT, dam.dam)
		if target and target ~= src and target.summoner ~= src and realdam > 0 then
			src:incVim(realdam * dam.vim * target:getRankVimAdjust())
		end
		return realdam
	end,
}

-- Demonfire: heal demon; damage others
newDamageType{
	name = "demonfire", type = "DEMONFIRE",
	kr_name = "악마의 불길",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and target:attr("demon") then
			target:heal(dam, src)
			return -dam
		elseif target then
			DamageType:get(DamageType.FIRE).projector(src, x, y, DamageType.FIRE, dam)
			return dam
		end
	end,
}

-- Retch: heal undead; damage living
newDamageType{
	name = "purging blight", type = "RETCH",
	kr_name = "구역질나는 황폐",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and (target:attr("undead") or target:attr(retch_heal)) then
			target:heal(dam * 1.5, src)

			if src.callTalent then
				if rng.percent(src:callTalent(src.T_RETCH, "getPurgeChance")) then
					local effs = {}
					local status = "detrimental"
					for eff_id, p in pairs(target.tmp) do
						local e = target.tempeffect_def[eff_id]
						if e.status == status and e.type == "physical" then
							effs[#effs+1] = {"effect", eff_id}
						end
					end
					if #effs > 0 then
						local eff = rng.tableRemove(effs)
						target:removeEffect(eff[2])
					end
				end
			end
		elseif target then
			DamageType:get(DamageType.BLIGHT).projector(src, x, y, DamageType.BLIGHT, dam)

			if src.callTalent then
				if rng.percent(src:callTalent(src.T_RETCH, "getPurgeChance")) then
					local effs = {}
					local status = "beneficial"
					for eff_id, p in pairs(target.tmp) do
						local e = target.tempeffect_def[eff_id]
						if e.status == status and e.type == "physical" then
							effs[#effs+1] = {"effect", eff_id}
						end
					end
					if #effs > 0 then
						local eff = rng.tableRemove(effs)
						target:removeEffect(eff[2])
					end
				end
			end
		end
	end,
}

-- Holy light, damage demon/undead; heal others
newDamageType{
	name = "holy light", type = "HOLY_LIGHT",
	kr_name = "성스러운 빛",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and not target:attr("undead") and not target:attr("demon") then
			target:heal(dam / 2, src)
		elseif target then
			DamageType:get(DamageType.LIGHT).projector(src, x, y, DamageType.LIGHT, dam)
		end
	end,
}

-- Heals
newDamageType{
	name = "healing", type = "HEAL",
	kr_name = "치료",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			target:attr("allow_on_heal", 1)
			target:heal(dam, src)
			target:attr("allow_on_heal", -1)
		end
	end,
}

-- Used by Bathe in Light, healing+shielding
-- Keep an eye on this and Weapon of Light for any infinite stack shield then engage combos
newDamageType{
	name = "healing light", type = "HEALING_POWER",
	kr_name = "치료의 빛",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			target:setEffect(target.EFF_EMPOWERED_HEALING, 1, {power=(dam/200)})
			if dam >= 100 then target:attr("allow_on_heal", 1) end
			target:heal(dam, src)

			-- If the target is shielded already then add to the shield power, else add a shield
			local shield_power = dam * util.bound((target.healing_factor or 1), 0, 2.5)
			if not target:hasEffect(target.EFF_DAMAGE_SHIELD) then
				target:setEffect(target.EFF_DAMAGE_SHIELD, 2, {power=shield_power})
			else
				-- Shields can't usually merge, so change the parameters manually
				local shield = target:hasEffect(target.EFF_DAMAGE_SHIELD)
				shield.power = shield.power + shield_power
				target.damage_shield_absorb = target.damage_shield_absorb + shield_power
				target.damage_shield_absorb_max = target.damage_shield_absorb_max + shield_power
				shield.dur = math.max(2, shield.dur)

				-- Limit the number of times a shield can be extended
				if shield.dur_extended then
					shield.dur_extended = shield.dur_extended + 1
					if shield.dur_extended >= 20 then
						game.logPlayer(target, "#DARK_ORCHID#피해 보호막이 더이상 연장되지 못하고 터져버렸습니다.")
						target:removeEffect(target.EFF_DAMAGE_SHIELD)
					end
				else shield.dur_extended = 1 end
			end
			if dam >= 100 then target:attr("allow_on_heal", -1) end
		end
	end,
}

-- Light damage+heal source, used by Radiance
newDamageType{
	name = "judgement", type = "JUDGEMENT",
	kr_name = "심판",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and target ~= src then
			--print("[JUDGEMENT] src ", src, "target", target, "src", src )
			DamageType:get(DamageType.LIGHT).projector(src, x, y, DamageType.LIGHT, dam)
			if dam >= 100 then src:attr("allow_on_heal", 1) end
			src:heal(dam / 2, src)
			if dam >= 100 then src:attr("allow_on_heal", -1) end


		end
	end,
}

newDamageType{
	name = "healing nature", type = "HEALING_NATURE",
	kr_name = "자연의 치료",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and not target:attr("undead") then
			if dam >= 100 then target:attr("allow_on_heal", 1) else target:attr("silent_heal", 1) end
			target:heal(dam, src)
			if dam >= 100 then target:attr("allow_on_heal", -1) else target:attr("silent_heal", -1) end
		elseif target then
			DamageType:get(DamageType.NATURE).projector(src, x, y, DamageType.NATURE, dam)
			
		end
	end,
}

-- Corrupted blood, blight damage + potential diseases
-- Should no longer be used on items, use ITEM_BLIGHT_DISEASE
newDamageType{
	name = "infective blight", type = "CORRUPTED_BLOOD", text_color = "#DARK_GREEN#",
	kr_name = "전염시키는 황폐",
	projector = function(src, x, y, type, dam)
		if _G.type(dam) == "number" then dam = {dam=dam} end
		DamageType:get(DamageType.BLIGHT).projector(src, x, y, DamageType.BLIGHT, dam.dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and target:canBe("disease") and rng.percent(dam.disease_chance or 20) then
			local eff = rng.table{{target.EFF_ROTTING_DISEASE, "con"}, {target.EFF_DECREPITUDE_DISEASE, "dex"}, {target.EFF_WEAKNESS_DISEASE, "str"}}
			target:setEffect(eff[1], dam.dur or 5, { src = src, [eff[2]] = dam.disease_power or 5, dam = dam.disease_dam or (dam.dam / 5) })
		end
	end,
}

-- blood boiled, blight damage + slow
newDamageType{
	name = "hindering blight", type = "BLOOD_BOIL", text_color = "#DARK_GREEN#",
	kr_name = "저해시키는 황폐",
	projector = function(src, x, y, type, dam)
		DamageType:get(DamageType.BLIGHT).projector(src, x, y, DamageType.BLIGHT, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and not target:attr("undead") and not target:attr("construct") then
			target:setEffect(target.EFF_SLOW, 4, {power=0.2, no_ct_effect=true})
		end
	end,
}

-- life leech (used cursed gloom skill)
newDamageType{
	name = "life leech",
	kr_name = "생명력 강탈",
	type = "LIFE_LEECH",
	text_color = "#F53CBE#",
	hideMessage=true,
	hideFlyer=true
}

-- Physical + Stun Chance
newDamageType{
	name = "physical stun", type = "PHYSICAL_STUN",
	kr_name = "물리적 기절",
	projector = function(src, x, y, type, dam)
		DamageType:get(DamageType.PHYSICAL).projector(src, x, y, DamageType.PHYSICAL, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and rng.percent(25) then
			if target:canBe("stun") then
				target:setEffect(target.EFF_STUNNED, 2, {src=src, apply_power=src:combatSpellpower(), min_dur=1})
			else
				game.logSeen(target, "%s 기절을 저항했습니다.", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}

-- Physical Damage/Cut Split
newDamageType{
	name = "physical bleed", type = "SPLIT_BLEED",
	kr_name = "물리적 출혈",
	projector = function(src, x, y, type, dam)
		DamageType:get(DamageType.PHYSICAL).projector(src, x, y, DamageType.PHYSICAL, dam / 2)
		DamageType:get(DamageType.PHYSICAL).projector(src, x, y, DamageType.PHYSICAL, dam / 12)
		dam = dam - dam / 12
		local target = game.level.map(x, y, Map.ACTOR)
		if target and target:canBe("cut") then
			-- Set on fire!
			target:setEffect(target.EFF_CUT, 5, {src=src, power=dam / 11, no_ct_effect=true})
		end
	end,
}

-- Temporal/Physical damage
newDamageType{
	name = "temporal shear", type = "MATTER",
	kr_name = "시간 베기",
	projector = function(src, x, y, type, dam)
		DamageType:get(DamageType.TEMPORAL).projector(src, x, y, DamageType.TEMPORAL, dam / 2)
		DamageType:get(DamageType.PHYSICAL).projector(src, x, y, DamageType.PHYSICAL, dam / 2)
	end,
}

-- Temporal/Darkness damage
newDamageType{
	name = "temporal darkness", type = "VOID", text_color = "#GREY#",
	kr_name = "시간의 어둠",
	projector = function(src, x, y, type, dam)
		DamageType:get(DamageType.TEMPORAL).projector(src, x, y, DamageType.TEMPORAL, dam / 2)
		DamageType:get(DamageType.DARKNESS).projector(src, x, y, DamageType.DARKNESS, dam / 2)
	end,
}

-- Gravity damage types
newDamageType{
	name = "gravity", type = "GRAVITY",
	kr_name = "중력",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if not target then return end
		if target and target:attr("never_move") then
			dam = dam * 1.5
		end
		DamageType:get(DamageType.PHYSICAL).projector(src, x, y, DamageType.PHYSICAL, dam)
	end,
}

newDamageType{
	name = "gravity pin", type = "GRAVITYPIN",
	kr_name = "속박의 중력",
	projector = function(src, x, y, type, dam)
		DamageType:get(DamageType.PHYSICAL).projector(src, x, y, DamageType.PHYSICAL, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		local reapplied = false
		if target then
			-- silence the apply message if the target already has the effect
			for eff_id, p in pairs(target.tmp) do
				local e = target.tempeffect_def[eff_id]
				if e.desc == "땅에 속박되었습니다." then
					reapplied = true
				end
			end
			if target:canBe("pin") then
				target:setEffect(target.EFF_PINNED, 2, {apply_power=src:combatSpellpower(), min_dur=1}, reapplied)
			else
				game.logSeen(target, "%s 속박을 저항했습니다.", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}

newDamageType{
	name = "physical repulsion", type = "REPULSION",
	kr_name = "물리적 반발력",
	projector = function(src, x, y, type, dam, tmp)
		local target = game.level.map(x, y, Map.ACTOR)
		tmp = tmp or {}
		-- extra damage on pinned targets
		if target and target:attr("never_move") then
			dam = dam * 1.5
		end
		DamageType:get(DamageType.PHYSICAL).projector(src, x, y, DamageType.PHYSICAL, dam) -- This damage type can deal damage multiple times, use with accordingly
		-- check knockback
		if target and not target:attr("never_move") and not tmp[target] then
			tmp[target] = true
			if target:checkHit(src:combatSpellpower(), target:combatPhysicalResist(), 0, 95, 15) and target:canBe("knockback") then
				target:knockback(src.x, src.y, 2)
				target:crossTierEffect(target.EFF_OFFBALANCE, src:combatSpellpower())
				game.logSeen(target, "%s 밀려났습니다.", (target.kr_name or target.name):capitalize():addJosa("가"))
			else
				game.logSeen(target, "%s 밀려나지 않았습니다.", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}

newDamageType{
	name = "grow", type = "GROW",
	kr_name = "성장",
	projector = function(src, x, y, typ, dam)
		local feat = game.level.map(x, y, Map.TERRAIN)
		if feat then
			if feat.grow then
				local newfeat_name, newfeat, silence = feat.grow, nil, false
				if type(feat.dig) == "function" then newfeat_name, newfeat, silence = feat.grow(src, x, y, feat) end
				newfeat = newfeat or game.zone.grid_list[newfeat_name]
				if newfeat then
					game.level.map(x, y, Map.TERRAIN, newfeat)
					if not silence then
						local nfn = (newfeat and (newfeat.kr_name or newfeat.name)) or (game.zone.grid_list[newfeat_name].kr_name or game.zone.grid_list[newfeat_name].name) --@ 다음줄 사용 : 너무 길어져서 변수로 뺌
						game.logSeen({x=x,y=y}, "%s %s 변했습니다.", (feat.kr_name or feat.name):capitalize():addJosa("가"), nfn:addJosa("로"))
					end
				end
			end
		end
	end,
}

-- Mosses
newDamageType{
	name = "pinning nature", type = "GRASPING_MOSS",
	kr_name = "고정시키는 자연",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and src:reactionToward(target) < 0 then
			DamageType:get(DamageType.NATURE).projector(src, x, y, DamageType.NATURE, dam.dam)
			target:setEffect(target.EFF_SLOW_MOVE, 4, {apply_power=src:combatMindpower(), power=dam.slow/100}, true)
			if target:canBe("pin") and rng.percent(dam.pin) then
				target:setEffect(target.EFF_PINNED, 4, {apply_power=src:combatMindpower()}, true)
			else
				game.logSeen(target, "%s 저항했습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}

newDamageType{
	name = "healing nature", type = "NOURISHING_MOSS",
	kr_name = "회복시키는 자연",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and src:reactionToward(target) < 0 then
			local realdam = DamageType:get(DamageType.NATURE).projector(src, x, y, DamageType.NATURE, dam.dam)
			if realdam > 0 then src:heal(realdam * dam.factor, target) end
		end
	end,
}

newDamageType{
	name = "impeding nature", type = "SLIPPERY_MOSS",
	kr_name = "방해하는 자연",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and src:reactionToward(target) < 0 then
			DamageType:get(DamageType.NATURE).projector(src, x, y, DamageType.NATURE, dam.dam)
			target:setEffect(target.EFF_SLIPPERY_MOSS, 2, {apply_power=src:combatMindpower(), fail=dam.fail}, true)
		end
	end,
}

newDamageType{
	name = "confounding nature", type = "HALLUCINOGENIC_MOSS",
	kr_name = "혼란시키는 자연",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and src:reactionToward(target) < 0 then
			DamageType:get(DamageType.NATURE).projector(src, x, y, DamageType.NATURE, dam.dam)
			if target:canBe("confusion") and rng.percent(dam.chance) then
				target:setEffect(target.EFF_CONFUSED, 2, {apply_power=src:combatMindpower(), power=dam.power}, true)
			else
				game.logSeen(target, "%s 저항했습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}

-- Circles
newDamageType{
	name = "sanctity", type = "SANCTITY",
	kr_name = "신성",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			if target == src then
				target:setEffect(target.EFF_SANCTITY, 1, {power=dam, no_ct_effect=true})
			elseif target:canBe("silence") then
				target:setEffect(target.EFF_SILENCED, 2, {apply_power=src:combatSpellpower(), min_dur=1}, true)
			else
				game.logSeen(target, "%s 저항했습니다.", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}

newDamageType{
	name = "defensive darkness", type = "SHIFTINGSHADOWS",
	kr_name = "방어적 그림자",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			if target == src then
				target:setEffect(target.EFF_SHIFTING_SHADOWS, 1, {power= dam, no_ct_effect=true})
			else
				DamageType:get(DamageType.DARKNESS).projector(src, x, y, DamageType.DARKNESS, dam)
			end
		end
	end,
}

newDamageType{
	name = "blazing light", type = "BLAZINGLIGHT",
	kr_name = "타오르는 빛",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			if target == src then
				target:setEffect(target.EFF_BLAZING_LIGHT, 1, {power= 1 + (dam / 4), no_ct_effect=true})
			else
				DamageType:get(DamageType.FIRE).projector(src, x, y, DamageType.FIRE, dam)
				DamageType:get(DamageType.LIGHT).projector(src, x, y, DamageType.LIGHT, dam)
			end
		end
	end,
}

newDamageType{
	name = "prismatic repulsion", type = "WARDING",
	kr_name = "무지개빛 파동",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			if target == src then
				target:setEffect(target.EFF_WARDING, 1, {power=dam*5, no_ct_effect=true})
			elseif target ~= src then
				DamageType:get(DamageType.LIGHT).projector(src, x, y, DamageType.LIGHT, dam )
				DamageType:get(DamageType.DARKNESS).projector(src, x, y, DamageType.DARKNESS, dam)
				if target:checkHit(src:combatSpellpower(), target:combatPhysicalResist(), 0, 95, 15) and target:canBe("knockback") then
					target:knockback(src.x, src.y, 1)
					target:crossTierEffect(target.EFF_OFFBALANCE, src:combatSpellpower())
					game.logSeen(target, "%s 밀려났습니다.", (target.kr_name or target.name):capitalize():addJosa("가"))
				else
					game.logSeen(target, "%s 밀려나지 않았습니다.", (target.kr_name or target.name):capitalize():addJosa("가"))
				end
			end
		end
	end,
}

newDamageType{
	name = "mind slow", type = "MINDSLOW",
	kr_name = "정신적 감속",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			local sx, sy = game.level.map:getTileToScreen(x, y)
			target:setEffect(target.EFF_SLOW, 4, {power=dam, apply_power=src:combatMindpower()})
		end
	end,
}

-- Freezes target, checks for physresistance
newDamageType{
	name = "mind freeze", type = "MINDFREEZE",
	kr_name = "정신적 빙결",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			-- Freeze it, if we pass the test
			local sx, sy = game.level.map:getTileToScreen(x, y)
			if target:canBe("stun") then
				target:setEffect(target.EFF_FROZEN, dam, {hp=70 + src:combatMindpower() * 10, apply_power=src:combatMindpower()})
			else
				game.logSeen(target, "%s 저항했습니다.", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}

newDamageType{
	name = "implosion", type = "IMPLOSION",
	kr_name = "파열",
	projector = function(src, x, y, type, dam)
		local dur = 3
		local perc = 50
		if _G.type(dam) == "table" then dam, dur, perc = dam.dam, dam.dur, (dam.initial or perc) end
		local init_dam = dam
		if init_dam > 0 then DamageType:get(DamageType.PHYSICAL).projector(src, x, y, DamageType.PHYSICAL, init_dam) end
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			target:setEffect(target.EFF_IMPLODING, dur, {src=src, power=dam})
		end
	end,
}

-- Temporal + Stat damage
newDamageType{
	name = "regressive temporal", type = "CLOCK",
	kr_name = "시간 역행",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			local dam = 2 + math.ceil(dam / 15)
			target:setEffect(target.EFF_TURN_BACK_THE_CLOCK, 3, {power=dam, apply_power=src:combatSpellpower(), min_dur=1})
		end
		-- Reduce Con then deal the damage
		DamageType:get(DamageType.TEMPORAL).projector(src, x, y, DamageType.TEMPORAL, dam)
	end,
}

-- Temporal Over Time
newDamageType{
	name = "wasting temporal", type = "WASTING", text_color = "#LIGHT_STEEL_BLUE#",
	kr_name = "시간 낭비",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		local dur = 3
		local perc = 30
		if _G.type(dam) == "table" then dam, dur, perc = dam.dam, dam.dur, (dam.initial or perc) end
		local init_dam = dam * perc / 100
		if init_dam > 0 then DamageType:get(DamageType.TEMPORAL).projector(src, x, y, DamageType.TEMPORAL, init_dam) end
		if target then
			-- Set wasting effect
			dam = dam - init_dam
			target:setEffect(target.EFF_WASTING, dur, {src=src, power=dam / dur, no_ct_effect=true})
		end
		return init_dam
	end,
}

newDamageType{
	name = "stop", type = "STOP",
	kr_name = "정지",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			if target:canBe("stun") then
				target:setEffect(target.EFF_STUNNED, dam, {apply_power=src:combatSpellpower()})
			else
				game.logSeen(target, "%s 멈추지 않습니다.", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}

newDamageType{
	name = "debilitating temporal", type = "RETHREAD",
	kr_name = "쇠약의 시간",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		local chance = rng.range(1, 4)
		-- Pull random effect
		if target then
			if src then src:incParadox(-dam.reduction) end
			
			if chance == 1 then
				if target:canBe("stun") then
					target:setEffect(target.EFF_STUNNED, 3, {apply_power=src:combatSpellpower()})
				else
					game.logSeen(target, "%s 기절하지 않았습니다.", (target.kr_name or target.name):capitalize():addJosa("가"))
				end
			elseif chance == 2 then
				if target:canBe("blind") then
					target:setEffect(target.EFF_BLINDED, 3, {apply_power=src:combatSpellpower()})
				else
					game.logSeen(target, "%s 실명되지 않았습니다.", (target.kr_name or target.name):capitalize():addJosa("가"))
				end
			elseif chance == 3 then
				if target:checkHit(src:combatSpellpower(), target:combatPhysicalResist(), 0, 95, 15) and target:canBe("pin") then
					target:setEffect(target.EFF_PINNED, 3, {apply_power=src:combatSpellpower()})
				else
					game.logSeen(target, "%s 속박되지 않았습니다.", (target.kr_name or target.name):capitalize():addJosa("가"))
				end
			elseif chance == 4 then
				if target:canBe("confusion") then
					target:setEffect(target.EFF_CONFUSED, 3, {power=50, apply_power=src:combatSpellpower()})
				else
					game.logSeen(target, "%s 혼란 효과를 저항했습니다.", (target.kr_name or target.name):capitalize():addJosa("가"))
				end
			end
		end
		-- deal damage last so we get paradox from each target
		DamageType:get(DamageType.TEMPORAL).projector(src, x, y, DamageType.TEMPORAL, dam.dam)
	end,
}

newDamageType{
	name = "temporal echo", type = "TEMPORAL_ECHO",
	kr_name = "시간의 메아리",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			dam = (target.max_life - target.life) * dam
			DamageType:get(DamageType.TEMPORAL).projector(src, x, y, DamageType.TEMPORAL, dam)
		end
	end,
}

newDamageType{
	name = "draining physical", type = "DEVOUR_LIFE",
	kr_name = "물리적 흡수",
	projector = function(src, x, y, type, dam)
		if _G.type(dam) == "number" then dam = {dam=dam} end
		local target = game.level.map(x, y, Map.ACTOR) -- Get the target first to make sure we heal even on kill
		if target then dam.dam = math.max(0, math.min(target.life, dam.dam)) end
		local realdam = DamageType:get(DamageType.PHYSICAL).projector(src, x, y, DamageType.PHYSICAL, dam.dam)
		if target and realdam > 0 then
			local heal = realdam * (dam.healfactor or 1)
			-- cannot be reduced
			local temp = src.healing_factor
			src.healing_factor = 1
			src:heal(heal, target)
			src.healing_factor = temp
			src:logCombat(target, "#Source1# #Target#의 생명력 %d 만큼을 먹어치웠습니다!", heal)
		end
	end,
	hideMessage=true,
}

newDamageType{
	name = "temporal slow", type = "CHRONOSLOW",
	kr_name = "감속의 시간",
	projector = function(src, x, y, type, dam)
		DamageType:get(DamageType.TEMPORAL).projector(src, x, y, DamageType.TEMPORAL, dam.dam)
		local target = game.level.map(x, y, Map.ACTOR)
		local reapplied = false
		if target then
			-- silence the apply message if the target already has the effect
			for eff_id, p in pairs(target.tmp) do
				local e = target.tempeffect_def[eff_id]
				if e.desc == "Slow" then
					reapplied = true
				end
			end
			target:setEffect(target.EFF_SLOW, 3, {power=dam.slow, apply_power=src:combatSpellpower()}, reapplied)
		end
	end,
}

newDamageType{
	name = "molten rock", type = "MOLTENROCK",
	kr_name = "용해된 바위",
	projector = function(src, x, y, type, dam)
		return DamageType:get(DamageType.FIRE).projector(src, x, y, DamageType.FIRE, dam / 2) +
		       DamageType:get(DamageType.PHYSICAL).projector(src, x, y, DamageType.PHYSICAL, dam / 2)
	end,
}

newDamageType{
	name = "entangle", type = "ENTANGLE",
	kr_name = "얽어매기",
	projector = function(src, x, y, type, dam)
		DamageType:get(DamageType.PHYSICAL).projector(src, x, y, DamageType.PHYSICAL, dam/3)
		DamageType:get(DamageType.NATURE).projector(src, x, y, DamageType.NATURE, 2*dam/3)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			if target:canBe("pin") then
				target:setEffect(target.EFF_PINNED, 5, {no_ct_effect=true})
			else
				game.logSeen(target, "%s 저항했습니다.", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}

newDamageType{
	name = "manaworm arcane", type = "MANAWORM",
	kr_name = "마법의 마나 벌레",
	projector = function(src, x, y, type, dam)
		local realdam = DamageType:get(DamageType.ARCANE).projector(src, x, y, DamageType.ARCANE, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			if game.zone.void_blast_hits and game.party:hasMember(target) then game.zone.void_blast_hits = game.zone.void_blast_hits + 1 end

			if target:knowTalent(target.T_MANA_POOL) then
				target:setEffect(target.EFF_MANAWORM, 5, {power=dam * 5, src=src, no_ct_effect=true})
				src:disappear(src)
			else
				game.logSeen(target, "%s 아무런 영향을 받지 않습니다.", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
		return realdam
	end,
}

newDamageType{
	name = "arcane blast", type = "VOID_BLAST",
	kr_name = "마력 돌풍",
	projector = function(src, x, y, type, dam)
		local realdam = DamageType:get(DamageType.ARCANE).projector(src, x, y, DamageType.ARCANE, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if game.zone.void_blast_hits and target and game.party:hasMember(target) then
			game.zone.void_blast_hits = game.zone.void_blast_hits + 1
		end
		return realdam
	end,
}

newDamageType{
	name = "circle of death", type = "CIRCLE_DEATH",
	kr_name = "죽음의 고리",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and (src:reactionToward(target) < 0 or dam.ff) then
			for eff_id, p in pairs(target.tmp) do
				local e = target.tempeffect_def[eff_id]
				if e.subtype.bane then return end
			end

			local what = rng.percent(50) and "blind" or "confusion"
			if target:canBe(what) then
				target:setEffect(what == "blind" and target.EFF_BANE_BLINDED or target.EFF_BANE_CONFUSED, math.ceil(dam.dur), {src=src, power=50, dam=dam.dam, apply_power=src:combatSpellpower()})
			else
				game.logSeen(target, "%s 파멸을 저항했습니다.", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}

-- Darkness damage + speed reduction + minion damage inc
newDamageType{
	name = "decaying darkness", type = "RIGOR_MORTIS",
	kr_name = "부패하는 어둠",
	projector = function(src, x, y, type, dam, tmp)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			DamageType:get(DamageType.DARKNESS).projector(src, x, y, DamageType.DARKNESS, dam.dam)
			target:setEffect(target.EFF_SLOW, dam.dur, {power=dam.speed, apply_power=src:combatSpellpower()})
			target:setEffect(target.EFF_RIGOR_MORTIS, dam.dur, {power=dam.minion, apply_power=src:combatSpellpower()})
		end
	end,
}

newDamageType{
	name = "abyssal darkness", type = "ABYSSAL_SHROUD",
	kr_name = "심연의 어둠",
	projector = function(src, x, y, type, dam)
		--make it dark
		game.level.map.remembers(x, y, false)
		game.level.map.lites(x, y, false)

		local target = game.level.map(x, y, Map.ACTOR)
		local reapplied = false
		if target then
			-- silence the apply message it if the target already has the effect
			for eff_id, p in pairs(target.tmp) do
				local e = target.tempeffect_def[eff_id]
				if e.desc == "Abyssal Shroud" then --@ 번역하는 부분 아님
					reapplied = true
				end
			end
			target:setEffect(target.EFF_ABYSSAL_SHROUD, 2, {power=dam.power, lite=dam.lite, apply_power=src:combatSpellpower(), min_dur=1}, reapplied)
			DamageType:get(DamageType.DARKNESS).projector(src, x, y, DamageType.DARKNESS, dam.dam)
		end
	end,
}

newDamageType{
	name = "% chance to summon an orc spirit", type = "GARKUL_INVOKE",
	kr_name = "% 확률로 오크 정신체 소환",
	projector = function(src, x, y, type, dam)
		if not rng.percent(dam) then return end
		local target = game.level.map(x, y, engine.Map.ACTOR)
		if not target then return end

		if game.party:hasMember(src) and game.party:findMember{type="garkul spirit"} then return end

		-- Find space
		local x, y = util.findFreeGrid(src.x, src.y, 5, true, {[engine.Map.ACTOR]=true})
		if not x then return end

		print("Invoking garkul spirit on", x, y)

		local NPC = require "mod.class.NPC"
		local orc = NPC.new{
			type = "humanoid", subtype = "orc",
			display = "o", color=colors.UMBER,
			combat = { dam=resolvers.rngavg(5,12), atk=2, apr=6, physspeed=2 },
			body = { INVEN = 10, MAINHAND=1, OFFHAND=1, BODY=1, QUIVER=1 },
			infravision = 10,
			lite = 1,
			rank = 2,
			size_category = 3,
			resolvers.racial(),
			resolvers.sustains_at_birth(),
			autolevel = "warrior",
			ai = "summoned", ai_real = "dumb_talented_simple", ai_state = { ai_move="move_complex", talent_in=2, },
			stats = { str=20, dex=8, mag=6, con=16 },
			name = "orc spirit", color=colors.SALMON, image = "npc/humanoid_orc_orc_berserker.png",
			kr_name = "오크 영혼",
			desc = [[무거운 갑옷을 입고 거대한 도끼를 든 오크입니다.]],
			level_range = {35, nil}, exp_worth = 0,
			max_life = resolvers.rngavg(110,120), life_rating = 12,
			resolvers.equip{
				{type="weapon", subtype="battleaxe", autoreq=true},
				{type="armor", subtype="massive", autoreq=true},
			},
			combat_armor = 0, combat_def = 5,

			resolvers.talents{
				[src.T_ARMOUR_TRAINING]={base=2, every=10, max=4},
				[src.T_WEAPON_COMBAT]={base=2, every=10, max=4},
				[src.T_WEAPONS_MASTERY]={base=2, every=10, max=4},
				[src.T_RUSH]={base=3, every=7, max=6},
				[src.T_STUNNING_BLOW]={base=3, every=7, max=6},
				[src.T_BERSERKER]={base=3, every=7, max=6},
			},

			faction = src.faction,
			summoner = src,
			summon_time = 6,
		}

		orc:resolve() orc:resolve(nil, true)
		game.zone:addEntity(game.level, orc, "actor", x, y)
		orc:forceLevelup(src.level)

		orc.remove_from_party_on_death = true
		game.party:addMember(orc, {control="no", type="garkul spirit", title="Garkul Spirit", kr_title="가르쿨의 영혼"})
		orc:setTarget(target)
	end,
}

-- speed reduction, hateful whisper
newDamageType{
	name = "nightmare", type = "NIGHTMARE",
	kr_name = "악몽",
	projector = function(src, x, y, type, dam, tmp)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and src:reactionToward(target) < 0 then
			if rng.chance(10) and not target:hasEffect(target.EFF_HATEFUL_WHISPER) then
				src:forceUseTalent(src.T_HATEFUL_WHISPER, {ignore_cd=true, ignore_energy=true, force_target=target, force_level=1, ignore_ressources=true})
			end

			if rng.chance(30) then
				target:setEffect(target.EFF_SLOW, 3, {power=0.3})
			end
		end
	end,
}

newDamageType{
	name = "weakness", type = "WEAKNESS",
	kr_name = "약화",
	projector = function(src, x, y, type, dam, tmp)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			local reapplied = target:hasEffect(target.EFF_WEAKENED)
			target:setEffect(target.EFF_WEAKENED, dam.dur, { power=dam.incDamage }, reapplied)
		end
	end,
}

-- Generic apply temporary effect
newDamageType{
	name = "special effect", type = "TEMP_EFFECT",
	kr_name = "특수한 효과",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			local ok = false
			if dam.friends then if src:reactionToward(target) >= 0 then ok = true end
			elseif dam.foes then if src:reactionToward(target) < 0 then ok = true end
			else ok = true
			end
			if ok and (not dam.check_immune or target:canBe(dam.check_immune)) then target:setEffect(dam.eff, dam.dur, table.clone(dam.p)) end
		end
	end,
}

newDamageType{
	name = "manaburn arcane", type = "MANABURN", text_color = "#PURPLE#",
	kr_name = "마법적 마나 태우기",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			local mana = dam
			local vim = dam / 2
			local positive = dam / 4
			local negative = dam / 4

			mana = math.min(target:getMana(), mana)
			vim = math.min(target:getVim(), vim)
			positive = math.min(target:getPositive(), positive)
			negative = math.min(target:getNegative(), negative)

			target:incMana(-mana)
			target:incVim(-vim)
			target:incPositive(-positive)
			target:incNegative(-negative)

			local dam = math.max(mana, vim * 2, positive * 4, negative * 4)
			return DamageType:get(DamageType.ARCANE).projector(src, x, y, DamageType.ARCANE, dam)
		end
		return 0
	end,
}

newDamageType{
	name = "leaves", type = "LEAVES",
	kr_name = "나뭇잎",
	projector = function(src, x, y, type, dam, tmp)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			if src:reactionToward(target) < 0 then
				if target:canBe("cut") then
					local reapplied = target:hasEffect(target.EFF_CUT)
					target:setEffect(target.EFF_CUT, 2, { power=dam.dam, src=src }, reapplied)
				end
			else
				local reapplied = target:hasEffect(target.EFF_LEAVES_COVER)
				target:setEffect(target.EFF_LEAVES_COVER, 1, { power=dam.chance }, reapplied)
			end
		end
	end,
}

-- Distortion; Includes knockback, penetrate, stun, and explosion paramters
newDamageType{
	name = "distorting physical", type = "DISTORTION",
	kr_name = "물리적 왜곡",
	projector = function(src, x, y, type, dam, tmp)
		local target = game.level.map(x, y, Map.ACTOR)
		if not target then return end
		tmp = tmp or {}
		if target and not tmp[target] then
			tmp[target] = true
			local old_pen = 0
			
			game.level.map:particleEmitter(x, y, 1, "distortion")
			
			-- Spike resists pen
			if dam.penetrate then
				old_pen = src.resists_pen and src.resists_pen[engine.DamageType.PHYSICAL] or 0
				src.resists_pen[engine.DamageType.PHYSICAL] = 100
			end
			-- Handle distortion effects
			if target:hasEffect(target.EFF_DISTORTION) then
				-- Explosive?
				if dam.explosion then
					src:project({type="ball", target.x, target.y, radius=dam.radius, friendlyfire=dam.friendlyfire}, target.x, target.y, engine.DamageType.DISTORTION, {dam=src:mindCrit(dam.explosion), power=dam.distort or 0})
					game.level.map:particleEmitter(target.x, target.y, dam.radius, "generic_blast", {radius=dam.radius, tx=target.x, ty=target.y, rm=255, rM=255, gm=180, gM=255, bm=180, bM=255, am=35, aM=90})
					dam.explosion_done = true
				end
				-- Stun?
				if dam.stun then
					dam.do_stun = true
				end
			end
			-- Our damage
			target:setEffect(target.EFF_DISTORTION, 2, {power=dam.distort or 0})
			if not dam.explosion_done then
				DamageType:get(DamageType.PHYSICAL).projector(src, x, y, DamageType.PHYSICAL, dam.dam)
			end
			-- Do knockback
			if dam.knockback then
				if target:checkHit(src:combatMindpower(), target:combatPhysicalResist(), 0, 95, 15) and target:canBe("knockback") then
					target:knockback(src.x, src.y, dam.knockback)
					target:crossTierEffect(target.EFF_OFFBALANCE, src:combatMindpower())
					game.logSeen(target, "%s 밀려났습니다.", (target.kr_name or target.name):capitalize():addJosa("가"))
				else
					game.logSeen(target, "%s 밀려나지 않았습니다.", (target.kr_name or target.name):capitalize():addJosa("가"))
				end
			end
			-- Do stun
			if dam.do_stun then
				if target:canBe("stun") then
					target:setEffect(target.EFF_STUNNED, dam.stun, {apply_power=src:combatMindpower()})
				else
					game.logSeen(target, "%s 기절하지 않았습니다.", (target.kr_name or target.name):capitalize():addJosa("가"))
				end
			end
			-- Reset resists pen
			if dam.penetrate then
				src.resists_pen[engine.DamageType.PHYSICAL] = old_pen
			end
		end
	end,
}

-- Mind/Fire damage with lots of parameter options
newDamageType{
	name = "dreamforge", type = "DREAMFORGE",
	kr_name = "꿈의 연마",
	projector = function(src, x, y, type, dam, tmp)
		local target = game.level.map(x, y, Map.ACTOR)
		if not target then return end
		local power, dur, chance, dist, fail, do_particles
		tmp = tmp or {}
		if _G.type(dam) == "table" then dam, power, dur, chance, fail, dist, do_particles = dam.dam, dam.power, dam.dur, dam.chance, dam.fail, dam.dist, dam.do_particles end
		if target and not tmp[target] then
			if src:checkHit(src:combatMindpower(), target:combatMentalResist(), 0, 95) then
				DamageType:get(DamageType.MIND).projector(src, x, y, DamageType.MIND, {dam=dam/2, alwaysHit=true})
				DamageType:get(DamageType.FIREBURN).projector(src, x, y, DamageType.FIREBURN, dam/2)
				if power and power > 0 then
					local silent = true and target:hasEffect(target.EFF_BROKEN_DREAM) or false
					target:setEffect(target.EFF_BROKEN_DREAM, dur, {power=power, fail=fail}, silent)
					if rng.percent(chance) then
						target:crossTierEffect(target.EFF_BRAINLOCKED, src:combatMindpower())
					end
				end
				-- Do knockback
				if dist then
					if target:canBe("knockback") then
						target:knockback(src.x, src.y, dist)
						target:crossTierEffect(target.EFF_OFFBALANCE, src:combatMindpower())
						game.logSeen(target, "%s 밀려났습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
					else
						game.logSeen(target, "%s 연마의 굉음을 저항했습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
					end
				end
				if do_particles then
					if rng.percent(50) then
						game.level.map:particleEmitter(target.x, target.y, 1, "generic_discharge", {rm=225, rM=255, gm=160, gM=160, bm=0, bM=0, am=35, aM=90})
					elseif hit then
						game.level.map:particleEmitter(target.x, target.y, 1, "generic_discharge", {rm=225, rM=255, gm=225, gM=255, bm=255, bM=255, am=35, aM=90})
					end
				end
			else -- Save for half damage
				DamageType:get(DamageType.MIND).projector(src, x, y, DamageType.MIND, {dam=dam/4, alwaysHit=true})
				DamageType:get(DamageType.FIREBURN).projector(src, x, y, DamageType.FIREBURN, dam/4)
				game.logSeen(target, "%s 꿈의 연마를 저항했습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
	end,
}


newDamageType{
	name = "natural mucus", type = "MUCUS",
	kr_name = "점액",
	projector = function(src, x, y, type, dam, tmp)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and not target.turn_procs.mucus then
			target.turn_procs.mucus = true
			if src:reactionToward(target) >= 0 then
				if src == target then
					target:incEquilibrium(-(dam.self_equi or 1))
				else
					target:incEquilibrium(-(dam.equi or 1))
					src:incEquilibrium(-(dam.equi or 1))
				end
			elseif target:canBe("poison") then
				target:setEffect(target.EFF_POISONED, 5, {src=src, power=dam.dam, max_power = dam.dam*5, apply_power=src:combatMindpower()})
			end
		elseif not target and not src.turn_procs.living_mucus and src:knowTalent(src.T_LIVING_MUCUS) and game.zone and not game.zone.wilderness then
			src.turn_procs.living_mucus = true
			local t = src:getTalentFromId(src.T_LIVING_MUCUS)
			if rng.percent(t.getChance(src, t)) then
				t.spawn(src, t)
			end
		end
	end,
}

newDamageType{
	name = "disarming acid", type = "ACID_DISARM", text_color = "#GREEN#",
	kr_name = "산성 무장해제",
	projector = function(src, x, y, type, dam)
		if _G.type(dam) == "number" then dam = {chance=25, dam=dam} end
		local realdam = DamageType:get(DamageType.ACID).projector(src, x, y, DamageType.ACID, dam.dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and rng.percent(dam.chance) then
			if target:canBe("disarm") then
				target:setEffect(target.EFF_DISARMED, dam.dur or 3, {src=src, apply_power=src:combatMindpower()})
			else
				game.logSeen(target, "%s 저항했습니다.", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
		end
		return realdam
	end,
}

-- Acid damage + Accuracy/Defense/Armor Down Corrosion
newDamageType{
	name = "corrosive acid", type = "ACID_CORRODE",
	kr_name = "산성 부식",
	projector = function(src, x, y, type, dam, tmp)
		if _G.type(dam) == "number" then dam = {dur = 4, armor = dam/2, defense = dam/2, dam = dam, atk=dam/2} end
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			DamageType:get(DamageType.ACID).projector(src, x, y, DamageType.ACID, dam.dam)
			target:setEffect(target.EFF_CORRODE, dam.dur, {atk=dam.atk, armor=dam.armor, defense=dam.defense, apply_power=src:combatMindpower()})
		end
	end,
}

-- Bouncy slime!
newDamageType{
	name = "bouncing slime", type = "BOUNCE_SLIME",
	kr_name = "활발한 슬라임",
	projector = function(src, x, y, type, dam, tmp, _, tg)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			local realdam = DamageType:get(DamageType.SLIME).projector(src, x, y, DamageType.SLIME, {dam=dam.dam, power=0.30})

			if dam.nb > 0 then
				dam.done = dam.done or {}
				dam.done[target.uid] = true
				dam.nb = dam.nb - 1
				dam.dam = dam.dam*(dam.bounce_factor or 0.5) -- lose 50% damage by default
				local list = {}
				src:project({type="ball", selffire=false, x=x, y=y, radius=6, range=0}, x, y, function(bx, by)
					local actor = game.level.map(bx, by, Map.ACTOR)
					if actor and not dam.done[actor.uid] and src:reactionToward(actor) < 0 then
						print("[BounceSlime] found possible actor", actor.name, bx, by, "distance", core.fov.distance(x, y, bx, by))
						list[#list+1] = actor
					end
				end)
				if #list > 0 then
					local st = rng.table(list)
					src:projectile({type="bolt", range=6, x=x, y=y, speed = tg.speed or 6, name=tg.name or "bouncing slime", kr_name=tg.kr_name or tg.name or "활발한 슬라임", selffire=false, display={particle="bolt_slime"}}, st.x, st.y, DamageType.BOUNCE_SLIME, dam, {type="slime"})
				end
			end
			return realdam
		end
	end,
}

-- Acid damage + Slow
newDamageType{
	name = "caustic mire", type = "CAUSTIC_MIRE",
	kr_name = "부식성 늪",
	projector = function(src, x, y, type, dam, tmp)
		if _G.type(dam) == "number" then dam = {dur = 2, slow=20} end
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			DamageType:get(DamageType.ACID).projector(src, x, y, DamageType.ACID, dam.dam)
			target:setEffect(target.EFF_SLOW, dam.dur, {power=dam.slow/100, apply_power=src:combatSpellpower()})
		end
	end,
}

-- Sun Path damage
newDamageType{
	name = "sun path", type = "SUN_PATH",
	kr_name = "태양의 길",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and src:reactionToward(target) < 0 then
			return DamageType:get(DamageType.LIGHT).projector(src, x, y, DamageType.LIGHT, dam)
		end
	end,
}

newDamageType{
	name = "telekinetic shove", type = "TK_PUSHPIN",
	kr_name = "염동력 압박",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			target:knockback(src.x, src.y, dam.push, nil, function(g, x, y)
				if game.level.map:checkEntity(x, y, Map.TERRAIN, "block_move", target) then
					DamageType:get(DamageType.PHYSICAL).projector(src, target.x, target.y, DamageType.PHYSICAL, dam.dam)
					if target:canBe("pin") then
						target:setEffect(target.EFF_PINNED, dam.dur, {apply_power=src:combatMindpower()})
					else
						game.logSeen(src, "%s 속박을 저항했습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
					end
				end
			end)
			return dam.dam
		end
	end,
}

newDamageType{
	name = "brain storm", type = "BRAINSTORM",
	kr_name = "뇌파 폭풍",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target then
			DamageType:get(DamageType.LIGHTNING).projector(src, target.x, target.y, DamageType.LIGHTNING, dam)
			if target:checkHit(src:combatMindpower(), target:combatMentalResist(), 0, 95, 15) then
				target:crossTierEffect(target.EFF_BRAINLOCKED, src:combatMindpower())
			else
				game.logSeen(target, "%s 정신 공격을 저항했습니다!", (target.kr_name or target.name):capitalize():addJosa("가"))
			end
			
			if src:hasEffect(src.EFF_TRANSCENDENT_TELEKINESIS) then
				if target:canBe("blind") then
					target:setEffect(target.EFF_BLINDED, 4, {apply_power=src:combatMindpower()})
				end
			end
			return dam
		end
	end,
}

newDamageType{
	name = "static net", type = "STATIC_NET",
	kr_name = "정전기 망",
	projector = function(src, x, y, type, dam)
		local target = game.level.map(x, y, Map.ACTOR)
		if target and src:reactionToward(target) < 0 then
			DamageType:get(DamageType.LIGHTNING).projector(src, x, y, DamageType.LIGHTNING, dam.dam)
			target:setEffect(target.EFF_SLOW, 4, {apply_power=src:combatMindpower(), power=dam.slow/100}, true)
		elseif target == src then
			target:setEffect(target.EFF_STATIC_CHARGE, 4, {power=dam.weapon}, true)
		end
	end,
}
