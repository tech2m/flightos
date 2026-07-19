local UI = {}
UI.colors = {
    bg        = colors.black,
    tabActive = colors.blue,
    tabIdle   = colors.gray,
    tabText   = colors.white,
    tabTextDim= colors.lightGray,
    header    = colors.cyan,
    text      = colors.white,
    textDim   = colors.lightGray,
    accent    = colors.lime,
    warn      = colors.yellow,
    err       = colors.red,
    border    = colors.gray,
    btnBg     = colors.blue,
    btnText   = colors.white,
    inputBg   = colors.gray,
    inputText = colors.white,
}
function UI.clear(target)
    target = target or term
    target.setBackgroundColor(UI.colors.bg)
    target.setTextColor(UI.colors.text)
    target.clear()
end
function UI.drawTabBar(target, tabs, activeIdx, y)
    y = y or 1
    local w, _ = target.getSize()
    target.setCursorPos(1, y)
    target.setBackgroundColor(colors.black)
    target.clearLine()
    local x = 1
    local hitboxes = {}
    for i, tab in ipairs(tabs) do
        if i == activeIdx then
            target.setBackgroundColor(UI.colors.tabActive)
            target.setTextColor(UI.colors.tabText)
        else
            target.setBackgroundColor(UI.colors.tabIdle)
            target.setTextColor(UI.colors.tabTextDim)
        end
        local label = " " .. tab.name .. " "
        target.setCursorPos(x, y)
        target.write(label)
        hitboxes[i] = { x1 = x, x2 = x + #label - 1 }
        x = x + #label + 1
    end
    target.setBackgroundColor(colors.black)
    if x <= w then
        target.setCursorPos(x, y)
        target.write(string.rep(" ", w - x + 1))
    end
    return hitboxes
end
function UI.drawBox(target, x, y, w, h, title)
    target.setBackgroundColor(UI.colors.bg)
    target.setTextColor(UI.colors.border)
    target.setCursorPos(x, y)
    target.write("+" .. string.rep("-", w - 2) .. "+")
    for row = y + 1, y + h - 2 do
        target.setCursorPos(x, row)
        target.write("|")
        target.setCursorPos(x + w - 1, row)
        target.write("|")
    end
    target.setCursorPos(x, y + h - 1)
    target.write("+" .. string.rep("-", w - 2) .. "+")
    if title then
        target.setTextColor(UI.colors.header)
        target.setCursorPos(x + 2, y)
        target.write(" " .. title .. " ")
    end
end
function UI.writeAt(target, x, y, text, fg, bg)
    target.setCursorPos(x, y)
    if fg then target.setTextColor(fg) end
    if bg then target.setBackgroundColor(bg) end
    target.write(text)
    target.setBackgroundColor(UI.colors.bg)
    target.setTextColor(UI.colors.text)
end
function UI.drawButton(target, x, y, label, active)
    local bg = active and UI.colors.accent or UI.colors.btnBg
    local fg = active and colors.black or UI.colors.btnText
    target.setCursorPos(x, y)
    target.setBackgroundColor(bg)
    target.setTextColor(fg)
    target.write(" " .. label .. " ")
    target.setBackgroundColor(UI.colors.bg)
    target.setTextColor(UI.colors.text)
    return { x1 = x, x2 = x + #label + 1, y = y }
end
function UI.padRight(text, width)
    if #text >= width then return text:sub(1, width) end
    return text .. string.rep(" ", width - #text)
end
function UI.centerText(target, y, text, fg)
    local w, _ = target.getSize()
    local x = math.floor((w - #text) / 2) + 1
    UI.writeAt(target, x, y, text, fg)
end
function UI.drawProgressBar(target, x, y, width, value, maxVal, fg)
    local filled = math.floor((value / maxVal) * width + 0.5)
    filled = math.max(0, math.min(width, filled))
    target.setCursorPos(x, y)
    target.setBackgroundColor(fg or UI.colors.accent)
    target.write(string.rep(" ", filled))
    target.setBackgroundColor(UI.colors.border)
    target.write(string.rep(" ", width - filled))
    target.setBackgroundColor(UI.colors.bg)
end
return UI