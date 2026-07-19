local UI = require("ui")
local Music = require("music_service")
local app = {}
app.name = "Music"
local subtab = 1
local waiting_for_input = false
local in_search_result = false
local clicked_result = nil
function app.draw(target, service)
    local w, h = target.getSize()
    target.setBackgroundColor(colors.black)
    for y = 3, h do
        target.setCursorPos(1, y)
        target.clearLine()
    end
    target.setCursorPos(1, 2)
    target.setBackgroundColor(colors.gray)
    target.clearLine()
    local subtabs = {" Now Playing ", " Search "}
    for i = 1, #subtabs do
        if subtab == i then
            target.setTextColor(colors.black)
            target.setBackgroundColor(colors.white)
        else
            target.setTextColor(colors.white)
            target.setBackgroundColor(colors.gray)
        end
        target.setCursorPos(math.floor((w / #subtabs) * (i - 0.5)) - math.ceil(#subtabs[i] / 2) + 1, 2)
        target.write(subtabs[i])
    end
    if not Music.hasSpeaker() then
        UI.writeAt(target, 2, 4, "Speaker not connected", colors.red)
        return
    end
    if subtab == 1 then
        app.drawNowPlaying(target, w, h)
    else
        app.drawSearch(target, w, h)
    end
end
function app.drawNowPlaying(target, w, h)
    local state = Music.state
    if state.now_playing then
        local name = state.now_playing.name
        local artist = state.now_playing.artist
        if name:match("^►") or name:lower():match("patreon") or name:lower():match("hosting") then
            name = "Playing..."
            artist = "Music Stream"
        end
        UI.writeAt(target, 2, 4, name, colors.white)
        UI.writeAt(target, 2, 5, artist, colors.lightGray)
    else
        UI.writeAt(target, 2, 4, "Not playing", colors.lightGray)
    end
    if state.is_loading then
        UI.writeAt(target, 2, 6, "Loading...", colors.yellow)
    elseif state.is_error then
        UI.writeAt(target, 2, 6, "Network error", colors.red)
    end
    local playLabel = state.playing and " Pause " or " Play "
    UI.drawButton(target, 2, 8, playLabel, state.playing)
    local hasQueue = state.now_playing ~= nil or #state.queue > 0
    local skipBg = hasQueue and colors.blue or colors.gray
    UI.writeAt(target, 10, 8, " Skip ", colors.white, skipBg)
    local loopLabel = " Loop Off "
    if state.looping == 1 then loopLabel = " Loop Q "
    elseif state.looping == 2 then loopLabel = " Loop S " end
    UI.writeAt(target, 18, 8, loopLabel, state.looping > 0 and colors.black or colors.white, state.looping > 0 and colors.white or colors.gray)
    UI.writeAt(target, 2, 10, "Volume:", colors.lightGray)
    UI.drawProgressBar(target, 10, 10, 15, state.volume, 3.0, colors.white)
    UI.writeAt(target, 26, 10, string.format("%d%%", math.floor(100 * (state.volume / 3) + 0.5)), colors.white)
    if #state.queue > 0 then
        UI.writeAt(target, 2, 12, "Queue:", colors.cyan)
        for i = 1, math.min(3, #state.queue) do
            local item = state.queue[i]
            UI.writeAt(target, 2, 12 + i, string.format("%d. %s", i, item.name), colors.white)
        end
    end
end
function app.drawSearch(target, w, h)
    local state = Music.state
    if in_search_result then
        app.drawSearchResultMenu(target, w, h)
        return
    end
    target.setBackgroundColor(colors.gray)
    target.setTextColor(colors.white)
    target.setCursorPos(2, 4)
    target.write(string.rep(" ", w - 2))
    UI.writeAt(target, 3, 4, state.last_search or "Click to search...", colors.black, colors.white)
    if state.search_results then
        for i = 1, math.min(5, #state.search_results) do
            local r = state.search_results[i]
            UI.writeAt(target, 2, 5 + (i-1)*2, string.format("%d. %s", i, r.name), colors.white)
            UI.writeAt(target, 2, 6 + (i-1)*2, string.format("   %s", r.artist), colors.lightGray)
        end
    else
        if state.search_error then
            local msg = "Network error"
            if state.search_error_msg then
                msg = msg .. ": " .. state.search_error_msg
            end
            UI.writeAt(target, 2, 6, msg, colors.red)
        elseif state.last_search then
            UI.writeAt(target, 2, 6, "Searching...", colors.yellow)
        else
            UI.writeAt(target, 2, 6, "Tip: Paste YouTube links", colors.lightGray)
        end
    end
end
function app.drawSearchResultMenu(target, w, h)
    local state = Music.state
    local res = state.search_results[clicked_result]
    if not res then return end
    UI.writeAt(target, 2, 4, res.name, colors.white)
    UI.writeAt(target, 2, 5, res.artist, colors.lightGray)
    UI.writeAt(target, 2, 7, "Play Now", colors.white, colors.blue)
    UI.writeAt(target, 2, 9, "Play Next", colors.white, colors.blue)
    UI.writeAt(target, 2, 11, "Add to Queue", colors.white, colors.blue)
    UI.writeAt(target, 2, 13, "Cancel", colors.white, colors.gray)
end
function app.handleEvent(event, service, cfg, target)
    if not Music.hasSpeaker() then
        return false
    end
    local state = Music.state
    if waiting_for_input then
        return false
    end
    if event[1] == "mouse_click" then
        local mx = event[3]
        local my = event[4]
        local w, h = term.getSize()
        if my == 3 then
            if mx < w / 2 then
                subtab = 1
                in_search_result = false
            else
                subtab = 2
            end
            return true
        end
        if subtab == 1 then
            if my == 9 then
                if mx >= 2 and mx <= 8 then
                    Music.togglePlay()
                    return true
                end
                if mx >= 10 and mx <= 16 then
                    Music.skipSong()
                    return true
                end
                if mx >= 18 and mx <= 26 then
                    state.looping = (state.looping + 1) % 3
                    return true
                end
            end
            if my == 11 and mx >= 10 and mx <= 25 then
                state.volume = (mx - 10) / 15 * 3.0
                return true
            end
        else
            if in_search_result then
                if my == 8 then
                    in_search_result = false
                    local res = state.search_results[clicked_result]
                    if res.type == "playlist" then
                        state.queue = {}
                        for i = 2, #res.playlist_items do
                            table.insert(state.queue, res.playlist_items[i])
                        end
                        Music.playSong(res.playlist_items[1])
                    else
                        Music.playSong(res)
                    end
                    subtab = 1
                    return true
                elseif my == 10 then
                    in_search_result = false
                    local res = state.search_results[clicked_result]
                    if res.type == "playlist" then
                        for i = #res.playlist_items, 1, -1 do
                            table.insert(state.queue, 1, res.playlist_items[i])
                        end
                    else
                        table.insert(state.queue, 1, res)
                    end
                    subtab = 1
                    return true
                elseif my == 12 then
                    in_search_result = false
                    local res = state.search_results[clicked_result]
                    if res.type == "playlist" then
                        for i = 1, #res.playlist_items do
                            table.insert(state.queue, res.playlist_items[i])
                        end
                    else
                        table.insert(state.queue, res)
                    end
                    subtab = 1
                    return true
                elseif my == 14 then
                    in_search_result = false
                    return true
                end
            else
                if my == 5 and mx >= 2 and mx <= w - 1 then
                    waiting_for_input = true
                    target.setCursorPos(3, 4)
                    target.setBackgroundColor(colors.white)
                    target.setTextColor(colors.black)
                    target.write(string.rep(" ", w - 4))
                    target.setCursorPos(3, 4)
                    target.setCursorBlink(true)
                    local prevTerm = term.redirect(target)
                    local input = read()
                    term.redirect(prevTerm)
                    target.setCursorBlink(false)
                    waiting_for_input = false
                    Music.startSearch(input)
                    return true
                end
                if state.search_results and my >= 6 and my <= 15 then
                    local idx = math.floor((my - 6) / 2) + 1
                    if state.search_results[idx] then
                        clicked_result = idx
                        in_search_result = true
                        return true
                    end
                end
            end
        end
    end
    return false
end
return app