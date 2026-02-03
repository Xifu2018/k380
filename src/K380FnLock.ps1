# K380 Fn Lock Toggle - PowerShell Native v3
# Tries all K380 interfaces to find the control endpoint
#
# Usage:
#   .\K380FnLock.ps1 -FnLock      # Enable Fn lock
#   .\K380FnLock.ps1 -MediaKeys   # Disable Fn lock
#   .\K380FnLock.ps1              # Show GUI
#   .\K380FnLock.ps1 -Scan        # List devices

param(
    [switch]$FnLock,
    [switch]$MediaKeys,
    [switch]$Scan
)

$HidApiCode = @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
using System.Collections.Generic;

public static class K380Hid
{
    public const int DIGCF_PRESENT = 0x02;
    public const int DIGCF_DEVICEINTERFACE = 0x10;
    public const uint GENERIC_READ = 0x80000000;
    public const uint GENERIC_WRITE = 0x40000000;
    public const uint FILE_SHARE_READ = 0x01;
    public const uint FILE_SHARE_WRITE = 0x02;
    public const uint OPEN_EXISTING = 3;

    // K380 Fn Lock commands
    public static readonly byte[] FN_LOCK_ON = new byte[] { 0x10, 0xFF, 0x0B, 0x1E, 0x00, 0x00, 0x00 };
    public static readonly byte[] FN_LOCK_OFF = new byte[] { 0x10, 0xFF, 0x0B, 0x1E, 0x01, 0x00, 0x00 };

    [StructLayout(LayoutKind.Sequential)]
    public struct SP_DEVICE_INTERFACE_DATA
    {
        public int cbSize;
        public Guid InterfaceClassGuid;
        public int Flags;
        public IntPtr Reserved;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct SP_DEVICE_INTERFACE_DETAIL_DATA
    {
        public int cbSize;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 1024)]
        public string DevicePath;
    }

    [DllImport("hid.dll")]
    public static extern void HidD_GetHidGuid(out Guid hidGuid);

    [DllImport("hid.dll", SetLastError = true)]
    public static extern bool HidD_SetOutputReport(SafeFileHandle h, byte[] data, int len);

    [DllImport("setupapi.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr SetupDiGetClassDevs(ref Guid g, IntPtr e, IntPtr w, int f);

    [DllImport("setupapi.dll", CharSet = CharSet.Unicode)]
    public static extern bool SetupDiEnumDeviceInterfaces(IntPtr d, IntPtr i, ref Guid g, int m, ref SP_DEVICE_INTERFACE_DATA data);

    [DllImport("setupapi.dll", CharSet = CharSet.Unicode)]
    public static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr d, ref SP_DEVICE_INTERFACE_DATA data, ref SP_DEVICE_INTERFACE_DETAIL_DATA detail, int size, out int req, IntPtr info);

    [DllImport("setupapi.dll")]
    public static extern bool SetupDiDestroyDeviceInfoList(IntPtr d);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    public static extern SafeFileHandle CreateFile(string f, uint a, uint s, IntPtr sec, uint c, uint fl, IntPtr t);

    [DllImport("kernel32.dll")]
    public static extern bool WriteFile(SafeFileHandle handle, byte[] buffer, int bytesToWrite, out int bytesWritten, IntPtr overlapped);

    [DllImport("kernel32.dll")]
    public static extern int GetLastError();

    private static bool IsK380Path(string path)
    {
        if (string.IsNullOrEmpty(path)) return false;
        string p = path.ToLowerInvariant();
        return p.Contains("046d") && p.Contains("b342");
    }

    public static List<string> FindAllK380Paths()
    {
        var results = new List<string>();
        Guid hidGuid;
        HidD_GetHidGuid(out hidGuid);
        IntPtr devInfo = SetupDiGetClassDevs(ref hidGuid, IntPtr.Zero, IntPtr.Zero, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
        if (devInfo == IntPtr.Zero || devInfo == new IntPtr(-1)) return results;

        try
        {
            SP_DEVICE_INTERFACE_DATA ifData = new SP_DEVICE_INTERFACE_DATA();
            ifData.cbSize = Marshal.SizeOf(ifData);
            int idx = 0;

            while (SetupDiEnumDeviceInterfaces(devInfo, IntPtr.Zero, ref hidGuid, idx++, ref ifData))
            {
                SP_DEVICE_INTERFACE_DETAIL_DATA detail = new SP_DEVICE_INTERFACE_DETAIL_DATA();
                detail.cbSize = IntPtr.Size == 8 ? 8 : 6;
                int reqSize;

                if (!SetupDiGetDeviceInterfaceDetail(devInfo, ref ifData, ref detail, 1024, out reqSize, IntPtr.Zero))
                    continue;

                if (IsK380Path(detail.DevicePath))
                    results.Add(detail.DevicePath);
            }
        }
        finally { SetupDiDestroyDeviceInfoList(devInfo); }
        return results;
    }

    public static string SetFnLock(bool enable)
    {
        var paths = FindAllK380Paths();
        if (paths.Count == 0) 
            return "ERROR: K380 not found. Press a key to wake it.";

        byte[] cmd = enable ? FN_LOCK_ON : FN_LOCK_OFF;
        
        // Try different padding sizes
        int[] sizes = new int[] { 7, 8, 20, 32, 64 };
        
        foreach (var path in paths)
        {
            using (SafeFileHandle h = CreateFile(path, GENERIC_READ | GENERIC_WRITE, 
                FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero))
            {
                if (h.IsInvalid) continue;

                foreach (int size in sizes)
                {
                    byte[] paddedCmd = new byte[size];
                    Array.Copy(cmd, paddedCmd, Math.Min(cmd.Length, size));

                    // Try HidD_SetOutputReport
                    if (HidD_SetOutputReport(h, paddedCmd, paddedCmd.Length))
                    {
                        return enable 
                            ? "OK: Fn Lock ON - F1-F12 = Function keys" 
                            : "OK: Fn Lock OFF - F1-F12 = Media keys";
                    }

                    // Try WriteFile
                    int written;
                    if (WriteFile(h, paddedCmd, paddedCmd.Length, out written, IntPtr.Zero) && written > 0)
                    {
                        return enable 
                            ? "OK: Fn Lock ON - F1-F12 = Function keys" 
                            : "OK: Fn Lock OFF - F1-F12 = Media keys";
                    }
                }
            }
        }
        
        return "ERROR: Could not send command. Tried " + paths.Count + " interfaces.";
    }

    public static bool IsConnected() 
    { 
        return FindAllK380Paths().Count > 0; 
    }

    public static string GetDeviceInfo()
    {
        var paths = FindAllK380Paths();
        if (paths.Count == 0) return "No K380 found. Press a key to wake it.";
        
        string result = "Found " + paths.Count + " K380 interface(s):\n";
        int i = 1;
        foreach (var p in paths)
        {
            string col = "";
            int colIdx = p.ToLower().IndexOf("col");
            if (colIdx > 0) col = " (" + p.Substring(colIdx, 5) + ")";
            
            string access = " [no access]";
            using (SafeFileHandle h = CreateFile(p, GENERIC_READ | GENERIC_WRITE, 
                FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero))
            {
                if (!h.IsInvalid) access = " [writable]";
            }
            result += i++ + "." + col + access + "\n";
        }
        return result;
    }
}
'@

if (-not ([System.Management.Automation.PSTypeName]'K380Hid').Type) {
    Add-Type -TypeDefinition $HidApiCode
}

function Show-K380GUI {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "K380 Fn Lock"
    $form.Size = New-Object System.Drawing.Size(400, 300)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedSingle"
    $form.MaximizeBox = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = "Logitech K380"
    $title.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = [System.Drawing.Color]::White
    $title.AutoSize = $true
    $title.Location = New-Object System.Drawing.Point(20, 15)

    $status = New-Object System.Windows.Forms.Label
    $status.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $status.AutoSize = $true
    $status.Location = New-Object System.Drawing.Point(22, 50)
    if ([K380Hid]::IsConnected()) {
        $status.Text = "[Connected]"
        $status.ForeColor = [System.Drawing.Color]::LimeGreen
    }
    else {
        $status.Text = "[Not Connected]"
        $status.ForeColor = [System.Drawing.Color]::Red
    }

    $msgBox = New-Object System.Windows.Forms.Label
    $msgBox.Text = "Click a button to toggle Fn Lock"
    $msgBox.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $msgBox.ForeColor = [System.Drawing.Color]::Gray
    $msgBox.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $msgBox.Location = New-Object System.Drawing.Point(20, 85)
    $msgBox.Size = New-Object System.Drawing.Size(345, 60)
    $msgBox.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 45)

    $btnOn = New-Object System.Windows.Forms.Button
    $btnOn.Text = "Fn Lock ON"
    $btnOn.Font = New-Object System.Drawing.Font("Segoe UI", 12)
    $btnOn.Size = New-Object System.Drawing.Size(160, 60)
    $btnOn.Location = New-Object System.Drawing.Point(20, 165)
    $btnOn.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
    $btnOn.ForeColor = [System.Drawing.Color]::White
    $btnOn.FlatStyle = "Flat"
    $btnOn.Add_Click({
            $result = [K380Hid]::SetFnLock($true)
            $msgBox.Text = $result
            if ($result.StartsWith("OK")) { $msgBox.ForeColor = [System.Drawing.Color]::LimeGreen }
            else { $msgBox.ForeColor = [System.Drawing.Color]::Red }
            if ([K380Hid]::IsConnected()) { $status.Text = "[Connected]"; $status.ForeColor = [System.Drawing.Color]::LimeGreen }
            else { $status.Text = "[Not Connected]"; $status.ForeColor = [System.Drawing.Color]::Red }
        })

    $btnOff = New-Object System.Windows.Forms.Button
    $btnOff.Text = "Fn Lock OFF"
    $btnOff.Font = New-Object System.Drawing.Font("Segoe UI", 12)
    $btnOff.Size = New-Object System.Drawing.Size(160, 60)
    $btnOff.Location = New-Object System.Drawing.Point(205, 165)
    $btnOff.BackColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
    $btnOff.ForeColor = [System.Drawing.Color]::White
    $btnOff.FlatStyle = "Flat"
    $btnOff.Add_Click({
            $result = [K380Hid]::SetFnLock($false)
            $msgBox.Text = $result
            if ($result.StartsWith("OK")) { $msgBox.ForeColor = [System.Drawing.Color]::LimeGreen }
            else { $msgBox.ForeColor = [System.Drawing.Color]::Red }
            if ([K380Hid]::IsConnected()) { $status.Text = "[Connected]"; $status.ForeColor = [System.Drawing.Color]::LimeGreen }
            else { $status.Text = "[Not Connected]"; $status.ForeColor = [System.Drawing.Color]::Red }
        })

    $form.Controls.AddRange(@($title, $status, $msgBox, $btnOn, $btnOff))
    [void]$form.ShowDialog()
}

# Main
if ($Scan) {
    Write-Host "=== K380 Device Scan ===" -ForegroundColor Cyan
    Write-Host ([K380Hid]::GetDeviceInfo())
}
elseif ($FnLock) {
    Write-Host ([K380Hid]::SetFnLock($true))
}
elseif ($MediaKeys) {
    Write-Host ([K380Hid]::SetFnLock($false))
}
else {
    Show-K380GUI
}
