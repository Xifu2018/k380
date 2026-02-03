# K380 Fn Lock - 使用说明

## 使用方法

```powershell
# 在 PowerShell 中运行
.\K380FnLock.ps1 -FnLock      # F1-F12 = 功能键
.\K380FnLock.ps1 -MediaKeys   # F1-F12 = 多媒体键
.\K380FnLock.ps1 -Scan        # 扫描设备
.\K380FnLock.ps1              # 打开 GUI

# 如果遇到执行策略限制，使用：
powershell -ExecutionPolicy Bypass -File .\K380FnLock.ps1 -FnLock
```

## 创建桌面快捷方式

**Fn Lock ON:**
```
powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "完整路径\K380FnLock.ps1" -FnLock
```

**Fn Lock OFF:**
```
powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "完整路径\K380FnLock.ps1" -MediaKeys
```

## 兼容性

- Windows 10/11
- PowerShell 5.1+
- Logitech K380 (蓝牙直连)
