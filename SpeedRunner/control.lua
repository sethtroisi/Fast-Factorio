--	player.cancel_crafting{index=last_craft.index, count=last_craft.count}
--  player.begin_crafting{count=next_craft.count, recipe=next_craft.recipe, silent=False}

function action_check(player)
	local pos = player.position

    if game.tick < global.next_check then
        return
    end

    if #global.action_queue == 0 then
        return
    end
    
    action = global.action_queue[1]

    if action.cmd == "run_to" then
        if run_to(player, action.run_goal) then
            table.remove(global.action_queue, 0)
        else
            -- Should try to do things along the way (like craft)
            return
        end
    end




    -- pos.x, pos.y
    -- game.tick

--				if builder.get_item_count(item.name) >= item.count then
--						builder.remove_item({name=item.name, count=item.count})

--			if builder.mine_entity(ent) then
-- 			local products = ent.prototype.mineable_properties.products			
--			if products then
--				-- game.print("Products: " .. ent.line(products))
--				for key, value in pairs(products) do
--					inserted = builder.insert({name=value.name, count=math.random(value.amount_min, value.amount_max)})
--				end
--			end
--			ent.destroy()

--			tile = ent.surface.get_tile(ent.position)
			--game.print(ent.prototype.mineable_properties)
--			builder.mine_tile(tile)


end


-------------------
----- Helpers -----
-------------------

function run_to(player, goal)
    local deltaX = goal.x - player.position.x
    local deltaY = goal.y - player.position.y
    local err = 1

    if math.abs(deltaX) < err and math.abs(deltaY) < err then
        return true
    end

    dir = defines.direction.north
    if deltaY > err and deltaX > err then
        dir = defines.direction.southeast
    elseif deltaY > err and deltaX < -err then
        dir = defines.direction.southwest
    elseif deltaY > err then
        dir = defines.direction.south
    elseif deltaY < -err and deltaX > err then
        dir = defines.direction.northeast
    elseif deltaY < -err and deltaX < -err then
        dir = defines.direction.northwest
    elseif deltaY < -err then
        dir = defines.direction.north
    elseif deltaX > err then
        dir = defines.direction.east
    elseif deltaX < -err then
        dir = defines.direction.west
    end

    if game.tick % 25 == 0 then
--        game.print(deltaX .. ", " .. deltaY .. "   " .. dir)
    end

    player.walking_state = {walking = true, direction = dir}    

    global.next_check = game.tick + 1
    return false
end

function add_run_to(x, y)
    table.insert(global.action_queue, 1, {cmd="run_to", run_goal={x=x, y=y}})
end

-------------------
------ Setup ------
-------------------

script.on_event("start-stop-speedrun", function(event)
    global.speedrunRunning = not global.speedrunRunning
    game.print((global.speedrunRunning and "Starting" or "Stopping") .. " Speedrun")
    if global.speedrunRunning then
        runOnce()
    end;
end)

function runOnce()
--    global.speedrunRunning = false
	global.speedRunSetupComplete = true

    global.next_check = 0

	if not global.action_queue then
		global.action_queue = {}
	end

    game.print("Adding actions to queue")
    add_run_to(-74, -106)
    
    game.print("Action Queue: " .. #global.action_queue .. " actions")
end

--script.on_load(function()
--	runOnce()
--end)

script.on_event(defines.events.on_tick, function(event)
    if (game.tick > 0 and game.tick % 200 == 0) then
        local pos = game.players[1].position
        game.print(
            "Tick " .. (game.tick / 100)
            .. ", Pos: " .. string.format("%.1f, %.1f", pos.x, pos.y)
            .. ", ActionQueue: " .. #global.action_queue
               .. " top: " .. (#global.action_queue > 0 and global.action_queue[1].cmd or "None")
        )
    end

	if global.speedrunRunning then
		action_check(game.players[1])
	end
end)



-----------

---
    --https://github.com/pkulchenko/serpent


    --script.raise_event(defines.events.on_put_item,
    --    {position=X.position, player_index=builder.index, shift_build=false, built_by_moving=false, direction=X.direction})
    --script.raise_event(defines.events.on_built_entity,
    --    {created_entity=X, player_index=builder.index, tick=game.tick, name="on_built_entity"})
    --script.raise_event(defines.events.on_preplayer_mined_item,
    --    {entity=ent, player_index=builder.index, name="on_preplayer_mined_item"})


	--local areaList = builder.surface.find_entities_filtered{area = searchArea, type = "entity-ghost", force=builder.force }
	--local tileList = builder.surface.find_entities_filtered{area = searchArea, type = "tile-ghost", force=builder.force }
	-- Merge the lists
	-- for key, value in pairs(tileList) do
		-- if not areaList then
			-- areaList = {}
		-- end
		-- table.insert(areaList, value)
	-- end
	-- game.print("Found " .. #areaList .. " ghosts in area.")
---
