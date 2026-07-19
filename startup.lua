if _G.FLIGHTOS_RUNNING or (shell and shell.parentShell and shell.parentShell()) then
    return
end
term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.cyan)
print("FlightOS Bootloader")
term.setTextColor(colors.gray)
print("Hold any key to enter CraftOS console...")
print("")
local timer = os.startTimer(2)
local bypass = false
while true do
    local event, p1 = os.pullEvent()
    if event == "key" then
        bypass = true
        break
    elseif event == "timer" and p1 == timer then
        break
    end
end
if bypass then
    term.setTextColor(colors.yellow)
    print("Bypass activated. Entering CraftOS console.")
    print("Type 'flightos/main' to start FlightOS manually.")
    term.setTextColor(colors.white)
else
    while true do
        term.clear()
        term.setCursorPos(1, 1)
        local startTime = os.clock()
        local ok, success = pcall(function()
            return shell.run("flightos/main")
        end)
        local failed = (not ok) or (not success)
        if fs.exists("flightos/update_pending.txt") then
            local f = fs.open("flightos/update_pending.txt", "r")
            local updateScript = f.readAll()
            f.close()
            fs.delete("flightos/update_pending.txt")
            term.clear()
            term.setCursorPos(1, 1)
            term.setTextColor(colors.yellow)
            print("Installing update...")
            sleep(1.0)
            shell.run(updateScript)
            if fs.exists(updateScript) then
                fs.delete(updateScript)
            end
        else
            if not ok and success == "Terminated" then
                term.setTextColor(colors.yellow)
                print("\nFlightOS terminated by user.")
                print("Entering CraftOS console.")
                term.setTextColor(colors.white)
                break
            end
            if failed then
                term.setTextColor(colors.red)
                print("FlightOS crashed or failed to start.")
                if not ok then
                    print("Error: " .. tostring(success))
                end
                local duration = os.clock() - startTime
                if duration < 3.0 then
                    term.setTextColor(colors.yellow)
                    print("\nPress any key to enter console...")
                    term.setTextColor(colors.white)
                    os.pullEvent("key")
                    break
                else
                    term.setTextColor(colors.gray)
                    print("\nRestarting in 5 seconds...")
                    print("Hold Ctrl+T to abort.")
                    term.setTextColor(colors.white)
                    sleep(5)
                end
            end
        end
    end
end