require ("utils")

function action_check(player)
    local status = global.status

    if game.tick < global.next_check then
        status.ticks_waiting = status.ticks_waiting + 1
        return
    end

    if #global.action_queue == 0 then
        return
    end

    local action = global.action_queue[1]
    if action.handler ~= nil then
        if action.handler(player, action) then
            table.remove(global.action_queue, 1)
            status.actions_complete = status.actions_complete + 1
            status.ckpt_action_num = status.ckpt_action_num + 1
            status.last2 = status.last1
            status.last1 = action.cmd
        end
    else
        printAndQuit("Unknown action: " .. serpent.line(action))
    end
end


-------------------
----- Helpers -----
-------------------

function print_status()
    game.print(string.format('Tick %4d %2d/%d complete, ckpt: %s #%d',
        (game.tick / 60),
        global.status.actions_complete, global.status.original_queue,
        global.status.checkpoint, global.status.ckpt_action_num))
    game.print(string.format("  cmd: %s (last: %s, %s)",
        (#global.action_queue > 0 and global.action_queue[1].cmd or "None"),
        global.status.last1, global.status.last2))
end

function run_to(player, action)
    local goal = action.run_goal

    local deltaX = goal.x - player.position.x
    local deltaY = goal.y - player.position.y
    local err = 0.4

    if math.abs(deltaX) <= err and math.abs(deltaY) <= err then
        return true
    end

    if global.cheating.teleport then
        -- TODO check if something is in the way?
        game.players[1].teleport({goal.x, goal.y})
        local distance = math.sqrt(deltaX * deltaX + deltaY * deltaY)
        local wait = math.ceil(distance / (8.902 / 60))
        game.print("  teleported " .. distance .. " waiting " .. wait)
        global.next_check = game.tick + wait
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
    return false
end

script.on_event(defines.events.on_player_mined_item, function(event)
    if global.speedrunRunning and #global.action_queue > 0 then
        local action = global.action_queue[1]
        if action.cmd == "mine_at" or action.cmd == "mine_area" then
            local player = game.players[event.player_index]
            if not (player and player.valid) then return end

            action.count = action.count - 1
        end
   end
end)

function get_action()
    -- to be paired with add_X like such
    -- add_run_to(x, y);        -- Adds to global.action_queue
    -- action = get_action():   -- Pops from global.action_queue and passes back
    return table.remove(global.action_queue)
end

function add_action(action, queue)
    table.insert(queue or global.action_queue, action)
end

function add_run_to(x, y)
    add_action({cmd="run_to", handler=run_to, run_goal={x=x, y=y}})
end

function mine_area(player, action)
    if (action.count <= 0) then return true end

    -- # try and find the thing
    local found = game.surfaces[1].find_entities_filtered{
        area = action.area, radius = 2, limit = 100,
        type = action.type}

    assertAndQuit(#found > 0, "Didn't find any " .. action.name .. " | " .. (action.type or "") .. " | " .. serpent.line(action.area))
    assertAndQuit(string.match(found[1].name, action.name), action.name .. " not found in " .. found[1].name)
    player.update_selected_entity(found[1].position)

    -- Select the thing we are mining
    player.update_selected_entity(found[1].position)

    assertAndQuit(
        player.selected and player.can_reach_entity(player.selected),
        "Can't reach to mine " .. action.name .. " @ " .. serpent.line(found[1].position))

    player.mining_state = {mining = true, position = found[1].position}
    -- action.count is decremented in `on_player_mined_item`
    return action.count <= 0
end

function mine_at(player, action)
    -- # try and find the thing
    --local found = game.surfaces[1].find_entities_filtered{
    --    position = action.position, radius=1, limit = 1,
    --    type = action.type or "resource"}
    --assertAndQuit(#found > 0, "Didn't find any " .. action.name .. " | " .. (action.type or "") .. " | " .. serpent.line(action.position))
    --assertAndQuit(string.match(found[1].name, action.name), action.name .. " not found in " .. found[1].name)
    --player.update_selected_entity(found[1].position)

    if (action.count <= 0) then return true end

    -- Select the thing we are mining
    player.update_selected_entity(action.position)
    --assertAndQuit(string.match(player.selected.name, action.name),
    --              action.name .. " not found in " .. player.selected.name)

    assertAndQuit(
        player.selected and player.can_reach_entity(player.selected),
        "Can't reach to mine " .. action.name .. " @ " .. serpent.line(action.position))

    player.mining_state = {mining = true, position = action.position}
    -- action.count is decremented in `on_player_mined_item`

    return action.count <= 0
end


function build_at(player, action)
    if player.get_item_count(action.name) < 1 then
        game.print("build_at, did not have " .. action.name)
        return false
    end

    local surface = game.surfaces[1]
    if not surface.can_place_entity{name=action.name, position=action.position, direction=action.orient} then
        game.print("build_at, can not place " .. serpent.line(action.position))
        return false
    end

    player.remove_item({name=action.name, count=1})
    local t = surface.create_entity{name=action.name, position=action.position, direction=action.orient,
                                    raise_built=true, force=game.forces.player}
    assertAndQuit(t ~= nil, 'Failed "build_at" ' .. serpent.line(action))
    return true
end

function insert_in(player, action)
    -- TODO move under some option to cheat.
    if player.get_item_count(action.item) < action.count then
        return false
    end

    local found = game.surfaces[1].find_entity(action.into, action.position)
    if not found then
        game.print("Did not find " .. action.into .. " at " .. serpent.line(action.position))
        return false
    end

    local inserted = found.insert({name=action.item, count=action.count})
    local removed = player.remove_item({name=action.item, count=inserted})
    assert(inserted == removed, "Ugh ohh " .. inserted .. " != " .. removed)
    floating_text("+" .. inserted .. " (" .. action.item .. ")", action.position)
    return true
end

function fill_each_to(player, action)
    local found = game.surfaces[1].find_entities_filtered{name=action.into, area=action.area}
    if not found then
        game.print("Did not find " .. action.into .. " at " .. serpent.line(action.area))
        return false
    end

    local total = 0
    for key, entity in pairs(found) do
        local item_count = entity.get_item_count(action.item)

        local to_insert = math.max(0, action.in_each - item_count)

        if to_insert > 0 then
            if player.get_item_count(action.item) < to_insert then
                printAndQuit("Ran out of " .. action.item .. " on " .. key .. " of " .. #found)
                return false
            end

            local removed = player.remove_item({name=action.item, count=to_insert})
            local inserted = entity.insert({name=action.item, count=to_insert})
            if removed ~= inserted then
                --assert(removed == inserted, "Bad fill_each_to " .. removed .. " != " .. inserted)
                printAndQuit("Bad fill_each_to " .. removed .. " != " .. inserted)
            end
            total = total + removed

            floating_text("-" .. removed .. " (" .. action.item .. ")", entity.position)
        end
    end
    game.print("  Inserted " .. total .. " " .. action.item .. " into " .. #found .. " " .. action.into)
    if #found == 0 then
        printAndQuit("Nothing found")
    end

    return true
end

function add_craft(player, action)
    if action.wait and action.count == 0 then
        return player.crafting_queue_size == 0
    end

    local recipe = player.force.recipes[action.name]
    local started = player.begin_crafting{recipe=recipe, count=action.count, silent=False}
    action.count = action.count - started

    if started == 0 then
        -- wait 0.2s and try again
        global.next_check = game.tick + 100
        return false
    else
        floating_text("+" .. started .. " crafts of " .. action.name, player.position)
    end

    return action.count == 0 and (not action.wait or (player.crafting_queue_size == 0))
end

function collect_from(player, action)
    local started = player.get_item_count(action.item)
    local to_get = action.inv_count - started
    if to_get < 0 then
        game.print("Already had " .. action.inv_count .. " " .. action.item)
        return true
    end

    local found = game.surfaces[1].find_entities_filtered{name=action.name, area=action.area}
    if not found then
        game.print("Did not find " .. action.name .. " at " .. serpent.line(action.area))
        return false
    end

    -- TODO try to collect evenly from machines
    local total_found = 0
    for key, entity in pairs(found) do
        local inventory = entity.get_output_inventory()
        local item_count = inventory.get_item_count(action.item)
        total_found = total_found + item_count
    end

    for key, entity in pairs(found) do
        local inventory = entity.get_output_inventory()
        local item_count = inventory.get_item_count(action.item)
        --game.print(key .. " " .. entity.name .. " " .. serpent.line(entity.position) .. ": " .. item_count)

        -- Don't take last coal from burner inserter
        if action.item == "coal" and entity.name == "burner-mining-drill" then
            item_count = item_count - 1
        end

        local to_pull = math.min(to_get, item_count)
        if to_pull > 0 then
            local inserted = player.insert({name=action.item, count=to_pull})
            assert(inserted == to_pull, "Didn't find " .. to_pull)
            -- Only remove as many as were actually inserted
            local pulled = inventory.remove({name=action.item, count=inserted})
            assert(pulled == inserted, "Didn't remove " .. inserted .. " only " .. pulled)

            to_get = to_get - pulled
            floating_text("+" .. pulled .. " (" .. action.item .. ")", entity.position)
            if to_get <= 0 then break end
        end
    end

    if to_get > 0 and action.wait ~= false then
        -- wait 0.2s and try again
        global.next_check = game.tick + 20
        game.print("waiting need " .. to_get .. " more " .. action.item .. " " .. serpent.line(action))
        return false
    end

    local inv_count = player.get_item_count(action.item)
    game.print("  Stocked " .. inv_count .. " " .. action.item
            .. "  extra: " .. total_found - (inv_count - started) )
    return true
end

----

function add_run_to(x, y)
    add_action({cmd="run_to", handler=run_to, run_goal={x=x, y=y}})
end

function add_mine_at(x, y, name, count, type)
    -- mine exactly count
    add_action(
        {cmd="mine_at", handler=mine_at,
         name=name, type=type, count=count, position={x,y}})
end

function add_mine_area(name, type, count, area)
    add_action(
        {cmd="mine_area", handler=mine_area,
         name=name, type=type, count=count, area=area})
end


function add_build_at(name, x, y, orient)
    add_action(
        {cmd="build_at", handler=build_at,
         name=name, position={x, y}, orient=orient})
end

function add_insert_in(into, item, count, x, y)
    add_action(
        {cmd="insert_in", handler=insert_in,
         position={x, y}, into=into, item=item, count=count})
end

function add_fill_each_to(into, item, in_each, area)
    add_action(
        {cmd="fill_each_to", handler=fill_each_to,
         into=into, item=item, in_each=in_each, area=area})
end

function add_add_craft(name, count, wait)
    add_action(
        {cmd="add_craft", handler=add_craft,
         name=name, count=count, wait=wait, queued=false})
end

function add_set_autocraft(items)
    add_action({
        cmd="set_autocraft", items=items,
        handler=function(player, action)
            game.print("  autocrafting: " .. serpent.line(action.items))
            global.autocraft = action.items
            return true
        end,
    })
end

function add_collect_from(name, item, inv_count, area, wait)
    -- inv_count => amount to have in inventory after.
    add_action(
        {cmd="collect_from", handler=collect_from,
         name=name, item=item,
         area=area,
         inv_count=inv_count,
         wait=wait
        })
end

function add_wait_inventory(item, inv_count)
    add_action(
        {cmd="wait_inventory",
         handler= function(player, action)
            -- TODO have global wait counter.
            local count = player.get_item_count(item)
            if count < inv_count then
                game.print("Waiting for " .. inv_count .. " (have " .. count .. ") " .. item)
                global.next_check = game.tick + 20
                return false
            end
            return true
         end,
         item=item, -- for debug printing
         inv_count=inv_count,
        })
end

function add_wait(ticks, msg)
    add_action(
        {cmd="wait",
         handler= function(player, action)
            game.print("Waiting " .. action.ticks .. " tick(s) " .. "@" .. math.ceil(game.tick/60) .. "s : " .. action.msg)
            global.next_check = game.tick + action.ticks
            return true
         end,
         ticks=ticks, msg=msg
        })
end

function add_print_inventory(verify, show)
    add_action(
        {cmd="print_inventory", verify=verify,
         handler= function(player, action)
            local inventory = player.get_main_inventory()
            inventory.sort_and_merge()
            for item, count in pairs(inventory.get_contents()) do
                local to_verify = verify and verify[item] ~= nil
                local verify_print = (to_verify and " (verify >= " .. verify[item] .. ")") or ""
                if show ~= false then
                    game.print(count .. " x " .. item .. verify_print);
                end
                if verify and verify[item] ~= nil then
                    assert(count >= verify[item],
                        "Don't have " .. verify[item] .. " of " .. item .. " only " .. count)
                    verify[item] = nil
                end
            end
            if #verify > 0 then
                for item, count in pairs(verify) do
                    game.print("Didn't have any " .. item)
                end
                printAndQuit("Bad Verify")
            end
            return true
        end
        })
end

-------------------
------ Setup ------
-------------------

function setupQueue()

-- early game areas
    early_trees = {{-2, 0}, {2, 2}}   -- 2x2 (2x3?)

    coal_area = {{-11, -5}, {-1, -3}}   -- 2x6
    stone_area = {{1, -6}, {9, -1}}     -- 9x5 (slightly zigged)
    iron_area = {{0, 4}, {9, 13}}       -- 8x8 (furnace, mining, furnace, mining)
    copper_area = {{-22, 2}, {-20, 10}} -- TODO

    coal_start = {-1, -3}
    iron_start = { 0,  4}
    stone_chest_start = { 2.5, -3.5}

-- mid game_areas
    iron_2_area = {{0, 4}, {9, 17}}
    coal_2_area = {{-11, -5}, {-1, -3}}

--- Setup early game shortcuts
    function add_early_mine_coal(count)
        add_mine_at(0, -1, "coal", count)
    end

    function add_early_mine_stone(count)
        add_mine_at(1.5, -0.5, "stone", count)
    end

    add_early_mine_coal(2)
    mine_two_coal = get_action()

    add_early_mine_stone(2)
    mine_two_stone = get_action()

    add_early_mine_stone(3)
    mine_three_stone = get_action()

    function early_fuel_mining_smelter(mining_fuel, furnace_fuel, area)
        add_fill_each_to("burner-mining-drill", "coal", mining_fuel,  area)
        add_fill_each_to("stone-furnace",       "coal", furnace_fuel, area)
    end

    function early_iron(nth, pre_stone, post_stone, post_craft_action)
        add_early_mine_stone(pre_stone)
        add_collect_from("stone-furnace", "iron-plate",   9, iron_area)
        add_add_craft("burner-mining-drill", 1, false)

        add_early_mine_stone(post_stone)
        add_add_craft("stone-furnace", 1, false)

        add_action(post_craft_action)
        add_wait_inventory("stone-furnace", 1)

        add_build_at("burner-mining-drill",
                     iron_start[1] + 2, iron_start[2] + 2 * (nth - 1), defines.direction.west)
        add_build_at("stone-furnace",
                     iron_start[1] + 0, iron_start[2] + 2 * (nth - 1), defines.direction.west)
    end

---- QUEUE START

    set_checkpoint("Start")
    add_change_speed(10)
    add_run_to(0, 1.5)

    add_set_autocraft({"stone-furnace", "gears"})

---- First iron furnace
    add_build_at("stone-furnace",       iron_start[1] + 0, iron_start[2], defines.direction.west)
    add_build_at("burner-mining-drill", iron_start[1] + 2, iron_start[2], defines.direction.west)

    --Fuel
    add_early_mine_coal(1)
    add_insert_in("burner-mining-drill", "coal", 1,   iron_start[1] + 2, iron_start[2])
    add_early_mine_coal(1)
    add_insert_in("stone-furnace",       "coal", 1,   iron_start[1] + 0, iron_start[2])

---- 2nd Iron Furnace
    set_checkpoint("Iron 2")
    early_iron(2,    5, 5, mine_two_coal)

    --- Fuel everything up
    add_fill_each_to("burner-mining-drill", "coal", 1,  iron_area)
    add_early_mine_coal(2)
    add_fill_each_to("stone-furnace",       "coal", 1,  iron_area)
    add_early_mine_coal(2)
    -- (first insert goes into use immediately)
    add_fill_each_to("burner-mining-drill", "coal", 1,  iron_area)

---- 1st & 2nd coal miners
    set_checkpoint("Coal 1&2")
    add_early_mine_stone(6)
    add_collect_from("stone-furnace", "iron-plate",   9, iron_area)
    add_add_craft("burner-mining-drill", 1, false)

    add_early_mine_stone(5)
    add_collect_from("stone-furnace", "iron-plate",   9, iron_area)
    add_add_craft("burner-mining-drill", 1, false)

    -- finish craft
    add_early_mine_coal(4)

    add_build_at("burner-mining-drill", coal_start[1] + 0, coal_start[2], defines.direction.west)
    add_build_at("burner-mining-drill", coal_start[1] - 2, coal_start[2], defines.direction.east)
    add_fill_each_to("burner-mining-drill", "coal", 1,   coal_area)

---- Refuel iron
    add_early_mine_coal(4)
    early_fuel_mining_smelter(2, 1, iron_area)

---- 3rd iron
    set_checkpoint("Iron 3")
    --add_change_speed(1)
    early_iron(3,   6, 6, mine_two_coal)

    add_collect_from("burner-mining-drill", "coal", 9,    coal_area)
    early_fuel_mining_smelter(2, 1, iron_area)

---- A couple of trees
    add_mine_area("tree", "tree", 6, early_trees)
    add_print_inventory({["wood"]=21}, false)


---- 1st Stone
    set_checkpoint("Stone 1")
    add_add_craft("wooden-chest", 2, false)
    add_early_mine_stone(2)

    add_collect_from("stone-furnace", "iron-plate",   9, iron_area)
    add_add_craft("burner-mining-drill", 1, false)

    add_early_mine_stone(2)
    add_wait_inventory("burner-mining-drill", 1)

    add_build_at("burner-mining-drill", 3, -2, defines.direction.north)
    add_build_at("wooden-chest",        stone_chest_start[1], stone_chest_start[2], 0)

    -- Fuel stone
    add_collect_from("burner-mining-drill", "coal", 3, coal_area)
    add_fill_each_to("burner-mining-drill", "coal", 3,    stone_area)

---- Fuel iron
    -- small wait
    add_early_mine_coal(2)

    add_collect_from("burner-mining-drill", "coal", 15, coal_area)

    -- Technicall 3 * (3+2) = 15, but likely only need ~10 fuel
    -- Fuel every ~26s for burner-mining-drill, Fuel every ~45s for stone-furnace
    early_fuel_mining_smelter(2, 1, iron_area)


---- More coal (more is better)
    set_checkpoint("Coal 2.0")
    add_early_mine_stone(3)

    add_collect_from("stone-furnace", "iron-plate",   9, iron_area)
    add_add_craft("burner-mining-drill", 1, false)

    add_early_mine_stone(5)
    add_collect_from("stone-furnace", "iron-plate",   9, iron_area)
    add_add_craft("burner-mining-drill", 1, false)

    add_early_mine_stone(3)
    add_wait_inventory("burner-mining-drill", 2)

    add_build_at("burner-mining-drill", coal_start[1] + 0, coal_start[2] - 2, defines.direction.west)
    add_build_at("burner-mining-drill", coal_start[1] - 2, coal_start[2] - 2, defines.direction.east)

    add_early_mine_coal(1)
    add_collect_from("burner-mining-drill", "coal", 2, coal_area)
    add_fill_each_to("burner-mining-drill", "coal", 1,  coal_area)

---- 4th Iron
    set_checkpoint("Major Iron")
    early_iron(4,   4, 3, mine_three_stone)

    add_collect_from("burner-mining-drill", "coal", 15, coal_area)
    early_fuel_mining_smelter(2, 1, iron_area)

---- 5th Iron
    add_collect_from("wooden-chest", "stone",  10, stone_area)

    early_iron(5,    2, 2, mine_three_stone)

    add_collect_from("burner-mining-drill", "coal", 16, coal_area)
    early_fuel_mining_smelter(3, 2, iron_area)

---- 2nd Stone
    set_checkpoint("Stone 2")
    add_early_mine_stone(1)

    add_collect_from("wooden-chest",  "stone",        5, stone_area)
    add_collect_from("stone-furnace", "iron-plate",   9, iron_area)

    add_add_craft("burner-mining-drill", 1, false)

    add_early_mine_stone(2)
    add_wait_inventory("burner-mining-drill", 1)

    add_build_at("burner-mining-drill",               2, -5, defines.direction.south)

    add_collect_from("burner-mining-drill", "coal", 6, coal_area)
    add_fill_each_to("burner-mining-drill", "coal", 3, stone_area)

---- 6th Iron
    set_checkpoint("Iron 6-8")

    add_early_mine_stone(3)
    add_collect_from("wooden-chest",        "stone", 5, stone_area)

    add_collect_from("stone-furnace", "iron-plate",   9, iron_area)
    add_add_craft("burner-mining-drill", 1, false)

    add_early_mine_stone(2)
    add_collect_from("wooden-chest",        "stone", 5, stone_area)
    add_add_craft("stone-furnace", 1, false)

    add_early_mine_coal(2)
    add_collect_from("burner-mining-drill", "coal", 20, coal_area)

    -- TODO run_back with actions in the middle?
    add_run_to(-1.5, 5)
    add_wait_inventory("stone-furnace", 1)

    add_build_at("burner-mining-drill",   2, 14, defines.direction.west)
    add_build_at("stone-furnace",         0, 14, defines.direction.west)
    early_fuel_mining_smelter(2, 1, iron_area)

    add_run_to(-1.5, 1.5)
    add_run_to( 0.5, 1.5)

    add_collect_from("wooden-chest",        "stone", 10, stone_area)
    add_collect_from("stone-furnace", "iron-plate",   9, iron_area)
    add_add_craft("burner-mining-drill", 1, false)
    add_add_craft("stone-furnace", 1, false)
    add_early_mine_stone(5)

    add_collect_from("wooden-chest",        "stone", 10, stone_area)
    add_collect_from("stone-furnace", "iron-plate",   9, iron_area)
    add_add_craft("burner-mining-drill", 1, false) -- eats my earlier stone-furnace :/
    add_add_craft("stone-furnace", 2, false)
    add_early_mine_stone(4)

    add_collect_from("burner-mining-drill", "coal", 20, coal_area)

    add_run_to(-1.5, 7)
    add_wait_inventory("stone-furnace", 2)

    add_build_at("burner-mining-drill",   2, 16, defines.direction.west)
    add_build_at("stone-furnace",         0, 16, defines.direction.west)
    add_build_at("burner-mining-drill",   2, 18, defines.direction.west)
    add_build_at("stone-furnace",         0, 18, defines.direction.west)
    early_fuel_mining_smelter(2, 1, iron_area)

    add_run_to(-1.5, 1.5)
    add_run_to( 0.5, 1.5)

---- Stone time
    set_checkpoint("Stone 3&4 - 5&6")

    for i = 1,2 do
        add_add_craft("wooden-chest", 2, false)
        add_collect_from("stone-furnace", "iron-plate", 18, iron_area)
        add_collect_from("wooden-chest",  "stone",       5, stone_area)
        add_add_craft("burner-mining-drill", 1, false)

        add_early_mine_stone(3)
        add_collect_from("wooden-chest",  "stone",       5, stone_area)
        add_add_craft("burner-mining-drill", 1, false)

        add_early_mine_coal(2)
        add_wait_inventory("burner-mining-drill", 2)

        add_build_at("burner-mining-drill", 3+2*i, -2, defines.direction.north)
        add_build_at("burner-mining-drill", 2+2*i, -5, defines.direction.south)
        add_build_at("wooden-chest",        stone_chest_start[1] + 2*i, stone_chest_start[2], 0)

        add_collect_from("burner-mining-drill", "coal", 8, coal_area)
        add_fill_each_to("burner-mining-drill", "coal", 2, stone_area)
    end
    -- Done

---- Coal time
    set_checkpoint("Coal 5-8")

    for i = 0,1 do
        add_collect_from("stone-furnace", "iron-plate",   18, iron_area)
        add_collect_from("wooden-chest",        "stone",  10, stone_area)
        add_add_craft("burner-mining-drill", 2, false)

        add_early_mine_stone(5)
        add_wait_inventory("burner-mining-drill", 2)

        add_build_at("burner-mining-drill",               -5, -5+2*i, defines.direction.west)
        add_build_at("burner-mining-drill",               -7, -5+2*i, defines.direction.east)

        add_collect_from("burner-mining-drill", "coal", 4, coal_area)
        add_fill_each_to("burner-mining-drill", "coal", 1, coal_area)
    end
    -- Done

---- Iron row two
    set_checkpoint("Iron Row 2")
    add_change_speed(5)

    -- Get all iron (and refual)
    add_run_to(-1.5, 5)
        add_collect_from("stone-furnace", "iron-plate", 1000, iron_area, false)
    add_run_to(-1.5, 1.5) add_run_to( 0.5, 1.5)

    for i = 0,1 do
        -- Get all coal on hand.
        add_collect_from("burner-mining-drill", "coal", 1000, coal_area, false)

        -- Get all stone on hand.
        add_collect_from("wooden-chest", "stone", 1000, stone_area, false)
        add_fill_each_to("burner-mining-drill", "coal", 2,   stone_area)

        add_print_inventory({["coal"]=5, ["stone"]=20, ["iron"]=36}, false)

        -- Start crafting 4 of each
        add_add_craft("burner-mining-drill", 4, false) -- 4s x 4 = 16s
        add_early_mine_stone(8)

        -- Get all stone on hand.
        add_collect_from("wooden-chest", "stone", 20, stone_area)
        add_add_craft("stone-furnace", 4, false)   -- 0.5s x 4 = 2s
        add_early_mine_stone(1)

        add_run_to(-1.5, 1.5) add_run_to(-1.5, 7 + 4*i)
        add_wait_inventory("stone-furnace", 4)

        for j=0,3 do -- inclusive of end because 1-indexed probably
            add_build_at("burner-mining-drill",   6, 4 + 2*(4*i + j), defines.direction.west)
            add_build_at("stone-furnace",         4, 4 + 2*(4*i + j), defines.direction.west)
        end

        -- Fuel everything (but mostly new stuff)
        early_fuel_mining_smelter(2, 1, iron_area)

        -- Get all iron while here (waiting for at least 36)
        add_collect_from("stone-furnace", "iron-plate", 36, iron_area)
        add_collect_from("stone-furnace", "iron-plate", 1000, iron_area, false)

        add_run_to(-1.5, 1.5)
        add_run_to( 0.5, 1.5)
    end
    -- Done

---- Extra coal
    set_checkpoint("Big Coal")

    -- TODO 'get-in-reach'
    add_collect_from("wooden-chest", "stone", 1000, stone_area, false)
    add_collect_from("stone-furnace", "iron-plate", 36, iron_area)
    add_print_inventory({["coal"]=2, ["stone"]=20, ["iron"]=36}, false)
    add_add_craft("burner-mining-drill", 4, false)
    -- for copper in a second
    add_collect_from("stone-furnace", "iron-plate", 36, iron_area)

    add_run_to(-5.5, 1.5)
    for i=0,1 do
        add_wait_inventory("burner-mining-drill", 2)
        add_build_at("burner-mining-drill",               -9,  -3-2*i, defines.direction.west)
        add_build_at("burner-mining-drill",               -11, -3-2*i, defines.direction.east)
        add_fill_each_to("burner-mining-drill", "coal", 1,   coal_2_area)
    end

    -- collect ALL coal
    add_collect_from("burner-mining-drill", "coal", 1000, coal_area, false)


--[[
---- Copper!
    set_checkpoint("Copper")
    add_change_speed(2)

    -- Get All Stone -- TODO function
    add_run_to( 8, 1.5)
        add_collect_from("wooden-chest", "stone", 40, {{4, 0}, {16, 1}})
        add_add_craft("burner-mining-drill", 2, false) -- Start crafting
    add_run_to( 0.5, 1.5)

    add_run_to(-1.5, 1.5) add_run_to(-1.5, 7)
        add_collect_from("stone-furnace", "iron-plate", 18, {{0, 4}, {1, 16}}, false)
        add_add_craft("burner-mining-drill", 2, false)
        add_add_craft("stone-furnace", 4, false)
    add_run_to(-1.5, 1.5) add_run_to( 0.5, 1.5)

    add_run_to(-19, 1.5)
    for j=0,3 do -- inclusive of end because 1-indexed probably
        add_wait_inventory("stone-furnace", 1)
        add_build_at("burner-mining-drill",  -22, 2+2*j, defines.direction.east)
        add_build_at("stone-furnace",        -20, 2+2*j, defines.direction.east)
        early_fuel_mining_smelter(5, 3, copper_area)
    end

--]]
-- Final stuff

--    add_print_inventory{["wood"]=5}

    -- ~10 coal, 5 wood,
    --    ~30 coal, ~20 iron, ~6 stone,
    -- ~131 seconds

    add_wait(1, "end") -- Get finish time
end

-----

function runOnce()
    if global.speedRunSetupComplete then return end
    global.speedRunSetupComplete = true

    global.action_queue = {}
    game.print("Adding actions to queue")
    setupQueue()
    game.print("Action Queue: " .. #global.action_queue .. " actions")

    global.next_check = 0
    global.autocraft = {}

    global.status = {
        actions_complete = 0,
        ckpt_action_num = 0,
        original_queue = #global.action_queue,
        checkpoint = "", -- TODO add_set_checkpoint
        last1 = "",
        last2 = "",
        ticks_waiting = 0,

    }

    -- Can be helpful for avoiding things and in debugging.
    global.cheating = {
        teleport = false,
        always_day = true,
    }

    game.players[1].surface.always_day = global.cheating.always_day
end

script.on_event(defines.events.on_tick, function(event)
    if global.speedRunSetupComplete ~= true then
        runOnce()
        global.speedrunRunning = true
    end

    if global.speedrunRunning then
        if (game.tick > 0 and game.tick % (60 * 30) == 0) then -- 30s
            print_status()
        end
        action_check(game.players[1])

        if #global.action_queue == 0 then
            game.speed = 0.02
            global.speedrunRunning = false
        end
    end
end)


-------------------
------ Maths ------
-------------------
--[[
Fuel every ~26s for burner-mining-drill, Fuel every ~45s for stone-furnace

burner-mining-drills mine 1 coal/4s (- 1 coal every 26s)
stone-furnace + burner-mining-drill = 1coal/16

1 coal miner powers ~ 4 miners + smelters + self

To saturate self craft => every 4.5 seconds => 9 iron + 10 stone
=> 2 iron/s => 8 iron drills
=> ~2.5 stone/s => 10 stone drills

--]]
