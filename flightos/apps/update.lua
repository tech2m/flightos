local UI = require("ui")
local app = {}
app.name = "Update"
local waiting_for_input = false
local update_status = ""
local status_color = UI.colors.text
local entered_url = ""
local updateCoroutine = nil
function app.draw(target, service)
    local w, h = target.getSize()
    UI.centerText(target, 4, "FlightOS System Update", UI.colors.header)
    UI.writeAt(target, 2, 6, "Enter update link (Pastebin, dpaste, etc.):", UI.colors.textDim)
    target.setBackgroundColor(colors.gray)
    target.setTextColor(colors.white)
    target.setCursorPos(2, 8)
    target.write(string.rep(" ", w - 2))
    UI.writeAt(target, 3, 8, entered_url ~= "" and entered_url or "Click to enter URL...", entered_url ~= "" and colors.white or colors.lightGray, colors.gray)
    if update_status ~= "" then
        UI.centerText(target, 11, update_status, status_color)
    end
    UI.centerText(target, 14, "Warning: Updating will restart FlightOS", colors.yellow)
end
local function performUpdate(url, target)
    update_status = "Resolving URL..."
    status_color = colors.yellow
    os.queueEvent("redraw_screen")
    sleep(0.5)
    local cleanUrl = url
    if not url:match("^https?://") then
        if #url == 8 and url:match("^%w+$") then
            cleanUrl = "https://pastebin.com/raw/" .. url
        else
            cleanUrl = "https://" .. url
        end
    else
        if url:match("pastebin%.com/[%w]+$") and not url:match("pastebin%.com/raw/") then
            local code = url:match("pastebin%.com/([%w]+)$")
            if code then cleanUrl = "https://pastebin.com/raw/" .. code end
        elseif url:match("dpaste%.com/[%w]+$") and not url:match("%.txt$") then
            cleanUrl = url .. ".txt"
        end
    end
    update_status = "Downloading update..."
    os.queueEvent("redraw_screen")
    sleep(0.5)
    local response = http.get(cleanUrl)
    if not response then
        update_status = "Download failed! URL invalid or blocked."
        status_color = colors.red
        os.queueEvent("redraw_screen")
        return
    end
    local code = response.readAll()
    response.close()
    if not code or #code < 50 then
        update_status = "Error: Downloaded file is empty or invalid"
        status_color = colors.red
        os.queueEvent("redraw_screen")
        return
    end
    update_status = "Download complete! Installing..."
    status_color = colors.lime
    os.queueEvent("redraw_screen")
    sleep(1.0)
    local f = fs.open("update_temp.lua", "w")
    f.write(code)
    f.close()
    local pf = fs.open("flightos/update_pending.txt", "w")
    pf.write("update_temp.lua")
    pf.close()
    os.queueEvent("flightos_update")
end
function app.handleEvent(event, service, cfg, target)
    if waiting_for_input then return false end
    if event[1] == "mouse_click" and event[4] == 9 then
        local mx = event[3]
        local w, h = term.getSize()
        if mx >= 2 and mx <= w - 1 then
            waiting_for_input = true
            target.setCursorPos(3, 8)
            target.setBackgroundColor(colors.white)
            target.setTextColor(colors.black)
            target.write(string.rep(" ", w - 4))
            target.setCursorPos(3, 8)
            target.setCursorBlink(true)
            local prev = term.redirect(target)
            local input = read()
            term.redirect(prev)
            target.setCursorBlink(false)
            waiting_for_input = false
            if input and #input > 0 then
                entered_url = input
                updateCoroutine = coroutine.create(function()
                    performUpdate(input, target)
                end)
                coroutine.resume(updateCoroutine)
            end
            return true
        end
    end
    if updateCoroutine and coroutine.status(updateCoroutine) ~= "dead" then
        local ok, result = coroutine.resume(updateCoroutine, table.unpack(event))
        if not ok then
            update_status = "Error: " .. tostring(result)
            status_color = colors.red
            updateCoroutine = nil
        end
        return true
    end
    return false
end
return app