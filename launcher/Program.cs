using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Security.Principal;
using System.Windows.Forms;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        string exePath = Assembly.GetExecutingAssembly().Location;
        string dir = Path.GetDirectoryName(exePath);

        if (!IsAdministrator())
        {
            try
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = exePath,
                    Verb = "runas",
                    UseShellExecute = true,
                    WorkingDirectory = dir
                });
            }
            catch (Exception)
            {
                MessageBox.Show(
                    "需要管理员权限才能从全屏游戏切换光标。\n请右键选择“以管理员身份运行”。",
                    "Monitor Switch",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Warning);
            }
            return;
        }

        string[] ahkCandidates =
        {
            Path.Combine(dir, "AutoHotkey64.exe"),
            Path.Combine(dir, "v2", "AutoHotkey64.exe"),
            Path.Combine(dir, "AutoHotkey32.exe"),
            Path.Combine(dir, "v2", "AutoHotkey32.exe")
        };
        string ahk = ahkCandidates.FirstOrDefault(path =>
            File.Exists(path) && new FileInfo(path).Length > 0);
        string[] scripts =
        {
            "switch_cursor_monitor.ahk",
            "switch_monitor.ahk",
            "switch_cursor_watchdog.ahk"
        };

        if (ahk == null)
        {
            MessageBox.Show(
                "找不到可用的 AutoHotkey v2 运行时。\n\n" +
                "已检查以下位置：\n" + string.Join("\n", ahkCandidates) +
                "\n\n请确认压缩包已完整解压。",
                "Monitor Switch",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return;
        }

        string[] missing = scripts
            .Where(name => !File.Exists(Path.Combine(dir, name)))
            .ToArray();

        if (missing.Length > 0)
        {
            MessageBox.Show(
                "缺少脚本：\n" + string.Join("\n", missing),
                "Monitor Switch",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return;
        }

        foreach (string script in scripts)
        {
            try
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = ahk,
                    Arguments = "\"" + Path.Combine(dir, script) + "\"",
                    WorkingDirectory = dir,
                    UseShellExecute = false
                });
            }
            catch (Exception error)
            {
                MessageBox.Show(
                    "启动 " + script + " 失败：\n" + error.Message,
                    "Monitor Switch",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
                return;
            }
        }
    }

    private static bool IsAdministrator()
    {
        using (WindowsIdentity identity = WindowsIdentity.GetCurrent())
        {
            return new WindowsPrincipal(identity)
                .IsInRole(WindowsBuiltInRole.Administrator);
        }
    }
}
