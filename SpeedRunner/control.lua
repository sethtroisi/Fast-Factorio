function action_check(player)
	local pos = player.position

    if game.tick < global.next_check then
        return
    end

    if #global.action_queue == 0 then
        return
    end

    action = global.action_queue[1]

    action_handler = {
        run_to = run_to,
        mine_at = mine_at,
        insert_in = insert_in,
        add_craft = add_craft,
    }

    -- TODO set up action handles
    local handler = action_handler[action.cmd]
    if handler then
        if handler(player, action) then
            table.remove(global.action_queue, 1)
        else
            -- Should try to do crafting at the same time?
            return
        end
    end

    if action.cmd == "build_at" then
        if build_at(player, action) then
            table.remove(global.action_queue, 1)
        else
            -- TODO shouldn't happen :/
            -- TODO log more debug
            global.speedrunRunning = false
            game.print("Failed to build_at")
            return
        end
    end

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

function run_to(player, action)
    local goal = action.run_goal

    -- TODO move this under some option
    if false then
        game.players[1].teleport({goal.x, goal.y})
        return true
    end

    local deltaX = goal.x - player.position.x
    local deltaY = goal.y - player.position.y
    local err = 0.5

    if math.abs(deltaX) <= err and math.abs(deltaY) <= err then
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

    if game.tick % 100 == 10 then
        game.print(string.format('    Running: %.1f, %.1f => ', deltaX, deltaY) .. dir)
    end

    player.walking_state = {walking = true, direction = dir}

    global.next_check = game.tick + 1
    return false
end

script.on_event(defines.events.on_player_mined_item, function(event)
	if #global.action_queue > 0 then
	    local action = global.action_queue[1]
	    if action.cmd == "mine_at" then
        	local player = game.players[event.player_index]
        	if not (player and player.valid) then return end

            action.count = action.count - 1
        end
   end
end)


function mine_at(player, action)
    -- TODO add to a setting
    if false then
    	player.insert{name=action.name, count=action.count}
    	return true
    end

    -- # try and find the thing
    -- TODO check we're close? or just add 'run_to?'

    local found = game.surfaces[1].find_entities_filtered{position = action.position, radius=1, type = "resource", limit = 2}
--    game.print(serpent.line(action.loc) .. " " .. action.t .. " found: " .. #found)
    if #found > 0 then
--      Select the thing we are mining
		player.update_selected_entity(found[1].position)
		player.mining_state = {mining = true, position = found[1].position}

--        local tile = player.surface.get_tile(found[1].position.x, found[1].position.y);
--        player.mine_tile(tile)

        -- Decremented in on_player_mined_item
--        action.count = action.count - 1
    end

    return action.count <= 0
end


function build_at(player, action)
    if player.get_item_count(action.name) < 1 then
        return false
    end

    local surface = game.surfaces[1]
    if not surface.can_place_entity{name=action.name, position=action.position, direction=action.orient} then
        return false
    end

	player.remove_item({name=action.name, count=1})
    local t = surface.create_entity{name=action.name, position=action.position, direction=action.orient,
                                    raise_built=true, force=game.forces.player}
    if not t then
        return false
    end

    return true
end

function insert_in(player, action)
--    if player.get_item_count(action.name) < action.count then
--        return false
--    end

--    local found = game.surfaces[1].find_entities_filtered{position={0,0}, radius=200}
--	for key, value in pairs(found) do
--	    if value.type ~= "resource" and value.name ~= "coal" and value.name ~= "stone" and value.name ~= "copper-ore" and value.type ~= "tree" then
--    	    game.print(key .. " " .. value.type .. " " .. value.name .. " " .. serpent.line(value.position))
--    	end
--	end

    local found = game.surfaces[1].find_entity(action.into, action.position)
    if not found then
        game.print("Did not find " .. action.into .. " at " .. serpent.line(action.position))
        return false;
    end

    local inserted = found.insert({name=action.name, count=action.count})
	player.remove_item({name=action.name, count=inserted})
    return true
end

function add_craft(player, action)
--    if player.get_item_count(action.name) < action.count then
--        return false
--    end

    if action.wait and action.queued then
        return player.crafting_queue_size == 0
    end

    local recipe = player.force.recipes[action.name]
    local started = player.begin_crafting{recipe=recipe, count=action.count, silent=False}
    action.queued = true

    return not action.wait or (player.crafting_queue_size == 0)
end


----

function add_run_to(x, y)
    table.insert(global.action_queue,
        {cmd="run_to", run_goal={x=x, y=y}})
end

function add_mine_at(x, y, name, c)
    table.insert(global.action_queue,
        {cmd="mine_at", name=name, count=c, position={x,y}})
end

function add_build_at(name, x, y, orient)
    table.insert(global.action_queue,
        {cmd="build_at", name=name, position={x, y}, orient=orient})
end

-- TODO try and remove this by generating it, or dynamically searching and fueling.
function add_insert_in(into, name, count, x, y)
    table.insert(global.action_queue,
        {cmd="insert_in", position={x, y}, into=into, name=name, count=count})
end

function add_add_craft(name, count, wait)
    table.insert(global.action_queue,
        {cmd="add_craft", name=name, count=count, wait=wait, queued=false})
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

    add_run_to(-73.8, -106.5)

    add_build_at("burner-mining-drill", -72, -103, defines.direction.west)
    add_build_at("stone-furnace",       -74, -103, defines.direction.west)

----

    add_mine_at(-74.5, -107.5, "coal", 2)
    add_insert_in("burner-mining-drill", "coal", 1, -72, -103)
    add_insert_in("stone-furnace",       "coal", 1, -74, -103)

----

    add_mine_at(-72.5, -107.5, "stone", 5)
   	game.players[1].insert{name="iron-plate", count=20}
    add_add_craft("burner-mining-drill", 1, false)

----

    add_mine_at(-74.5, -107.5, "coal", 2)
    add_insert_in("burner-mining-drill", "coal", 1, -72, -103)
    add_insert_in("stone-furnace",       "coal", 1, -74, -103)

----

    add_mine_at(-72.5, -107.5, "stone", 5)
   	game.players[1].insert{name="iron-plate", count=20}
    add_add_craft("burner-mining-drill", 1, true)


    add_mine_at(-74.5, -107.5, "coal", 1)
    add_build_at("burner-mining-drill", -75, -108, defines.direction.west)
    add_build_at("burner-mining-drill", -77, -108, defines.direction.east)

    add_insert_in("burner-mining-drill", "coal", 1, -75, -108)

----

    game.print("Action Queue: " .. #global.action_queue .. " actions")
end

--script.on_load(function()
--	runOnce()
--end)

script.on_event(defines.events.on_tick, function(event)
	if global.speedrunRunning then
        if (game.tick > 0 and game.tick % 200 == 0) then
            local pos = game.players[1].position
            game.print(
                "Tick " .. (game.tick / 100)
                .. ", Pos: " .. string.format("%.1f, %.1f", pos.x, pos.y)
                .. ", ActionQueue: " .. #global.action_queue
                   .. " top: " .. (#global.action_queue > 0 and global.action_queue[1].cmd or "None")
            )
        end
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
