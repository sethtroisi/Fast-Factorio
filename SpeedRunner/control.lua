function action_check(player)
    local pos = player.position

    if game.tick < global.next_check then
        return
    end

    if #global.action_queue == 0 then
        return
    end

    action = global.action_queue[1]

    if action.cmd == "build_at" then
        if action.handler(player, action) then
            table.remove(global.action_queue, 1)
        else
            printAndQuit('Failed "build_at" ' .. serpent.line(action))
            return
        end
    else
        if action.handler ~= nil then
            if action.handler(player, action) then
                table.remove(global.action_queue, 1)
            else
                -- Should try to do crafting at the same time?
                return
            end
        else
            printAndQuit("Unknown action: " .. serpent.line(action))
        end
    end

--      if builder.get_item_count(item.name) >= item.count then
--      builder.remove_item({name=item.name, count=item.count})

--      if builder.mine_entity(ent) then
--          local products = ent.prototype.mineable_properties.products
--          if products then
--              -- game.print("Products: " .. ent.line(products))
--              for key, value in pairs(products) do
--                  inserted = builder.insert({name=value.name, count=math.random(value.amount_min, value.amount_max)})
--              end
--      end
--      ent.destroy()

--      tile = ent.surface.get_tile(ent.position)
--      game.print(ent.prototype.mineable_properties)
--      builder.mine_tile(tile)


end


-------------------
----- Helpers -----
-------------------

function printAndQuit(msg)
    game.print(msg)
    -- TODO log more debug
    global.speedrunRunning = false
    game.speed = 0.02
end

function floating_text(msg, pos)
    game.surfaces[1].create_entity{
        name="flying-text",
        text=msg,
        position=pos,
        color={r=0.15,g=0.4,b=1}
    }
end

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

-- quick and dirty, one depth clone
function table.clone(org)
  return {table.unpack(org)}
end

function get_action()
    -- to be paired with add_X like such
    -- add_run_to(x, y);        -- Adds to global.action_queue
    -- action = get_action():   -- Pops from global.action_queue and passes back
    return table.remove(global.action_queue)
end

function add_action(action)
    table.insert(global.action_queue, action)
end

function add_run_to(x, y)
    table.insert(global.action_queue,
        {cmd="run_to", handler=run_to,
         run_goal={x=x, y=y}})
end

function mine_at(player, action)
    -- TODO add to a setting
    if false then
        player.insert{name=action.name, count=action.count}
        return true
    end

    -- # try and find the thing
    -- TODO check we're close? or just add 'run_to?'

    local found = game.surfaces[1].find_entities_filtered{
        position = action.position, radius=1, limit = 1,
        type = action.type or "resource"}

    if #found > 0 then
        assert(string.match(found[1].name, action.name), action.name .. " not found in " .. found[1].name)

--      Select the thing we are mining
        player.update_selected_entity(found[1].position)
        player.mining_state = {mining = true, position = found[1].position}
        -- action.count is decremented in `on_player_mined_item`

--      Why doesn't this work?
--        local tile = player.surface.get_tile(found[1].position.x, found[1].position.y)
--        player.mine_tile(tile)
    end

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
    if not t then
        return false
    end

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

function insert_in_each(player, action)
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
                printAndQuit("Ran out of " .. action.item .. " " .. key .. "/" .. #found)
                return false
            end

            local removed = player.remove_item({name=action.item, count=to_insert})
            local inserted = entity.insert({name=action.item, count=to_insert})
            if removed ~= inserted then
                --assert(removed == inserted, "Bad insert_in_each " .. removed .. " != " .. inserted)
                printAndQuit("Bad insert_in_each " .. removed .. " != " .. inserted)
            end
            total = total + removed

            floating_text("-" .. removed .. " (" .. action.item .. ")", entity.position)
        end
    end

    game.print("  Inserted " .. total .. " " .. action.item .. " into " .. #found .. " " .. action.into)
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
        -- wait 0.5s and try again
        global.next_check = game.tick + 20
    else
        floating_text("+" .. started .. " crafts of " .. action.name, player.position)
    end

    return action.count == 0 and (not action.wait or (player.crafting_queue_size == 0))
end

function collect_from(player, action)
    local to_get = action.inv_count - player.get_item_count(action.item)
    if to_get < 0 then
        game.print("Already had " .. action.inv_count .. " " .. action.item)
        return true
    end

    local found = game.surfaces[1].find_entities_filtered{name=action.name, area=action.area}
    if not found then
        game.print("Did not find " .. action.name .. " at " .. serpent.line(action.area))
        return false
    end

    for key, entity in pairs(found) do
        local inventory = entity.get_output_inventory()
        local item_count = inventory.get_item_count(action.item)
        --game.print(key .. " " .. entity.name .. " " .. serpent.line(entity.position) .. ": " .. item_count)

        local to_pull = math.min(to_get, math.min(item_count, action.max_per_machine))
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

    if to_get > 0 then
        -- wait 0.2s and try again
        global.next_check = game.tick + 20
        game.print("waiting at " .. serpent.line(action) .. " need " .. to_get .. " more")
        return false
    end

    game.print("  Stocked " .. player.get_item_count(action.item) .. " " .. action.item)
    return to_get == 0
end

----

function add_run_to(x, y)
    table.insert(global.action_queue,
        {cmd="run_to", handler=run_to,
         run_goal={x=x, y=y}})
end

function add_mine_at(x, y, name, c, type)
    table.insert(global.action_queue,
        {cmd="mine_at", handler=mine_at,
         name=name, type=type, count=c, position={x,y}})
end

function add_build_at(name, x, y, orient)
    table.insert(global.action_queue,
        {cmd="build_at", handler=build_at,
         name=name, position={x, y}, orient=orient})
end

function add_insert_in(into, item, count, x, y)
    table.insert(global.action_queue,
        {cmd="insert_in", handler=insert_in,
         position={x, y}, into=into, item=item, count=count})
end

function add_insert_in_each(into, item, in_each, area)
    table.insert(global.action_queue,
        {cmd="insert_in_each", handler=insert_in_each,
         into=into, item=item, in_each=in_each, area=area})
end

function add_add_craft(name, count, wait)
    table.insert(global.action_queue,
        {cmd="add_craft", handler=add_craft,
         name=name, count=count, wait=wait, queued=false})
end

function add_collect_from(name, item, inv_count, max_per_machine, area)
    -- inv_count => amount to have in inventory after.
    table.insert(global.action_queue,
        {cmd="collect_from", handler=collect_from,
         name=name, item=item,
         area=area,
         inv_count=inv_count, max_per_machine=max_per_machine,
        })
end

function add_wait_inventory(item, inv_count)
    table.insert(global.action_queue,
        {cmd="wait_inventory",
         handler= function(player, action)
            -- TODO have global wait counter.
            local count = player.get_item_count(item)
            if count < inv_count then
                game.print("Waiting for " .. inv_count .. " (have " .. count .. ")")
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
    table.insert(global.action_queue,
        {cmd="wait",
         handler= function(player, action)
            game.print("Waiting " .. action.ticks .. " tick(s) " .. "@" .. game.tick .. ": " .. action.msg)
            global.next_check = game.tick + action.ticks
            return true
         end,
         ticks=ticks, msg=msg})
end

-------------------
------ Setup ------
-------------------

script.on_event("start-stop-speedrun", function(event)
    global.speedrunRunning = not global.speedrunRunning
    game.print((global.speedrunRunning and "Starting" or "Stopping") .. " Speedrun")
    if global.speedrunRunning then
        if global.speedRunSetupComplete ~= true then
            runOnce()
        end
    end
end)

function runOnce()
--    global.speedrunRunning = false
    global.speedRunSetupComplete = true

    global.next_check = 0

    if not global.action_queue then
        global.action_queue = {}
    end

    game.print("Adding actions to queue")

    game.players[1].surface.always_day=true

    -- TODO change_game_speed handler/action
    game.speed = 5

    add_run_to(0, 1.5)

--- Setup early game shortcuts
    function add_early_mine_coal(count)
        add_mine_at(0, -1, "coal", count)
    end

    function add_early_mine_stone(count)
        add_mine_at(2, -1, "stone", count)
    end

    add_early_mine_coal(2)
    mine_two_coal = get_action()

    add_early_mine_stone(2)
    mine_two_stone = get_action()

    add_early_mine_stone(3)
    mine_three_stone = get_action()

    function early_iron(pre_stone, post_stone, post_craft_action, y)
        add_early_mine_stone(pre_stone)
        add_collect_from("stone-furnace", "iron-plate",   9, 1000,  {{0, 4}, {0, 16}})
        add_add_craft("burner-mining-drill", 1, false)

        add_early_mine_stone(post_stone)
        add_add_craft("stone-furnace", 1, false)

        add_action(post_craft_action)
        add_wait_inventory("stone-furnace", 1)

        add_build_at("burner-mining-drill",   2, y, defines.direction.west)
        add_build_at("stone-furnace",         0, y, defines.direction.west)
    end
----

---- First iron furnace
    add_build_at("burner-mining-drill", 2, 4, defines.direction.west)
    add_build_at("stone-furnace",       0, 4, defines.direction.west)

    --Fuel
    add_early_mine_coal(1)
    add_insert_in("burner-mining-drill", "coal", 1,   2, 4)
    add_early_mine_coal(1)
    add_insert_in("stone-furnace",       "coal", 1,   0, 4)

---- 2nd Iron Furnace

    early_iron(5, 5, mine_two_coal, 6)

--- Fuel everything up
    add_insert_in("burner-mining-drill", "coal", 1,   2, 4)
    add_insert_in("burner-mining-drill", "coal", 1,   2, 6)

    add_early_mine_coal(2)
    add_insert_in("stone-furnace",       "coal", 1,   0, 4)
    add_insert_in("stone-furnace",       "coal", 1,   0, 6)

    add_early_mine_coal(2)
    add_insert_in("burner-mining-drill", "coal", 1,   2, 4)
    add_insert_in("burner-mining-drill", "coal", 1,   2, 6)

---- 1st & 2nd coal miners
    add_early_mine_stone(6)
    add_collect_from("stone-furnace", "iron-plate",   9, 1000,  {{0, 4}, {0, 16}})
    add_add_craft("burner-mining-drill", 1, false)

    add_early_mine_stone(5)
    add_collect_from("stone-furnace", "iron-plate",   9, 1000,  {{0, 4}, {0, 16}})
    add_add_craft("burner-mining-drill", 1, false)

    -- finish craft
    add_early_mine_coal(4)

    add_build_at("burner-mining-drill",               -1, -3, defines.direction.west)
    add_build_at("burner-mining-drill",               -3, -3, defines.direction.east)
    add_insert_in("burner-mining-drill", "coal", 1,   -1, -3)
    add_insert_in("burner-mining-drill", "coal", 1,   -3, -3)

---- Refuel iron
    add_early_mine_coal(4)
    add_insert_in("burner-mining-drill", "coal", 2,   2, 4)
    add_insert_in("burner-mining-drill", "coal", 2,   2, 6)
    add_insert_in("stone-furnace",       "coal", 1,   0, 4)
    add_insert_in("stone-furnace",       "coal", 1,   0, 6)

---- 3rd iron
    early_iron(6, 6, mine_two_stone, 8)

    add_collect_from("burner-mining-drill", "coal", 9, 1000,  {{-3, -7}, {-1, -3}})
    add_insert_in_each("burner-mining-drill", "coal", 2,   {{2, 4}, {2, 8}})
    add_insert_in_each("stone-furnace",       "coal", 1,   {{0, 4}, {0, 8}})

---- A couple of trees
    add_mine_at(-2, 1, "tree", 1, "tree")
    add_mine_at(-1, 1, "tree", 1, "tree")
    add_mine_at( 0, 1, "tree", 1, "tree")
    -- 13 wood

---- 1st Stone
    -- TODO add_inventory_check(stone, 5)
    add_collect_from("stone-furnace", "iron-plate",   9, 1000,  {{0, 4}, {0, 16}})
    add_add_craft("burner-mining-drill", 1, false)

    add_add_craft("wooden-chest", 3, false)
    add_early_mine_stone(3)

    add_build_at("burner-mining-drill",            4, -1, defines.direction.south)
    add_build_at("wooden-chest",                   4,  0, defines.direction.west)

    add_collect_from("burner-mining-drill", "coal", 4, 1000,  {{-3, -7}, {-1, -3}})
    add_insert_in("burner-mining-drill", "coal", 4,   4, -1)


---- Fuel all miners
    -- small wait
    add_early_mine_stone(2) -- should have 5 now

    add_collect_from("burner-mining-drill", "coal", 12, 1000,  {{-3, -7}, {-1, -3}})

    -- Technicall 3 * (3+2) = 15, but likely only need ~10 fuel
    -- Fuel every ~26s for burner-mining-drill, Fuel every ~45s for stone-furnace
    add_insert_in_each("burner-mining-drill", "coal", 3,   {{2, 4}, {2, 8}})
    add_insert_in_each("stone-furnace",       "coal", 2,   {{0, 4}, {0, 8}})


---- More coal (more is better)
    add_early_mine_stone(2)

    add_collect_from("stone-furnace", "iron-plate",   9, 1000,  {{0, 4}, {0, 16}})
    add_add_craft("burner-mining-drill", 1, false)

    add_early_mine_stone(3)
    add_collect_from("stone-furnace", "iron-plate",   9, 1000,  {{0, 4}, {0, 16}})
    add_add_craft("burner-mining-drill", 1, false) -- 4 now

    add_early_mine_stone(2)
    add_wait_inventory("burner-mining-drill", 2)

    add_build_at("burner-mining-drill",               -1, -5, defines.direction.west)
    add_build_at("burner-mining-drill",               -3, -5, defines.direction.east)

    -- ~tick 8600
    add_wait(1, "coal-setup-34") -- wait one tick for drills to be constructed

    -- TODO print_inventory
    add_collect_from("burner-mining-drill", "coal", 2, 1000,  {{-3, -7}, {-1, -3}})

    add_insert_in("burner-mining-drill", "coal", 1,   -1, -5)
    add_insert_in("burner-mining-drill", "coal", 1,   -3, -5)

---- 4th Iron
    early_iron(3, 5, mine_three_stone, 10)

    add_collect_from("burner-mining-drill", "coal", 12, 1000,  {{-3, -7}, {-1, -3}})
    add_insert_in_each("burner-mining-drill", "coal", 3,   {{2, 4}, {2, 10}})
    add_insert_in_each("stone-furnace",       "coal", 2,   {{0, 4}, {0, 10}})

---- 5th Iron
    add_collect_from("wooden-chest", "stone",  10, 1000,  {{4, 0}, {9, 1}})

    early_iron(0, 0, mine_three_stone, 12)

    add_collect_from("burner-mining-drill", "coal", 15, 1000,  {{-3, -7}, {-1, -3}})
    add_insert_in_each("burner-mining-drill", "coal", 3,   {{2, 4}, {2, 12}})
    add_insert_in_each("stone-furnace",       "coal", 2,   {{0, 4}, {0, 12}})

---- 2nd Stone
    add_early_mine_stone(1)

    add_collect_from("wooden-chest",  "stone",        5, 1000,  {{4, 0}, {9, 1}})
    add_collect_from("stone-furnace", "iron-plate",   9, 1000,  {{0, 4}, {0, 16}})

    add_add_craft("burner-mining-drill", 1, false)

    add_early_mine_stone(2)
    add_wait_inventory("burner-mining-drill", 1)

    add_build_at("burner-mining-drill",            6, -1, defines.direction.south)
    add_build_at("wooden-chest",                   6,  0, defines.direction.west)

    add_collect_from("burner-mining-drill", "coal", 6, 1000,  {{-3, -7}, {-1, -3}})
    add_insert_in_each("burner-mining-drill", "coal", 3,      {{4, -1}, {6, -1}})

---- 6th Iron
    add_early_mine_stone(3)
    add_collect_from("wooden-chest",  "stone",        5, 1000,  {{4, 0}, {9, 1}})
    add_collect_from("stone-furnace", "iron-plate",   9, 1000,  {{0, 4}, {0, 16}})

    add_add_craft("burner-mining-drill", 1, false)

    add_early_mine_stone(2)
    add_collect_from("wooden-chest",  "stone",        5, 1000,  {{4, 0}, {9, 1}})
    add_add_craft("stone-furnace", 1, false)

    add_early_mine_coal(2)
    add_collect_from("burner-mining-drill", "coal", 20, 1000,  {{-3, -7}, {-1, -3}})

    -- TODO run_back with actions in the middle?
    add_run_to(-1.5, 5)
    add_wait_inventory("stone-furnace", 1)

    add_build_at("burner-mining-drill",   2, 14, defines.direction.west)
    add_build_at("stone-furnace",         0, 14, defines.direction.west)
    add_insert_in_each("burner-mining-drill", "coal", 3,   {{2, 4}, {2, 14}})
    add_insert_in_each("stone-furnace",       "coal", 2,   {{0, 4}, {0, 14}})

    add_run_to(0.5, 1.5)
    -- Done


--]]

    -- ~5 coal | ~5 coal, ~13 stone, ~9 iron
    -- ~95 seconds

    add_wait(1, "end") -- Get finish time

    game.print("Action Queue: " .. #global.action_queue .. " actions")
end

--script.on_load(function()
--  runOnce()
--end) .. serpent.line(action))
script.on_event(defines.events.on_tick, function(event)
    if global.speedrunRunning then
        if (game.tick > 0 and game.tick % 500 == 0) then
            local pos = game.players[1].position
            -- TODO action index along with queue size
            game.print(
                "Tick " .. (game.tick / 100)
                .. ", Pos: " .. string.format("%.1f, %.1f", pos.x, pos.y)
                .. ", ActionQueue: " .. #global.action_queue
                   .. " top: " .. (#global.action_queue > 0 and global.action_queue[1].cmd or "None")
            )
        end
        action_check(game.players[1])

        if #global.action_queue == 0 then
            game.speed = 0.02
        end
    end
end)


-----------
