local decoder = require("cc.audio.dfpwm").make_decoder()
local Music = {}
Music.api_base_url = "https://ipod-2to6magyna-uc.a.run.app/"
Music.version = "2.1"
Music.state = {
    playing = false,
    queue = {},
    now_playing = nil,
    looping = 0,
    volume = 1.5,
    is_loading = false,
    is_error = false,
    search_results = nil,
    search_error = false,
    last_search = nil,
}
local speakers = { peripheral.find("speaker") }
local playing_id = nil
local last_download_url = nil
local last_search_url = nil
local playing_status = 0
local needs_next_chunk = 0
local player_handle = nil
local start = nil
local size = nil
local buffer
function Music.startSearch(query)
    if not query or #query == 0 then
        Music.state.last_search = nil
        Music.state.search_results = nil
        Music.state.search_error = false
        Music.state.search_error_msg = nil
        last_search_url = nil
        return
    end
    Music.state.last_search = query
    Music.state.search_results = nil
    Music.state.search_error = false
    Music.state.search_error_msg = nil
    last_search_url = Music.api_base_url .. "?v=" .. Music.version .. "&search=" .. textutils.urlEncode(query)
    http.request(last_search_url)
end
function Music.playSong(song)
    for _, speaker in ipairs(speakers) do
        pcall(speaker.stop)
    end
    Music.state.playing = true
    Music.state.is_error = false
    Music.state.now_playing = song
    playing_id = nil
    os.queueEvent("playback_stopped")
    os.queueEvent("audio_update")
end
function Music.stopSong()
    Music.state.playing = false
    for _, speaker in ipairs(speakers) do
        pcall(speaker.stop)
    end
    playing_id = nil
    if player_handle then
        pcall(player_handle.close)
        player_handle = nil
    end
    Music.state.is_loading = false
    Music.state.is_error = false
    os.queueEvent("playback_stopped")
    os.queueEvent("audio_update")
end
function Music.pauseSong()
    Music.state.playing = false
    for _, speaker in ipairs(speakers) do
        pcall(speaker.stop)
    end
    os.queueEvent("playback_stopped")
    os.queueEvent("audio_update")
end
function Music.resumeSong()
    if Music.state.now_playing then
        Music.state.playing = true
        os.queueEvent("audio_update")
    end
end
function Music.togglePlay()
    if Music.state.playing then
        Music.pauseSong()
    else
        if Music.state.now_playing then
            if playing_id == Music.state.now_playing.id and player_handle then
                Music.resumeSong()
            else
                Music.playSong(Music.state.now_playing)
            end
        elseif #Music.state.queue > 0 then
            local next = Music.state.queue[1]
            table.remove(Music.state.queue, 1)
            Music.playSong(next)
        end
    end
    os.queueEvent("audio_update")
end
function Music.skipSong()
    Music.state.is_error = false
    for _, speaker in ipairs(speakers) do
        pcall(speaker.stop)
    end
    if player_handle then
        pcall(player_handle.close)
        player_handle = nil
    end
    if #Music.state.queue > 0 then
        if Music.state.looping == 1 then
            table.insert(Music.state.queue, Music.state.now_playing)
        end
        Music.state.now_playing = Music.state.queue[1]
        table.remove(Music.state.queue, 1)
        playing_id = nil
        Music.state.playing = true
    else
        Music.state.now_playing = nil
        Music.state.playing = false
        Music.state.is_loading = false
        Music.state.is_error = false
        playing_id = nil
    end
    os.queueEvent("playback_stopped")
    os.queueEvent("audio_update")
end
function Music.refreshSpeakers()
    speakers = { peripheral.find("speaker") }
end
function Music.hasSpeaker()
    Music.refreshSpeakers()
    return #speakers > 0
end
function Music.audioLoop()
    while true do
        Music.refreshSpeakers()
        if #speakers == 0 then
            sleep(1.0)
        elseif Music.state.playing and Music.state.now_playing then
            local thisid = Music.state.now_playing.id
            if playing_id ~= thisid then
                playing_id = thisid
                last_download_url = Music.api_base_url .. "?v=" .. Music.version .. "&id=" .. textutils.urlEncode(playing_id) .. "&t=" .. os.epoch("utc")
                playing_status = 0
                needs_next_chunk = 1
                http.request({url = last_download_url, binary = true})
                Music.state.is_loading = true
                os.queueEvent("redraw_screen")
                os.queueEvent("audio_update")
            elseif playing_status == 1 and needs_next_chunk == 1 then
                while true do
                    local chunk = player_handle.read(size)
                    if not chunk then
                        if Music.state.looping == 2 or (Music.state.looping == 1 and #Music.state.queue == 0) then
                            playing_id = nil
                        elseif Music.state.looping == 1 and #Music.state.queue > 0 then
                            table.insert(Music.state.queue, Music.state.now_playing)
                            Music.state.now_playing = Music.state.queue[1]
                            table.remove(Music.state.queue, 1)
                            playing_id = nil
                        else
                            if #Music.state.queue > 0 then
                                Music.state.now_playing = Music.state.queue[1]
                                table.remove(Music.state.queue, 1)
                                playing_id = nil
                            else
                                Music.state.now_playing = nil
                                Music.state.playing = false
                                playing_id = nil
                                Music.state.is_loading = false
                                Music.state.is_error = false
                            end
                        end
                        os.queueEvent("redraw_screen")
                        player_handle.close()
                        needs_next_chunk = 0
                        break
                    else
                        if start then
                            chunk, start = start .. chunk, nil
                            size = size + 4
                        end
                        buffer = decoder(chunk)
                        local fn = {}
                        for i, speaker in ipairs(speakers) do
                            fn[i] = function()
                                local name = peripheral.getName(speaker)
                                while not speaker.playAudio(buffer, math.min(1.0, Music.state.volume)) do
                                    parallel.waitForAny(
                                        function()
                                            repeat until select(2, os.pullEvent("speaker_audio_empty")) == name
                                        end,
                                        function()
                                            os.pullEvent("playback_stopped")
                                        end
                                    )
                                    if not Music.state.playing or playing_id ~= thisid then
                                        return
                                    end
                                end
                            end
                        end
                        local ok, err = pcall(parallel.waitForAll, table.unpack(fn))
                        if not ok then
                            needs_next_chunk = 2
                            Music.state.is_error = true
                            break
                        end
                        if not Music.state.playing and Music.state.now_playing and playing_id == thisid then
                            repeat
                                local event = os.pullEvent("audio_update")
                            until Music.state.playing or playing_id ~= thisid or not Music.state.now_playing
                        end
                        if not Music.state.playing or playing_id ~= thisid then
                            if player_handle then
                                pcall(player_handle.close)
                                player_handle = nil
                            end
                            break
                        end
                    end
                end
                os.queueEvent("audio_update")
            end
        end
        os.pullEvent("audio_update")
    end
end
function Music.httpLoop()
    while true do
        parallel.waitForAny(
            function()
                local event, url, handle = os.pullEvent("http_success")
                if url == last_search_url then
                    local decoded = textutils.unserialiseJSON(handle.readAll())
                    if type(decoded) == "table" then
                        local filtered = {}
                        for _, res in ipairs(decoded) do
                            local name = res.name or ""
                            if not name:match("^►") and not name:lower():match("patreon") and not name:lower():match("hosting") then
                                table.insert(filtered, res)
                            end
                        end
                        Music.state.search_results = filtered
                    else
                        Music.state.search_results = nil
                    end
                    Music.state.search_error = false
                    Music.state.search_error_msg = nil
                    os.queueEvent("redraw_screen")
                elseif url == last_download_url then
                    Music.state.is_loading = false
                    player_handle = handle
                    start = handle.read(4)
                    size = 16 * 1024 - 4
                    playing_status = 1
                    os.queueEvent("redraw_screen")
                    os.queueEvent("audio_update")
                end
            end,
            function()
                local event, url, err = os.pullEvent("http_failure")
                if url == last_search_url then
                    Music.state.search_error = true
                    Music.state.search_error_msg = err or "Connection failed"
                    os.queueEvent("redraw_screen")
                elseif url == last_download_url then
                    Music.state.is_loading = false
                    Music.state.is_error = true
                    Music.state.playing = false
                    playing_id = nil
                    os.queueEvent("redraw_screen")
                    os.queueEvent("audio_update")
                end
            end
        )
    end
end
return Music