local Config = require("config")
local Music = require("music_service")
local NetServer = {}
local CHANNEL = 42
local service, cfg
local modem
local broadcastTimer
function NetServer.init(svc, config)
    service = svc
    cfg = config
    modem = peripheral.find("modem", function(name, m)
        return m.isWireless()
    end)
    if modem then
        modem.open(CHANNEL)
    end
end
local function buildTelemetry()
    local d = service.data
    return {
        type = "telemetry",
        ship_id = os.getComputerID(),
        data = {
            roll = d.roll,
            pitch = d.pitch,
            x = d.x, y = d.y, z = d.z,
            auto_enabled = d.auto_enabled,
            enabled = d.enabled,
            manual_active = d.manual_active,
            manual_propeller = d.manual_propeller,
            manual_thrust = d.manual_thrust,
            manual_steering = d.manual_steering,
            aux_enabled = d.aux_enabled,
            aux_left_ready = d.aux_left_ready,
            aux_right_ready = d.aux_right_ready,
            aux_thrust = d.aux_thrust,
            dist = d.dist,
            progress = d.progress,
            fl = d.fl, fr = d.fr,
            bl = d.bl, br = d.br,
            rollOut = d.rollOut,
            pitchOut = d.pitchOut,
            music = {
                playing = Music.state.playing,
                is_loading = Music.state.is_loading,
                is_error = Music.state.is_error,
                volume = Music.state.volume,
                now_playing = Music.state.now_playing and {
                    name = Music.state.now_playing.name,
                    artist = Music.state.now_playing.artist,
                } or nil,
                queue_length = #Music.state.queue,
                queue = (function()
                    local queue = {}
                    for i = 1, math.min(3, #Music.state.queue) do
                        queue[i] = { name = Music.state.queue[i].name }
                    end
                    return queue
                end)(),
                looping = Music.state.looping,
                search_results = Music.state.search_results and (function()
                    local results = {}
                    for i = 1, math.min(5, #Music.state.search_results) do
                        local result = Music.state.search_results[i]
                        results[i] = {
                            name = result.name,
                            artist = result.artist,
                            type = result.type,
                        }
                    end
                    return results
                end)() or nil,
                last_search = Music.state.last_search,
                search_error = Music.state.search_error,
                search_error_msg = Music.state.search_error_msg,
            },
        },
        cfg = {
            target_x = cfg.target_x,
            target_y = cfg.target_y,
            target_z = cfg.target_z,
            auto_speed_max = cfg.auto_speed_max,
            auto_steer_max = cfg.auto_steer_max,
            auto_steer_kp = cfg.auto_steer_kp,
            auto_steer_kd = cfg.auto_steer_kd,
            speed_invert = cfg.speed_invert,
            steer_invert = cfg.steer_invert,
        }
    }
end
local function handleCommand(msg)
    if type(msg) ~= "table" or msg.type ~= "cmd" then return end
    if service.data.system_enabled == false then return end
    if msg.cmd == "set_target" then
        cfg.target_x = tonumber(msg.x) or cfg.target_x
        cfg.target_y = tonumber(msg.y) or cfg.target_y
        cfg.target_z = tonumber(msg.z) or cfg.target_z
        Config.save(cfg)
        if service.applyConfig then service.applyConfig(cfg) end
        os.queueEvent("remote_config_changed")
    elseif msg.cmd == "toggle_auto" then
        service.setAutoEnabled(not service.data.auto_enabled)
    elseif msg.cmd == "toggle_stab" then
        service.setEnabled(not service.data.enabled)
    elseif msg.cmd == "toggle_aux" then
        if service.setAuxEnabled then
            service.setAuxEnabled(not service.data.aux_enabled)
        end
    elseif msg.cmd == "set_config" then
        local key = msg.key
        local val = msg.value
        if key and val ~= nil then
            if key == "auto_speed_max" or key == "auto_steer_max" or key == "auto_steer_kp" or key == "auto_steer_kd" then
                cfg[key] = tonumber(val) or cfg[key]
            elseif key == "speed_invert" or key == "steer_invert" then
                if type(val) == "string" then
                    cfg[key] = (val:lower() == "true")
                else
                    cfg[key] = val
                end
            else
                cfg[key] = val
            end
            Config.save(cfg)
            if service.applyConfig then service.applyConfig(cfg) end
            os.queueEvent("remote_config_changed")
        end
    elseif msg.cmd == "test_motors" then
        if service.startMotorTest then service.startMotorTest() end
    elseif msg.cmd == "music" then
        if msg.action == "search" then
            Music.startSearch(msg.query)
        elseif msg.action == "result" then
            local result = Music.state.search_results and Music.state.search_results[tonumber(msg.index)]
            if result then
                if msg.mode == "play_now" then
                    Music.state.queue = {}
                    if result.type == "playlist" then
                        for i = 2, #result.playlist_items do
                            table.insert(Music.state.queue, result.playlist_items[i])
                        end
                        Music.playSong(result.playlist_items[1])
                    else
                        Music.playSong(result)
                    end
                elseif msg.mode == "play_next" then
                    if result.type == "playlist" then
                        for i = #result.playlist_items, 1, -1 do
                            table.insert(Music.state.queue, 1, result.playlist_items[i])
                        end
                    else
                        table.insert(Music.state.queue, 1, result)
                    end
                elseif msg.mode == "queue" then
                    if result.type == "playlist" then
                        for i = 1, #result.playlist_items do
                            table.insert(Music.state.queue, result.playlist_items[i])
                        end
                    else
                        table.insert(Music.state.queue, result)
                    end
                end
            end
        elseif msg.action == "toggle" then
            Music.togglePlay()
        elseif msg.action == "skip" then
            Music.skipSong()
        elseif msg.action == "stop" then
            Music.stopSong()
        elseif msg.action == "loop" then
            Music.state.looping = (Music.state.looping + 1) % 3
            os.queueEvent("audio_update")
        elseif msg.action == "volume" then
            Music.state.volume = math.max(0, math.min(3, tonumber(msg.value) or Music.state.volume))
            os.queueEvent("audio_update")
        end
    elseif msg.cmd == "ping" then
        if modem then
            modem.transmit(CHANNEL, CHANNEL, {
                type = "pong",
                ship_id = os.getComputerID(),
            })
        end
    end
end
function NetServer.loop()
    if not modem then return end
    broadcastTimer = os.startTimer(0.5)
    while true do
        local event = {os.pullEvent()}
        if event[1] == "modem_message" and event[3] == CHANNEL then
            local ok, msg = pcall(function() return event[5] end)
            if ok and type(msg) == "table" then
                handleCommand(msg)
            end
        elseif event[1] == "timer" and event[2] == broadcastTimer then
            local telem = buildTelemetry()
            modem.transmit(CHANNEL, CHANNEL, telem)
            broadcastTimer = os.startTimer(0.5)
        end
    end
end
return NetServer