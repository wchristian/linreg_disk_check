$ErrorActionPreference = "Stop"

$notificationText = [DateTime]::Now.ToShortDateString() + " " + [DateTime]::Now.ToShortTimeString() + ": $args"

# get template for notification from windows API, use "a single text string in 3 lines" template (ToastText01)
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null
$template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText01)

# replace text element with intended notification text
$toastXml = [xml] $template.GetXml()
$toastXml.GetElementsByTagName("text").AppendChild($toastXml.CreateTextNode($notificationText)) > $null

# Convert back to WinRT type
$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
$xml.LoadXml($toastXml.OuterXml)

# construct toast
$toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
$toast.Tag = "PowerShell"
$toast.Group = "PowerShell"

# show toast
$notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("PowerShell")
$notifier.Show($toast);
