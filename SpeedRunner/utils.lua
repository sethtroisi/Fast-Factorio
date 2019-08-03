-- Some simple utils moved here to declutter control.lua

-----------------------
---- General utils ----
-----------------------

function printAndQuit(msg)
    game.print(msg)
    -- TODO log more debug
    global.speedrunRunning = false
    game.speed = 0.02
end

function assertAndQuit(cond, msg)
    -- TODO print status
    assert(cond, msg)
end

-- quick and dirty, one depth clone
function table.clone(org)
  return {table.unpack(org)}
end

--------------------------
---- Factorio general ----
--------------------------

function floating_text(msg, pos)
    game.surfaces[1].create_entity{
        name="flying-text",
        text=msg,
        position=pos,
        color={r=0.15,g=0.4,b=1}
    }
end




-------------------
---- TAS utils ----
-------------------

-- These probably don't need to be changed so we're good to move them here

function set_checkpoint(ckpt)
    add_action({
         cmd="ckpt", ckpt=ckpt,
         handler=function(_, _)
             global.status.checkpoint = ckpt
             -- TODO print full status line
             game.print("  " .. ckpt)
             return true
         end,
    })
end

function add_change_speed(speed)
    add_action({
         cmd="game.speed", speed=speed,
         handler=function(_, _) game.speed = speed return true end,
    })
end


-----------------------
---- Setup stuff ------
-----------------------

script.on_event("start-stop-speedrun", function(event)
    global.speedrunRunning = not global.speedrunRunning
    game.print((global.speedrunRunning and "Starting" or "Stopping") .. " Speedrun")
    if global.speedrunRunning then
        if global.speedRunSetupComplete ~= true then
            runOnce()
        end
    end
end)

