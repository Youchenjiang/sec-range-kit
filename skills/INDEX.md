# Skill Index (`skills/`)

> **自動產生，請勿手動編輯。**
> 產生：`python tools/generate_skill_index.py`
> 校驗：`python tools/generate_skill_index.py --check`（索引脫節即 exit 1）

## 載入端如何發現（discovery contract）

1. **載入走目錄慣例，不是這份索引**：載入端掃描 `skills/<name>/SKILL.md`，
   只讀 frontmatter 的 `name` + `description` 兩欄作為技能身分，且目錄名必須與 `name` 一致。
2. **本索引不參與載入**：`INDEX.md` 是人／agent 的總表（名稱、描述、來源授權、路徑），
   讓你不必逐目錄翻閱就知道現有能力與授權邊界；它與載入掃描用同一套枚舉邏輯，
   因此「索引列得出」等價於「載入端讀得到」。
3. **自動同步**：索引由 `tools/generate_skill_index.py` 掃描目錄 +
   `SOURCES.json` 重新產生；`--check` 用於測試／doctor，可在索引與實際目錄脫節時中斷。


## 統計

- 技能總數：**152**
- 授權 `Apache-2.0`：140
- 授權 `MIT`：11
- 授權 `Not specified (internal work product)`：1

## 技能清單

| 名稱 | 描述 | 來源 | 授權 | 路徑 |
|------|------|------|------|------|
| `acquiring-disk-image-with-dd-and-dcfldd` | Create forensically sound bit-for-bit disk images with dd or dcfldd on a Linux forensic workstation… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/acquiring-disk-image-with-dd-and-dcfldd/SKILL.md` |
| `admiralty-system` | Apply the NATO Admiralty System (AJP-2.1) to assess source reliability and information credibility… | awesome-dfir-skills | Apache-2.0 | `skills/admiralty-system/SKILL.md` |
| `analysing-attack` | Analyse Mitre ATT&CK tactics, techniques and sub-techniques. Use when performing analysis of threat… | awesome-dfir-skills | Apache-2.0 | `skills/analysing-attack/SKILL.md` |
| `analyzing-browser-forensics-with-hindsight` | Parse Chromium-based browser databases with Hindsight to extract and correlate browsing history, do… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/analyzing-browser-forensics-with-hindsight/SKILL.md` |
| `analyzing-disk-image-with-autopsy` | Perform comprehensive forensic analysis of raw (dd), E01, or AFF disk images with Autopsy and The S… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/analyzing-disk-image-with-autopsy/SKILL.md` |
| `analyzing-docker-container-forensics` | Investigate compromised Docker containers by analyzing images, layers, | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/analyzing-docker-container-forensics/SKILL.md` |
| `analyzing-email-headers-for-phishing-investigation` | Parse and analyze email headers (Received chain, Return-Path, Message-ID) | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/analyzing-email-headers-for-phishing-investigation/SKILL.md` |
| `analyzing-heap-spray-exploitation` | Detect and analyze heap spray attacks in memory dumps using Volatility3 | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/analyzing-heap-spray-exploitation/SKILL.md` |
| `analyzing-linux-audit-logs-for-intrusion` | Uses the Linux Audit framework (auditd) with ausearch and aureport utilities | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/analyzing-linux-audit-logs-for-intrusion/SKILL.md` |
| `analyzing-linux-kernel-rootkits` | Detect kernel-level rootkits in Linux memory dumps using Volatility3 | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/analyzing-linux-kernel-rootkits/SKILL.md` |
| `analyzing-linux-system-artifacts` | Examine Linux system artifacts (auth logs, cron/systemd persistence, | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/analyzing-linux-system-artifacts/SKILL.md` |
| `analyzing-lnk-file-and-jump-list-artifacts` | Analyze Windows LNK shortcut files and Jump List artifacts with LECmd, | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/analyzing-lnk-file-and-jump-list-artifacts/SKILL.md` |
| `analyzing-memory-dumps-with-volatility` | Analyzes RAM memory dumps from compromised systems using the Volatility framework to identify malic… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/analyzing-memory-dumps-with-volatility/SKILL.md` |
| `analyzing-memory-forensics-with-lime-and-volatility` | Performs Linux memory acquisition using LiME (Linux Memory Extractor) | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/analyzing-memory-forensics-with-lime-and-volatility/SKILL.md` |
| `analyzing-mft-for-deleted-file-recovery` | Analyze the NTFS Master File Table ($MFT) with MFTECmd, analyzeMFT, | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/analyzing-mft-for-deleted-file-recovery/SKILL.md` |
| `analyzing-network-traffic-for-incidents` | Analyzes network traffic captures and flow data to identify adversary activity during security inci… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/analyzing-network-traffic-for-incidents/SKILL.md` |
| `analyzing-outlook-pst-for-email-forensics` | Parse Microsoft Outlook PST and OST files using libpff and pst-utils to extract message content, he… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/analyzing-outlook-pst-for-email-forensics/SKILL.md` |
| `analyzing-persistence-mechanisms-in-linux` | Scan Linux systems for persistence mechanisms including crontab/systemd entries, LD_PRELOAD injecti… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/analyzing-persistence-mechanisms-in-linux/SKILL.md` |
| `analyzing-powershell-empire-artifacts` | Detect PowerShell Empire post-exploitation framework artifacts in Windows Script Block Logging (Eve… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/analyzing-powershell-empire-artifacts/SKILL.md` |
| `analyzing-prefetch-files-for-execution-history` | Parse Windows Prefetch files (versions 17, 23, 26, 30) with tools like PECmd, WinPrefetchView, or p… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/analyzing-prefetch-files-for-execution-history/SKILL.md` |
| `analyzing-ransomware-network-indicators` | Identify ransomware-related network indicators, including C2 beaconing patterns, TOR exit node conn… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/analyzing-ransomware-network-indicators/SKILL.md` |
| `analyzing-security-logs-with-splunk` | Leverages Splunk Enterprise Security and SPL (Search Processing Language) | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/analyzing-security-logs-with-splunk/SKILL.md` |
| `analyzing-slack-space-and-file-system-artifacts` | Examine NTFS slack space, MFT entries, the USN Change Journal, and Alternate Data Streams (ADS) to… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/analyzing-slack-space-and-file-system-artifacts/SKILL.md` |
| `analyzing-usb-device-connection-history` | Correlate Windows registry keys (USBSTOR, MountedDevices), Event Logs, | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/analyzing-usb-device-connection-history/SKILL.md` |
| `analyzing-windows-amcache-artifacts` | Parses the Windows Amcache.hve registry hive with Eric Zimmerman''s | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/analyzing-windows-amcache-artifacts/SKILL.md` |
| `analyzing-windows-lnk-files-for-artifacts` | Parse Windows LNK shortcut files to extract target paths, MAC timestamps, | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/analyzing-windows-lnk-files-for-artifacts/SKILL.md` |
| `analyzing-windows-prefetch-with-python` | Parse Windows Prefetch (.pf) files with the windowsprefetch Python | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/analyzing-windows-prefetch-with-python/SKILL.md` |
| `analyzing-windows-registry-for-artifacts` | Extract and analyze Windows Registry hives with tools like RegRipper | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/analyzing-windows-registry-for-artifacts/SKILL.md` |
| `analyzing-windows-shellbag-artifacts` | Analyze Windows Shellbag (BagMRU) registry artifacts with SBECmd and | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/analyzing-windows-shellbag-artifacts/SKILL.md` |
| `building-incident-response-playbook` | Designs and documents structured incident response playbooks with step-by-step | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/building-incident-response-playbook/SKILL.md` |
| `building-incident-timeline-with-timesketch` | Build collaborative forensic incident timelines using Timesketch to ingest, | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/building-incident-timeline-with-timesketch/SKILL.md` |
| `building-malware-incident-communication-template` | Build structured communication templates for malware incidents (ransomware, | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/building-malware-incident-communication-template/SKILL.md` |
| `building-super-timelines-with-plaso` | Generate forensic super-timelines with Plaso's log2timeline.py, pinfo.py, | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/building-super-timelines-with-plaso/SKILL.md` |
| `building-threat-hunt-hypothesis-framework` | Build a systematic threat-hunt workflow that turns threat intelligence and ATT&CK gap analysis into… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/building-threat-hunt-hypothesis-framework/SKILL.md` |
| `collecting-indicators-of-compromise` | Systematically collects, categorizes, and distributes indicators of | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/collecting-indicators-of-compromise/SKILL.md` |
| `collecting-volatile-evidence-from-compromised-host` | Collect volatile forensic evidence from a compromised host by following the order of volatility, pr… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/collecting-volatile-evidence-from-compromised-host/SKILL.md` |
| `conducting-cloud-incident-response` | Respond to security incidents in AWS, Azure, and GCP via identity-based containment, cloud-native l… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/conducting-cloud-incident-response/SKILL.md` |
| `conducting-malware-incident-response` | Respond to malware infections across enterprise endpoints by identifying the malware family, determ… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/conducting-malware-incident-response/SKILL.md` |
| `conducting-memory-forensics-with-volatility` | Performs memory forensics analysis using Volatility 3 to extract evidence | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/conducting-memory-forensics-with-volatility/SKILL.md` |
| `conducting-phishing-incident-response` | Respond to phishing incidents by analyzing reported emails, extracting indicators, sandboxing URLs/… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/conducting-phishing-incident-response/SKILL.md` |
| `conducting-post-incident-lessons-learned` | Facilitate structured post-incident reviews to identify root causes, | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/conducting-post-incident-lessons-learned/SKILL.md` |
| `containing-active-breach` | Executes containment strategies to stop active adversary operations | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/containing-active-breach/SKILL.md` |
| `ctf-ai-ml` | Provides AI and machine learning techniques for CTF challenges. Use when attacking ML models, craft… | ctf-skills | MIT | `skills/ctf-ai-ml/SKILL.md` |
| `ctf-crypto` | Provides cryptography attack techniques for CTF challenges. Use when attacking encryption, hashing,… | ctf-skills | MIT | `skills/ctf-crypto/SKILL.md` |
| `ctf-forensics` | Provides digital forensics and signal analysis techniques for CTF challenges. Use when analyzing di… | ctf-skills | MIT | `skills/ctf-forensics/SKILL.md` |
| `ctf-malware` | Provides malware analysis and network traffic techniques for CTF challenges. Use when analyzing obf… | ctf-skills | MIT | `skills/ctf-malware/SKILL.md` |
| `ctf-misc` | Provides miscellaneous CTF challenge techniques for problems that do not cleanly fit the main categ… | ctf-skills | MIT | `skills/ctf-misc/SKILL.md` |
| `ctf-osint` | Provides open source intelligence techniques for CTF challenges. Use when gathering information fro… | ctf-skills | MIT | `skills/ctf-osint/SKILL.md` |
| `ctf-pwn` | Provides binary exploitation techniques for CTF challenges. Use when you already have a vulnerable… | ctf-skills | MIT | `skills/ctf-pwn/SKILL.md` |
| `ctf-reverse` | Provides reverse engineering techniques for CTF challenges. Use when the main job is to understand… | ctf-skills | MIT | `skills/ctf-reverse/SKILL.md` |
| `ctf-web` | Provides web exploitation techniques for CTF challenges. Use when the target is primarily an HTTP a… | ctf-skills | MIT | `skills/ctf-web/SKILL.md` |
| `ctf-writeup` | Generates a single standardized submission-style CTF writeup for competition handoff and organizer… | ctf-skills | MIT | `skills/ctf-writeup/SKILL.md` |
| `detecting-dcsync-attack-in-active-directory` | Detect DCSync attacks (MITRE T1003.006) where adversaries abuse Active Directory replication privil… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/detecting-dcsync-attack-in-active-directory/SKILL.md` |
| `detecting-dll-sideloading-attacks` | Detect DLL side-loading and search-order hijacking (MITRE T1574) where adversaries plant malicious… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/detecting-dll-sideloading-attacks/SKILL.md` |
| `detecting-email-account-compromise` | Detect compromised O365 and Google Workspace email accounts by analyzing Unified Audit Logs and Azu… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/detecting-email-account-compromise/SKILL.md` |
| `detecting-email-forwarding-rules-attack` | Detect malicious inbox/mail-flow forwarding rules that adversaries create to maintain | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/detecting-email-forwarding-rules-attack/SKILL.md` |
| `detecting-golden-ticket-attacks-in-kerberos-logs` | Detect Golden Ticket attacks in Active Directory using Splunk and KQL queries | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/detecting-golden-ticket-attacks-in-kerberos-logs/SKILL.md` |
| `detecting-insider-threat-behaviors` | Detect insider threat behavioral indicators including unusual data access, | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/detecting-insider-threat-behaviors/SKILL.md` |
| `detecting-kerberoasting-attacks` | Detect Kerberoasting attacks by monitoring for anomalous Kerberos TGS | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/detecting-kerberoasting-attacks/SKILL.md` |
| `detecting-lateral-movement-with-splunk` | Detect adversary lateral movement across networks using Splunk SPL queries | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/detecting-lateral-movement-with-splunk/SKILL.md` |
| `detecting-malicious-scheduled-tasks-with-sysmon` | Detect malicious scheduled task creation and modification using Sysmon | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/detecting-malicious-scheduled-tasks-with-sysmon/SKILL.md` |
| `detecting-mimikatz-execution-patterns` | Detect Mimikatz credential-dumping activity via command-line pattern matching, LSASS access signatu… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/detecting-mimikatz-execution-patterns/SKILL.md` |
| `detecting-ntlm-relay-with-event-correlation` | Detect NTLM relay attacks (T1557.001) by correlating Windows Event 4624 LogonType 3 for IP-to-hostn… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/detecting-ntlm-relay-with-event-correlation/SKILL.md` |
| `detecting-pass-the-hash-attacks` | Detect Pass-the-Hash (T1550.002) attacks by analyzing NTLM authentication patterns, flagging Type 3… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/detecting-pass-the-hash-attacks/SKILL.md` |
| `detecting-privilege-escalation-attempts` | Detect privilege escalation attempts across Windows and Linux, including access token manipulation,… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/detecting-privilege-escalation-attempts/SKILL.md` |
| `detecting-process-hollowing-technique` | Detect process hollowing (MITRE T1055.012) by analyzing memory-mapped | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/detecting-process-hollowing-technique/SKILL.md` |
| `detecting-process-injection-techniques` | Detects and analyzes process injection techniques used by malware including | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/detecting-process-injection-techniques/SKILL.md` |
| `detecting-rootkit-activity` | Detects rootkit presence on compromised systems by identifying hidden | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/detecting-rootkit-activity/SKILL.md` |
| `detecting-service-account-abuse` | Detect abuse of service accounts by hunting for anomalous interactive | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/detecting-service-account-abuse/SKILL.md` |
| `detecting-suspicious-powershell-execution` | Hunt for suspicious PowerShell execution (T1059.001) such as encoded commands, | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/detecting-suspicious-powershell-execution/SKILL.md` |
| `detecting-t1003-credential-dumping-with-edr` | Detect OS credential dumping (MITRE T1003) targeting LSASS memory, the SAM | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/detecting-t1003-credential-dumping-with-edr/SKILL.md` |
| `detecting-t1055-process-injection-with-sysmon` | Detect process injection techniques (T1055) - including DLL injection, process | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/detecting-t1055-process-injection-with-sysmon/SKILL.md` |
| `detecting-t1548-abuse-elevation-control-mechanism` | Detect abuse of elevation control mechanisms (T1548), including Windows UAC | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/detecting-t1548-abuse-elevation-control-mechanism/SKILL.md` |
| `detecting-wmi-persistence` | Detect WMI event subscription persistence (MITRE T1546.003) by analyzing Sysmon | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/detecting-wmi-persistence/SKILL.md` |
| `eradicating-malware-from-infected-systems` | Systematically map and remove malware, backdoors, and attacker persistence | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/eradicating-malware-from-infected-systems/SKILL.md` |
| `extracting-browser-history-artifacts` | Extracts and analyzes browser history, cookies, cache, downloads, and | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/extracting-browser-history-artifacts/SKILL.md` |
| `extracting-credentials-from-memory-dump` | Extracts cached credentials, password hashes, Kerberos tickets, and | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/extracting-credentials-from-memory-dump/SKILL.md` |
| `extracting-memory-artifacts-with-rekall` | Uses Rekall memory forensics framework to analyze memory dumps for process | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/extracting-memory-artifacts-with-rekall/SKILL.md` |
| `extracting-windows-event-logs-artifacts` | Extract, parse, and analyze Windows Event Logs (EVTX) using Chainsaw, | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/extracting-windows-event-logs-artifacts/SKILL.md` |
| `fleet-hunting-with-velociraptor` | Deploy a Velociraptor server and agents, then author VQL (Velociraptor Query Language) artifacts an… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/fleet-hunting-with-velociraptor/SKILL.md` |
| `generating-forensic-timelines-with-hayabusa` | Run Hayabusa against collected Windows EVTX files to apply Sigma detection rules and produce a prio… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/generating-forensic-timelines-with-hayabusa/SKILL.md` |
| `hitcon-dfir-vm-ops` | Connect to and operate the local dual-VM forensics analysis environment (Windows 10 FLARE-VM via vm… | framework internal | Not specified (internal work product) | `skills/hitcon-dfir-vm-ops/SKILL.md` |
| `hunting-evtx-with-chainsaw` | Run Chainsaw against collected Windows EVTX files to hunt with the SigmaHQ rule corpus, built-in de… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/hunting-evtx-with-chainsaw/SKILL.md` |
| `hunting-for-anomalous-powershell-execution` | Hunt for malicious PowerShell activity by analyzing Script Block Logging | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/hunting-for-anomalous-powershell-execution/SKILL.md` |
| `hunting-for-beaconing-with-frequency-analysis` | Identify command-and-control beaconing patterns in network traffic by | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/hunting-for-beaconing-with-frequency-analysis/SKILL.md` |
| `hunting-for-cobalt-strike-beacons` | Detect Cobalt Strike beacon command-and-control traffic using default TLS certificate signatures (s… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/hunting-for-cobalt-strike-beacons/SKILL.md` |
| `hunting-for-command-and-control-beaconing` | Detect C2 beaconing patterns in network traffic using frequency analysis, | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/hunting-for-command-and-control-beaconing/SKILL.md` |
| `hunting-for-data-exfiltration-indicators` | Hunt for data exfiltration by analyzing Zeek and Suricata network telemetry for unusual data flows,… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/hunting-for-data-exfiltration-indicators/SKILL.md` |
| `hunting-for-data-staging-before-exfiltration` | Detect data-staging activity (MITRE ATT&CK T1074) by analyzing EDR/Sysmon process-creation and file… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/hunting-for-data-staging-before-exfiltration/SKILL.md` |
| `hunting-for-dcom-lateral-movement` | Hunt for DCOM-based lateral movement (MITRE ATT&CK T1021.003) by detecting | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/hunting-for-dcom-lateral-movement/SKILL.md` |
| `hunting-for-dcsync-attacks` | Detect DCSync attacks (MITRE ATT&CK T1003.006) by analyzing Windows Event ID 4662 (AccessMask 0x100… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/hunting-for-dcsync-attacks/SKILL.md` |
| `hunting-for-defense-evasion-via-timestomping` | Detect NTFS timestamp manipulation (MITRE T1070.006) by comparing $STANDARD_INFORMATION | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/hunting-for-defense-evasion-via-timestomping/SKILL.md` |
| `hunting-for-dns-based-persistence` | Hunts for DNS-based persistence mechanisms such as DNS hijacking, dangling | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/hunting-for-dns-based-persistence/SKILL.md` |
| `hunting-for-dns-tunneling-with-zeek` | Detects DNS tunneling and covert-channel data exfiltration by analyzing | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/hunting-for-dns-tunneling-with-zeek/SKILL.md` |
| `hunting-for-domain-fronting-c2-traffic` | Detects domain fronting C2 traffic by analyzing SNI-vs-HTTP-Host-header | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/hunting-for-domain-fronting-c2-traffic/SKILL.md` |
| `hunting-for-lateral-movement-via-wmi` | Detects WMI-based lateral movement (e.g. wmic process call create, | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/hunting-for-lateral-movement-via-wmi/SKILL.md` |
| `hunting-for-living-off-the-cloud-techniques` | Hunts for adversary abuse of legitimate cloud services (Azure, AWS, GCP, | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/hunting-for-living-off-the-cloud-techniques/SKILL.md` |
| `hunting-for-living-off-the-land-binaries` | Proactively hunts for adversary abuse of legitimate, signed system binaries | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/hunting-for-living-off-the-land-binaries/SKILL.md` |
| `hunting-for-lolbins-execution-in-endpoint-logs` | Hunts for LOLBins (Living Off the Land Binaries) abuse, mapped to MITRE | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/hunting-for-lolbins-execution-in-endpoint-logs/SKILL.md` |
| `hunting-for-ntlm-relay-attacks` | Detects NTLM relay attacks (MITRE T1557.001) by analyzing Windows Event | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/hunting-for-ntlm-relay-attacks/SKILL.md` |
| `hunting-for-persistence-mechanisms-in-windows` | Systematically hunts for adversary persistence mechanisms across Windows | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/hunting-for-persistence-mechanisms-in-windows/SKILL.md` |
| `hunting-for-persistence-via-wmi-subscriptions` | Hunts for adversary persistence via WMI event subscriptions (MITRE T1546.003) | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/hunting-for-persistence-via-wmi-subscriptions/SKILL.md` |
| `hunting-for-process-injection-techniques` | Detects process injection techniques (MITRE T1055) — including | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/hunting-for-process-injection-techniques/SKILL.md` |
| `hunting-for-registry-persistence-mechanisms` | Hunts for registry-based persistence mechanisms (MITRE T1547) in Windows | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/hunting-for-registry-persistence-mechanisms/SKILL.md` |
| `hunting-for-registry-run-key-persistence` | Detect MITRE ATT&CK T1547.001 registry Run key persistence by analyzing | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/hunting-for-registry-run-key-persistence/SKILL.md` |
| `hunting-for-scheduled-task-persistence` | Runs a hypothesis-driven threat hunt for Windows Scheduled Task persistence (T1053), guiding SIEM/E… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/hunting-for-scheduled-task-persistence/SKILL.md` |
| `hunting-for-shadow-copy-deletion` | Runs a hypothesis-driven threat hunt for Volume Shadow Copy deletion (T1490) by querying SIEM/EDR t… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/hunting-for-shadow-copy-deletion/SKILL.md` |
| `hunting-for-spearphishing-indicators` | Hunt for spearphishing campaign indicators across email logs, endpoint | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/hunting-for-spearphishing-indicators/SKILL.md` |
| `hunting-for-startup-folder-persistence` | Detects T1547.001 startup folder persistence by monitoring Windows startup directories for suspicio… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/hunting-for-startup-folder-persistence/SKILL.md` |
| `hunting-for-supply-chain-compromise` | Runs a hypothesis-driven threat hunt for supply-chain compromise (T1195) by querying SIEM/EDR logs… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/hunting-for-supply-chain-compromise/SKILL.md` |
| `hunting-for-suspicious-scheduled-tasks` | Hunts for adversary persistence and execution via Windows scheduled tasks (T1053.005) by analyzing… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/hunting-for-suspicious-scheduled-tasks/SKILL.md` |
| `hunting-for-t1098-account-manipulation` | Hunts for MITRE ATT&CK T1098 account manipulation - shadow admin creation, SID history injection, g… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/hunting-for-t1098-account-manipulation/SKILL.md` |
| `hunting-for-unusual-network-connections` | Runs a hypothesis-driven threat hunt for command-and-control activity (T1071) by querying SIEM/EDR… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/hunting-for-unusual-network-connections/SKILL.md` |
| `hunting-for-unusual-service-installations` | Detects suspicious Windows service installations (MITRE ATT&CK T1543.003) by parsing System event l… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/hunting-for-unusual-service-installations/SKILL.md` |
| `hunting-for-webshell-activity` | Runs a hypothesis-driven threat hunt for web shell deployment (T1505.003) on internet-facing server… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/hunting-for-webshell-activity/SKILL.md` |
| `implementing-velociraptor-for-ir-collection` | Deploy and configure Velociraptor for scalable endpoint forensic artifact | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/implementing-velociraptor-for-ir-collection/SKILL.md` |
| `initial-incident-intake` | First-hour intake checklist + questions that produce an actionable scope and evidence plan. | awesome-dfir-skills | Apache-2.0 | `skills/initial-incident-intake/SKILL.md` |
| `investigating-ransomware-attack-artifacts` | Forensically preserve memory and disk, collect ransom notes and encrypted file samples, and identif… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/investigating-ransomware-attack-artifacts/SKILL.md` |
| `malware-analysis` | Professional malware analysis workflow for PE executables and suspicious files. Triggers on file up… | awesome-dfir-skills | Apache-2.0 | `skills/malware-analysis/SKILL.md` |
| `osquery-query-helper` | Help users write, validate, and troubleshoot osquery SQL queries using provided osquery table schem… | awesome-dfir-skills | Apache-2.0 | `skills/osquery-query-helper/SKILL.md` |
| `parsing-artifacts-with-eric-zimmerman-tools` | Parse Windows forensic artifacts—$MFT/$J (MFTECmd), Prefetch (PECmd), registry hives (RECmd), shell… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/parsing-artifacts-with-eric-zimmerman-tools/SKILL.md` |
| `performing-active-directory-compromise-investigation` | Investigate Active Directory compromise by analyzing authentication logs, | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/performing-active-directory-compromise-investigation/SKILL.md` |
| `performing-cloud-forensics-investigation` | Collect and analyze cloud forensic evidence using AWS CLI, Azure CLI, or gcloud | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/performing-cloud-forensics-investigation/SKILL.md` |
| `performing-cloud-incident-containment-procedures` | Execute cloud-native incident containment across AWS, Azure, and GCP using platform | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/performing-cloud-incident-containment-procedures/SKILL.md` |
| `performing-cloud-storage-forensic-acquisition` | Perform forensic acquisition of cloud storage services including Google | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/performing-cloud-storage-forensic-acquisition/SKILL.md` |
| `performing-disk-forensics-investigation` | Conduct disk forensics investigations using forensic imaging, file system | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/performing-disk-forensics-investigation/SKILL.md` |
| `performing-file-carving-with-foremost` | Recovers files from disk images and unallocated space using Foremost's | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/performing-file-carving-with-foremost/SKILL.md` |
| `performing-insider-threat-investigation` | Investigates insider threat incidents involving employees, contractors, | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/performing-insider-threat-investigation/SKILL.md` |
| `performing-linux-log-forensics-investigation` | Perform forensic investigation of Linux system logs including syslog, | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/performing-linux-log-forensics-investigation/SKILL.md` |
| `performing-log-analysis-for-forensic-investigation` | Collect, parse, and correlate system, application, and security logs | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/performing-log-analysis-for-forensic-investigation/SKILL.md` |
| `performing-malware-persistence-investigation` | Systematically investigate all persistence mechanisms on Windows and | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/performing-malware-persistence-investigation/SKILL.md` |
| `performing-memory-forensics-with-volatility3` | Analyze volatile memory (RAM) dumps using the Volatility 3 framework | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/performing-memory-forensics-with-volatility3/SKILL.md` |
| `performing-memory-forensics-with-volatility3-plugins` | Analyze memory dumps using Volatility3 plugins to detect injected code, | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/performing-memory-forensics-with-volatility3-plugins/SKILL.md` |
| `performing-mobile-device-forensics-with-cellebrite` | Acquire and analyze mobile device data using Cellebrite UFED Touch/4PC, UFED Physical Analyzer, and… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/performing-mobile-device-forensics-with-cellebrite/SKILL.md` |
| `performing-network-forensics-with-wireshark` | Capture and analyze network traffic using Wireshark and tshark to reconstruct network events from P… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/performing-network-forensics-with-wireshark/SKILL.md` |
| `performing-network-packet-capture-analysis` | Perform forensic analysis of network packet captures (PCAP/PCAPNG) using Wireshark, tshark, and tcp… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/performing-network-packet-capture-analysis/SKILL.md` |
| `performing-ransomware-response` | Executes a structured ransomware incident response from detection through | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/performing-ransomware-response/SKILL.md` |
| `performing-sqlite-database-forensics` | Performs forensic analysis of SQLite databases by examining B-tree page | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/performing-sqlite-database-forensics/SKILL.md` |
| `performing-steganography-detection` | Detects and extracts hidden data embedded in images, audio, and other media files using steganalysi… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/performing-steganography-detection/SKILL.md` |
| `performing-threat-hunting-with-yara-rules` | Use YARA pattern-matching rules to hunt for malware, suspicious files, | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/performing-threat-hunting-with-yara-rules/SKILL.md` |
| `performing-timeline-reconstruction-with-plaso` | Builds comprehensive forensic super-timelines using Plaso (log2timeline and psort) to correlate eve… | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/performing-timeline-reconstruction-with-plaso/SKILL.md` |
| `performing-windows-artifact-analysis-with-eric-zimmerman-tools` | Performs comprehensive Windows forensic artifact analysis using Eric | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/performing-windows-artifact-analysis-with-eric-zimmerman-tools/SKILL.md` |
| `recovering-deleted-files-with-photorec` | Recovers deleted files from disk images and storage media using PhotoRec's | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/recovering-deleted-files-with-photorec/SKILL.md` |
| `solve-challenge` | Solves CTF challenges by performing first-pass triage, identifying the dominant category, and routi… | ctf-skills | MIT | `skills/solve-challenge/SKILL.md` |
| `suspicious-powershell-hunt` | Hypothesis-driven hunt plan for suspicious PowerShell, plus query snippets for common telemetry. | awesome-dfir-skills | Apache-2.0 | `skills/suspicious-powershell-hunt/SKILL.md` |
| `testing-ransomware-recovery-procedures` | Tests and validates ransomware recovery procedures - backup restore operations | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/testing-ransomware-recovery-procedures/SKILL.md` |
| `threat-actor-profiling` | Build structured threat actor profiles using the 5W1H framework and the Diamond Model. Use this ski… | awesome-dfir-skills | Apache-2.0 | `skills/threat-actor-profiling/SKILL.md` |
| `triaging-security-incident` | Performs initial triage of security incidents using the NIST SP | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/triaging-security-incident/SKILL.md` |
| `triaging-security-incident-with-ir-playbook` | Classifies and prioritizes security incidents using structured IR | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/triaging-security-incident-with-ir-playbook/SKILL.md` |
| `triaging-windows-with-kape` | Runs KAPE (Kroll Artifact Parser and Extractor) to collect targeted | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/triaging-windows-with-kape/SKILL.md` |
| `validating-backup-integrity-for-recovery` | Validates backup integrity through cryptographic hash verification, | Anthropic Cybersecurity Skills | Apache-2.0 | `skills/validating-backup-integrity-for-recovery/SKILL.md` |
| `windows-intrusion-timeline` | Create a targeted intrusion timeline for a Windows incident using whatever artifacts are available… | awesome-dfir-skills | Apache-2.0 | `skills/windows-intrusion-timeline/SKILL.md` |

## 來源與授權（provenance）

| 來源 | 快照 | commit | 授權 | 技能數 |
|------|------|--------|------|--------|
| ctf-skills | `Security-LabData/external-skills/ctf-skills` | `c332c7be1b27cb64639a20124ac55ba916adef92` | MIT | 11 |
| awesome-dfir-skills | `Security-LabData/external-skills/awesome-dfir-skills` | `6e52942c6273a760296c38ca6ce950bbed4dfbdf` | Apache-2.0 | 8 |
| Anthropic Cybersecurity Skills | `Security-LabData/external-skills/Anthropic-Cybersecurity-Skills` | `54a798831d2266a3ca61ce68a7acb80b81160d57` | Apache-2.0 | 132 |
| framework internal | `(in-repo)` | `-` | Not specified (internal work product) | 1 |

> 註：`授權` 欄優先取 SKILL.md frontmatter 的 `license`；若技能未宣告，則回退到 `SOURCES.json` 中其來源的授權。
