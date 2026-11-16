# Whether this Windows session cannot show a game window: its input desktop
# is not "Default" (a locked screen moves input to the logon desktop) or
# cannot be opened (a locked screen, or a disconnected remote session). A
# locked session cannot present the game's OpenGL window, and the client
# stalls after the intro videos (2026-10-30, docs/test-results.md).
# The launchers used to look for LogonUI.exe instead, but it can outlive the
# unlock: on 2026-11-16 one started at an unlock was still running ten
# minutes later with the screen unlocked, and they refused to start.
# Dot-sourced by run-sp-harness.ps1 and run-mp-harness.ps1.
function Test-SessionLocked {
    if (-not ("TLGInputDesktop" -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class TLGInputDesktop {
    [DllImport("user32.dll", SetLastError = true)]
    static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
    [DllImport("user32.dll", SetLastError = true)]
    static extern bool GetUserObjectInformation(IntPtr obj, int index, StringBuilder buf, int len, out int needed);
    [DllImport("user32.dll")]
    static extern bool CloseDesktop(IntPtr desk);
    // The input desktop's name, or null when it cannot be opened.
    public static string Name() {
        IntPtr h = OpenInputDesktop(0, false, 0x0001); // DESKTOP_READOBJECTS
        if (h == IntPtr.Zero) return null;
        try {
            var sb = new StringBuilder(256);
            int needed;
            return GetUserObjectInformation(h, 2, sb, sb.Capacity, out needed) ? sb.ToString() : null; // UOI_NAME
        } finally {
            CloseDesktop(h);
        }
    }
}
'@
    }
    return [TLGInputDesktop]::Name() -ne "Default"
}
