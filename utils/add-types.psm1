using assembly System.Windows.Forms
using assembly System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessage(IntPtr hWnd, int msg, int wParam, IntPtr lParam);
}
"@

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Keyboard {
    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int key);
}
"@

