#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon

; =====================================================================
;  看门狗：switch_cursor_monitor.ahk 用心跳文件证明自己还活着。
;  心跳超过 25 秒没更新（且不是用户主动退出）就重新拉起。
; =====================================================================

MainScript := A_ScriptDir "\switch_cursor_monitor.ahk"
HeartbeatFile := A_ScriptDir "\switch_cursor_heartbeat.txt"
StopFlagFile := A_ScriptDir "\switch_cursor_stopped.flag"
WatchdogLog := A_ScriptDir "\switch_cursor_watchdog.log"

Log("看门狗启动 pid=" ProcessExist())
Check()                    ; 启动时先检查一次
SetTimer(Check, 10000)     ; 之后每 10 秒检查；同一回调只能有一个定时器

Check() {
    global MainScript, HeartbeatFile, StopFlagFile, WatchdogLog
    static lastLaunch := 0

    try {
        ; 用户从托盘主动退出时不要拉起
        if FileExist(StopFlagFile)
            return

        alive := false
        if FileExist(HeartbeatFile) {
            stamp := FileGetTime(HeartbeatFile, "M")
            if (stamp && DateDiff(A_Now, stamp, "Seconds") < 25)
                alive := true
        }
        if (alive)
            return

        ; 刚刚拉起过就等它把心跳写出来，避免连续启动
        if (A_TickCount - lastLaunch < 30000)
            return
        lastLaunch := A_TickCount

        Run('"' A_AhkPath '" "' MainScript '"')
        Log("心跳超时，已重新拉起")
    } catch as error {
        Log("检查出错：" error.Message " @ " error.What " line " error.Line)
    }
}

Log(text) {
    global WatchdogLog
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") "  " text "`n", WatchdogLog, "UTF-8")
}
