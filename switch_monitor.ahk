#Requires AutoHotkey v2.0
#SingleInstance Force
#MaxThreadsPerHotkey 1
#UseHook True
#NoTrayIcon

; =====================================================================
;  将当前窗口移到上一台/下一台显示器
;
;  Win+Shift+M       : 下一台显示器
;  Win+Shift+Right   : 下一台显示器
;  Win+Shift+Left    : 上一台显示器
;
;  显示器按空间位置排序：先横向，后纵向。
;  窗口会居中放到目标显示器的工作区；最大化窗口移动后仍保持最大化。
;  日志：C:\TOOLS\AutoHotKey\switch_monitor.log
; =====================================================================

LogFile := A_ScriptDir "\switch_monitor.log"

OnError((error, mode) => Log(
    "错误 [" mode "] " error.Message " @ " error.What " line " error.Line
))
Log("脚本启动 pid=" ProcessExist())

#+m::MoveWindowToNextMonitor()
#+Right::MoveWindowToNextMonitor()
#+Left::MoveWindowToPrevMonitor()

MoveWindowToNextMonitor() {
    MoveToMonitor(1)
}

MoveWindowToPrevMonitor() {
    MoveToMonitor(-1)
}

MoveToMonitor(direction) {
    ; 物理像素坐标，避免不同显示器缩放比例导致落点错误。
    try DllCall("SetThreadDpiAwarenessContext", "Ptr", -4)

    hwnd := DllCall("GetForegroundWindow", "Ptr")
    if (!hwnd || !DllCall("IsWindow", "Ptr", hwnd)) {
        ShowTip("没有可移动的前台窗口")
        return
    }

    cls := WindowClassName(hwnd)
    if (cls = "Progman" || cls = "WorkerW" || cls = "Shell_TrayWnd"
        || cls = "Shell_SecondaryTrayWnd") {
        ShowTip("桌面或任务栏不能移动")
        return
    }

    monitors := GetMonitors()
    if (monitors.Length < 2) {
        ShowTip("只检测到 1 台显示器")
        return
    }

    curIdx := MonitorIndexFromWindow(hwnd, monitors)
    nextIdx := curIdx + direction
    if (nextIdx > monitors.Length)
        nextIdx := 1
    if (nextIdx < 1)
        nextIdx := monitors.Length

    source := monitors[curIdx]
    target := monitors[nextIdx]
    wasMaximized := WinGetMinMax(hwnd) = 1
    title := WindowTitle(hwnd)

    Log(Format("hotkey dir={1} hwnd={2} max={3} cur={4} next={5} title={6}"
        , direction, hwnd, wasMaximized, curIdx, nextIdx, title))
    for i, monitor in monitors
        Log(Format("  mon{1}: {2},{3} {4}x{5} work={6},{7} {8}x{9}"
            , i, monitor.left, monitor.top, monitor.width, monitor.height
            , monitor.workLeft, monitor.workTop, monitor.workWidth, monitor.workHeight))

    ; 最大化窗口必须临时还原，否则 Windows 可能继续把它最大化到原显示器。
    if (wasMaximized) {
        WinRestore(hwnd)
        Sleep 80
    }

    WinGetPos(&winX, &winY, &winW, &winH, hwnd)
    newW := Min(winW, target.workWidth)
    newH := Min(winH, target.workHeight)
    newX := target.workLeft + (target.workWidth - newW) // 2
    newY := target.workTop + (target.workHeight - newH) // 2

    WinMove(newX, newY, newW, newH, hwnd)
    Sleep 120

    landedIdx := MonitorIndexFromWindow(hwnd, monitors)
    if (landedIdx != nextIdx) {
        ; 某些不同 DPI 的窗口会拒绝第一次 WinMove，用 SetWindowPos 再强制一次。
        Log(Format("  retry SetWindowPos target={1},{2} {3}x{4}"
            , newX, newY, newW, newH))
        DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", 0
            , "Int", newX, "Int", newY, "Int", newW, "Int", newH
            , "UInt", 0x0014)                                   ; NOZORDER + NOACTIVATE
        Sleep 120
        landedIdx := MonitorIndexFromWindow(hwnd, monitors)
    }

    if (wasMaximized) {
        WinMaximize(hwnd)
        Sleep 80
    }

    WinActivate(hwnd)
    Sleep 50

    if (landedIdx = nextIdx) {
        ShowTip("→ 显示器 " nextIdx "/" monitors.Length)
        Log(Format("  moved successfully target={1} actual={2} max={3}"
            , nextIdx, landedIdx, WinGetMinMax(hwnd) = 1))
    } else {
        ShowTip("移动失败：窗口仍在显示器 " landedIdx)
        Log(Format("  move failed target={1} actual={2}", nextIdx, landedIdx))
    }
}

GetMonitors() {
    global gMonitorList
    gMonitorList := []

    callback := CallbackCreate(EnumMonitorProc, "Fast", 4)
    DllCall("EnumDisplayMonitors", "Ptr", 0, "Ptr", 0, "Ptr", callback, "Ptr", 0)
    CallbackFree(callback)

    monitors := gMonitorList
    Loop monitors.Length - 1 {
        i := A_Index + 1
        item := monitors[i]
        j := i - 1
        while (j >= 1
            && (monitors[j].left > item.left
                || (monitors[j].left = item.left && monitors[j].top > item.top))) {
            monitors[j + 1] := monitors[j]
            j--
        }
        monitors[j + 1] := item
    }
    return monitors
}

EnumMonitorProc(hMonitor, hdc, rect, data) {
    global gMonitorList

    info := Buffer(40, 0)
    NumPut("UInt", 40, info, 0)
    if (!DllCall("GetMonitorInfoW", "Ptr", hMonitor, "Ptr", info))
        return true

    left := NumGet(info, 4, "Int")
    top := NumGet(info, 8, "Int")
    right := NumGet(info, 12, "Int")
    bottom := NumGet(info, 16, "Int")
    workLeft := NumGet(info, 20, "Int")
    workTop := NumGet(info, 24, "Int")
    workRight := NumGet(info, 28, "Int")
    workBottom := NumGet(info, 32, "Int")

    gMonitorList.Push({
        handle: hMonitor,
        left: left,
        top: top,
        right: right,
        bottom: bottom,
        width: right - left,
        height: bottom - top,
        workLeft: workLeft,
        workTop: workTop,
        workRight: workRight,
        workBottom: workBottom,
        workWidth: workRight - workLeft,
        workHeight: workBottom - workTop
    })
    return true
}

MonitorIndexFromWindow(hwnd, monitors) {
    monitorHandle := DllCall("MonitorFromWindow", "Ptr", hwnd, "UInt", 2, "Ptr")
    for i, monitor in monitors {
        if (monitor.handle = monitorHandle)
            return i
    }

    ; 兜底：使用窗口中心点判断。
    rect := Buffer(16, 0)
    if (DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", rect)) {
        x := (NumGet(rect, 0, "Int") + NumGet(rect, 8, "Int")) // 2
        y := (NumGet(rect, 4, "Int") + NumGet(rect, 12, "Int")) // 2
        for i, monitor in monitors {
            if (x >= monitor.left && x < monitor.right
                && y >= monitor.top && y < monitor.bottom)
                return i
        }
    }
    return 1
}

ShowTip(text) {
    ToolTip(text)
    SetTimer(() => ToolTip(), -1200)
}

WindowClassName(hwnd) {
    buf := Buffer(512, 0)
    if (!DllCall("GetClassNameW", "Ptr", hwnd, "Ptr", buf, "Int", 256))
        return ""
    return StrGet(buf, "UTF-16")
}

WindowTitle(hwnd) {
    buf := Buffer(2048, 0)
    DllCall("GetWindowTextW", "Ptr", hwnd, "Ptr", buf, "Int", 1024)
    return StrGet(buf, "UTF-16")
}

Log(text) {
    global LogFile
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") "  " text "`n", LogFile, "UTF-8")
}
