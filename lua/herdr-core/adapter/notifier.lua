local M = {}
local toast = [[
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime] > $null
$title = [Security.SecurityElement]::Escape($env:HERDR_NOTIFICATION_TITLE)
$body = [Security.SecurityElement]::Escape($env:HERDR_NOTIFICATION_BODY)
$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
$xml.LoadXml("<toast><visual><binding template='ToastGeneric'><text>$title</text><text>$body</text></binding></visual></toast>")
$notification = [Windows.UI.Notifications.ToastNotification]::new($xml)
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('WindowsPowerShell').Show($notification)
]]

---@param name     string
---@param status   string
---@param callback fun(err: string?)
---@param custom?  fun(name: string, status: string)
function M.send(name, status, callback, custom)
    if custom then
        local ok, failure = pcall(custom, name, status)
        callback(not ok and tostring(failure) or nil)
        return
    end
    local command = { "notify-send", "--", name, status }
    if vim.fn.has("win32") == 1 then
        command = {
            "powershell.exe", "-NoLogo", "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command", toast
        }
    elseif vim.fn.has("macunix") == 1 then
        command = {
            "osascript", "-e", "on run argv\ndisplay notification (item 2 of argv) with title (item 1 of argv)\nend run",
            "--", name, status
        }
    end
    local ok, failure = pcall(
        vim.system, command,
        {
            text = true,
            env = { HERDR_NOTIFICATION_TITLE = name, HERDR_NOTIFICATION_BODY = status }
        },
        function (result)
            callback(result.code ~= 0 and (result.stderr or "OS notification failed") or nil)
        end
    )
    if not ok then callback(tostring(failure)) end
end

return M
