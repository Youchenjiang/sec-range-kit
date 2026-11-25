---
name: hitcon-dfir-vm-ops
description: >-
  Connect to and operate the local dual-VM forensics analysis environment (Windows 10 FLARE-VM
  via vmrun Guest Operations and Kali Linux via SSH) on the Primary Analysis Gateway.
  Provides command syntax, tooling locations, dual-VM triage dispatch rules, and pre-flight checks
  for graceful fallback on remote analytical nodes.
---

# 🛠️ HITCON Cyber Range 主機鑑識作戰環境與雙 VM 操作指南 (hitcon-dfir-vm-ops)

本技能提供 **HITCON Cyber Range / CTF 主機鑑識與應急響應** 實戰中，調用本地實體分析網關（Primary Analysis Gateway）之 Windows FLARE-VM 與 Kali Linux 分析機的具體指令、工具分工、避坑防呆及跨主機協作規則。

---

## 0. 節點拓撲與環境先決條件檢查 (Pre-flight Check)

在發起任何 VM 連線或實體工具指令前，**必須先確認當前執行的主機環境**：

> ⚠️ **關鍵架構限制**：
> - 兩台分析 VM（FLARE-VM、Kali Linux）與 64GB 宿主算力**僅部署在 Primary Host（本地工作站）**。
> - 其他實體主機（隊友電腦、遠端雲端 Session、無 VMware 之節點）**完全無法直連這兩台 VM**。

### 0.1 節點自我檢測命令
在終端執行以下指令以判斷當前節點身份：

```powershell
# 檢測當前節點是否具備 VM 網關能力
python -c "import os, sys; has_vmrun = os.path.exists(r'C:\MyAPP\VMware Workstation\vmrun.exe'); has_secrets = os.path.exists('secrets.env'); print('NODE_TYPE: PRIMARY_GATEWAY' if (has_vmrun and has_secrets) else 'NODE_TYPE: REMOTE_ANALYST')"
```

- **若輸出 `PRIMARY_GATEWAY`**：
  - 具備完整 VM 操作權限與本地大檔存取權限。
  - 負責執行 Live VM 指令、大映像處理（E01 / Volatility），並將結果導出為輕量文字/CSV/JSON 工件供總線流通。
- **若輸出 `REMOTE_ANALYST`**：
  - **嚴禁**嘗試執行 `vmrun_guest.py`、`vmrun` 或私有 IP `ssh 192.168.12.128`。
  - **工作模式**：僅針對 `.collab` 或本地已同步之文字/CSV/JSON/代碼切片進行純邏輯檢索、逆向推理與 Review。
  - **如需 VM 輸出**：在 task 下透過 `collab_bus.py send --kind QUESTION` 向 Primary Host 發出工件導出請求（例如：「請 Primary Host 協助對 sample.evtx 執行 EvtxECmd 並回傳 CSV」）。

---

## 1. Windows FLARE-VM 遠端控制 (Windows 10 x64, 192.168.12.129)

### 1.1 連線機制：VMware Guest Operations (VMCI)
FLARE-VM 不開放外部 TCP 連線（防火牆全擋 22/3389/5985/445），但 VMware Tools 運作正常。統一透過 `rangekit/vm/vmrun_guest.py` 進行無網操作。客體帳號與密碼（`VM_GU` / `VM_GP`）自動自根目錄 Git-ignored 之 `secrets.env` 載入。

### 1.2 常用操作指令

```powershell
# 1. 檢查 Tools 狀態與客體 IP（免憑證）
python -m rangekit.vm.vmrun_guest tools

# 2. 執行客體 PowerShell 指令並抓取輸出
python -m rangekit.vm.vmrun_guest powershell 'Get-Date'
python -m rangekit.vm.vmrun_guest powershell 'Get-Process | Select-Object -First 10'

# 3. 執行客體 CMD 指令
python -m rangekit.vm.vmrun_guest exec 'dir /b C:\Windows\Temp'

# 4. 傳送檔案至客體
python -m rangekit.vm.vmrun_guest put local_script.ps1 'C:\Windows\Temp\test.ps1'

# 5. 從客體拉回分析產出
python -m rangekit.vm.vmrun_guest get 'C:\Windows\Temp\evidence.csv' ./evidence.csv
```

### 1.3 客體內已建置之 DFIR 工具鏈（路徑：`C:\Tools\DFIR\`）
- **Eric Zimmerman Tools 全套 (net9)**：`C:\Tools\DFIR\EZTools\net9\`
  - `EvtxECmd`（日誌解析）：`C:\Tools\DFIR\EZTools\net9\EvtxeCmd\EvtxECmd.exe`
  - `PECmd`（Prefetch）：`C:\Tools\DFIR\EZTools\net9\PECmd.exe`
  - `AmcacheParser`：`C:\Tools\DFIR\EZTools\net9\AmcacheParser.exe`
  - `AppCompatCacheParser`（Shimcache）：`C:\Tools\DFIR\EZTools\net9\AppCompatCacheParser.exe`
  - `RECmd`（離線機碼分析）：`C:\Tools\DFIR\EZTools\net9\RECmd.exe`
  - `MFTECmd`（NTFS MFT 解析）：`C:\Tools\DFIR\EZTools\net9\MFTECmd.exe`
  - `TimelineExplorer` / `RegistryExplorer`（GUI 視覺化）
- **Chainsaw v2.16.5**：`C:\Tools\DFIR\chainsaw\chainsaw.exe`（配搭 3,144 條 Sigma 規則：`C:\Tools\DFIR\sigma-rules\sigma-master\rules`）
- **Hayabusa v4.1.0**：`C:\Tools\DFIR\hayabusa\hayabusa-4.1.0-win-x64.exe`
  - 語法：`dfir-timeline -d <日誌目錄> -o out.csv -w -Q -U`（**務必加 `-U` 輸出 UTC**）
- **Sysmon**：客體已運行 `Sysmon64` 服務與 `SysmonDrv` 驅動，設定檔為 SwiftOnSecurity。

### 1.4 四大必知操作地雷
1. **客體拒絕空密碼**：vmrun 嚴禁空密碼，必須依賴 `secrets.env`。
2. **命令避免巢狀引號**：`powershell -Command "..."` 雙引號會被 vmrun 吃掉；複雜邏輯請先存為 `.ps1` 傳入客體再以 `-File` 執行。
3. **客體主控台為 CP950**：輸出包含非 ASCII 會在重導向時變成亂碼，腳本輸出**一律強制 ASCII 或 UTF-8**。
4. **輸出重導向括號包覆**：多命令重導向必須以 `( cmd1 & cmd2 ) > out.txt 2>&1` 包裹，避免前段輸出掉在虛擬 Console。

---

## 2. Kali Linux VM 遠端控制 (192.168.12.128)

### 2.1 連線機制：免密碼 SSH (Port 22)
Host 已建立 Ed25519 金鑰對並寫入 Kali `authorized_keys`。將其視為「宿主機免切換畫面的背景計算機」。

### 2.2 常用操作指令

```powershell
# 1. 快速文字處理與統計（例如分析 Apache/Nginx Web access.log）
ssh kali@192.168.12.128 "grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' /tmp/access.log | sort | uniq -c | sort -nr | head -n 20"

# 2. 封包提取與流量統計 (tshark)
ssh kali@192.168.12.128 "tshark -r /tmp/capture.pcap -qz io,stat,60"
ssh kali@192.168.12.128 "tshark -r /tmp/capture.pcap -Y 'http.request' -T fields -e ip.src -e http.request.full_uri"

# 3. 釣魚文檔分析 (oletools)
ssh kali@192.168.12.128 "olevba /tmp/invoice.docm"

# 4. Linux auditd 日誌排查
ssh kali@192.168.12.128 "ausearch -i -m execve"
```

> ⚠️ **時區提醒**：Kali 系統時區目前為 `America/New_York`，分析跨來源時間線時，所有時間戳**一律換算為 UTC** 作為標準時間。

---

## 3. 標本分流決策（看副檔名決定工作機）

兩台 VM 皆只有 2GB RAM，**嚴禁將 10GB+ 映像或大型記憶體 Dump 塞入 VM**！

| 標本類型 / 副檔名 | 唯一指定環境 | 核心作戰工具 | 分流原因 |
| :--- | :---: | :--- | :--- |
| **`.evtx`** (Windows 事件日誌) | **FLARE-VM** | `EvtxECmd` + `TimelineExplorer` / `Hayabusa` | 視覺化多欄位 Filter，排查速度最快。 |
| **`$MFT` / 註冊表 / `.pf`** | **FLARE-VM** | `MFTECmd`, `RECmd`, `PECmd` | Windows 原生結構解析最準確。 |
| **完整 `.E01` / 大型 NTFS 映像** | **Host 主機** | Autopsy 4.23.1, SleuthKit, Python binary parser | Host 有 64GB RAM；抽出小工件後再送 FLARE-VM。 |
| **記憶體 Dump (`.mem` / `.raw`)** | **Host 主機** | Volatility 3 v2.28.2 (已快取 pdb symbols) | VM 僅 2GB RAM 會直接 OOM/換頁卡死。 |
| **`access.log` / `/var/log/*`** | **Kali Linux** | `awk`, `grep`, `sed`, `ausearch` | Linux CLI 管道快攻。 |
| **`.pcap` / `.pcapng`** (網路流量) | **Kali Linux** | `tshark`, `tcpflow`, `zeek` | 封包流分割與流重組。 |
| **`.docm` / `.xlsm` / `.pdf`** | **Kali Linux** | `olevba`, `pdf-parser`, Python | 巨集與惡意內嵌物件解構。 |

---

## 4. 戰術參考手冊速查 (Playbooks Index)

所有實戰判讀卡與手冊位於 `tracks/lab/hitcon_range/playbooks/`：
- **作戰大綱與分工**：
  - `Holmes2026_雙機鑑識分工與作戰SOP.md`
  - `Holmes2026_FLARE-VM_DFIR工具鏈.md`
  - `Holmes2026_Host_DFIR_2頁Cheatsheet.md`
- **逐日 AI 現場決策卡**：
  - Day 1：端點事件 / macOS 工件 / Windows EID 速查
  - Day 2：執行痕跡三本柱（Prefetch / Amcache / Shimcache / UserAssist / USBSTOR）
  - Day 3：NTFS 底層 / `$MFT` / 刪除檔案救援
  - Day 4：Windows 記憶體取證（Volatility 3）
  - Day 5：Linux endpoint / auditd 重建
  - Day 6：SLA 微創圍堵與應急響應
