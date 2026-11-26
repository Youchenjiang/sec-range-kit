# Forensic

## Files and images

```bash
file x ; exiftool x ; binwalk x ; binwalk -e x      # embedded archives/images
foremost -i x -o out/                               # carve by magic bytes
pngcheck -v x.png                                    # broken chunks, wrong CRC, extra data after IEND
zsteg x.png ; zsteg -a x.png                         # LSB stego in PNG/BMP
steghide extract -sf x.jpg -p ''                     # JPEG/WAV stego, empty password first
stegseek x.jpg rockyou.txt                           # when steghide needs a password
```

- Wrong magic bytes or a cropped image: fix the header in HxD / `xxd`; for PNG height edits, recompute the IHDR CRC.
- Audio: spectrogram in Audacity / Sonic Visualiser; `sox x.wav -n spectrogram`.
- QR / barcodes: `zbarimg x.png`.

## Documents

```bash
olevba x.docm            # Office macros
pdfid x.pdf ; qpdf --qdf x.pdf out.pdf ; pdftotext x.pdf -   # PDF objects and text
unzip -l x.docx           # docx/xlsx/apk/jar are zip files
```

## Network captures

```bash
tshark -r x.pcap -qz io,phs                     # protocol hierarchy
tshark -r x.pcap -qz conv,tcp                   # conversations
tshark -r x.pcap -Y http.request -T fields -e http.host -e http.request.uri
tshark -r x.pcap --export-objects http,out/     # also smb, imf, tftp
```

Wireshark: Follow TCP/HTTP stream, Statistics > Conversations, File > Export Objects. TLS keys given? Preferences > TLS > (Pre)-Master-Secret log. USB HID captures: decode keyboard usage IDs from `usb.capdata`.

## Memory images (Volatility 3)

```bash
vol -f mem.raw windows.info
vol -f mem.raw windows.pslist ; windows.pstree ; windows.cmdline ; windows.netscan
vol -f mem.raw windows.filescan | grep -i flag ; vol -f mem.raw windows.dumpfiles --virtaddr <addr>
vol -f mem.raw windows.hashdump ; windows.consoles   # (Linux images: linux.bash, linux.pslist)
```

## Disk images and logs

- `mmls disk.img` then `fls -r -o <offset> disk.img` / `icat` (Sleuth Kit); or mount read-only.
- E01 / AD1 / ESE databases / auditd: the kit's DFIR parsers in `rangekit/dfir/` (see its README).
- Windows event logs: `rangekit/vm/collect/evtx_export.ps1` runs EvtxECmd, Hayabusa and Chainsaw on the host VM.
- Deleted or overwritten data: `strings`, `photorec`, and git objects (`git fsck --lost-found`).
