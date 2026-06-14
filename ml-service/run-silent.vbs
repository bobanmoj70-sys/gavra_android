' Silent launcher for Gavra ML Service
' Runs start-ml-service.bat without showing a window
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "cmd /c ""C:\Users\Bojan\gavra_android\ml-service\start-ml-service.bat""", 0, False
Set WshShell = Nothing
