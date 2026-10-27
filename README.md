# quickwinlabs/assets

quickwin CI/开发用的二进制资产仓:Windows 测试 ISO 与预装系统盘(均为分卷),
将来也放 XP 可用的 ffmpeg 等工具链二进制。一个资产族 = 一个 release
(tag + 分卷 + `SHA256SUMS.txt`)。

## Windows 测试 ISO

由 CI(`workflow_dispatch` 手动触发)从公开镜像源下载、校验、分卷后发布。
单文件 < 2GiB 的 GitHub release 硬限故采用 `split -b 1800m` 分卷。

| 类型 | release tag | workflow | 原始文件 | 大小 |
|---|---|---|---|---|
| XP | `win-isos-xp` | `build-xp.yml` | `zh-hans_windows_xp_professional_with_service_pack_3_x86_cd_vl_x14-74070.iso` | 602MB |
| Win7 | `win-isos-win7` | `build-win7.yml` | `cn_windows_7_ultimate_with_sp1_x64_dvd_u_677408.iso` | 3.2GB |
| Tiny11 Core | `win-isos-tiny11` | `build-tiny11.yml` | `tiny11core_25H2_Nov25.iso` | 3.3GB |
| Tiny11 标准盘 | `win-isos-tiny11-std` | `build-tiny11-std.yml` | `tiny11_25H2_Nov25.iso` | 5.3GB |

### 消费方式

```bash
# 1. 下载分卷(按 release 资产名)与 SHA256SUMS.txt
gh release download win-isos-xp -p 'zh-hans_windows_xp*.part*' -p SHA256SUMS.txt

# 2. 校验分卷 + 重组
sha256sum -c SHA256SUMS.txt --ignore-missing
cat zh-hans_windows_xp*.part* > xp.iso

# 3. 校验重组后的原始 ISO(SHA256SUMS.txt 第一行)
sha256sum -c SHA256SUMS.txt --ignore-missing
```

sha256 是唯一 integrity 锚点:release 资产可被重跑覆盖(`--clobber`),
消费方务必校验 `SHA256SUMS.txt`。

## 预装系统盘(win-images-*)

`images/setup-*.sh` 在 GitHub runner 上现场安装一份 Windows 盘(ISO 取自上面
`win-isos-*` 的 release,见 `scripts/fetch-release-iso.sh`),压缩后分卷发布
(`scripts/make-image-release.sh`;`build-image.yml` 手动触发,一次一个 type)。
给不想自己装 Windows 的人直接下载使用。

| 类型 | release tag | 源 ISO | 盘 | 压缩前 → 压缩后 | 卷数 |
|---|---|---|---|---|---|
| XP | `win-images-xp` | `win-isos-xp` | `xp_ready.qcow2` | 1.46GiB → 0.75GiB (52%) | 1 |
| Win7 | `win-images-win7` | `win-isos-win7` | `win7_ready.qcow2` | 7.33GiB → 3.36GiB (46%) | 2 |
| Tiny11 标准盘 | `win-images-win11` | `win-isos-tiny11-std` | `win11_ready.qcow2` | 12.7GiB → 10.4GiB (82%) | 6 |

(以上为 2026-10 实测值。win11 压不动是有原因的:25H2 盘里大部分是已压缩内容
——installer 载荷、Defender 定义库,不像 XP/Win7 那样满是可压的系统文件。)

压缩用 qcow2 原生压缩簇(`qemu-img convert -c -o compression_type=zstd`):qemu
能直接读(不必先解压),同时把整盘压小、再按 <2GiB 分卷。**代价:需要 qemu
≥ 5.4,且压缩盘是只读形态,使用时要叠 overlay**(quickwin 的 `run.sh` 本来
就是叠 overlay 跑的)。

### 消费方式

参考实现在 [quickwin/docker](https://github.com/quickwinlabs/quickwin/tree/main/docker),
拉盘、起机、SMB 共享、下发测试都已接好。下面两条路任选。

**A. 用 quickwin 的 docker/**(推荐)

```bash
cd quickwin/docker
./scripts/fetch-ready.sh win7    # 拉分卷 → 校验 → 拼成 snapshots/win7_ready.qcow2
./run.sh win7                    # 叠 overlay、起 QEMU、等 execd 健康
./http_test.sh win7              # 经 execd 下发 test/run.js
```

**B. 裸 qemu 手动起**(只需要本仓的盘)

```bash
# 1. 拉分卷 + 校验 + 重组
gh release download win-images-win7 -D .
cat win7_ready.qcow2.part* > win7_ready.qcow2
sha256sum -c SHA256SUMS.txt

# 2. 叠 overlay —— 压缩盘是只读形态,不能直接写
qemu-img create -f qcow2 -b win7_ready.qcow2 -F qcow2 win7_test.qcow2

# 3. 起机(SMB 共享不能省,见下节)
qemu-system-x86_64 -accel kvm \
  -hda win7_test.qcow2 -m 4096 -smp 4 \
  -netdev user,id=net0,guestfwd=tcp:10.0.2.4:445-cmd:"$PWD/smb_wrapper.sh",hostfwd=tcp::8007-:8080 \
  -device e1000,netdev=net0 \
  -display none -vnc 0.0.0.0:2 \
  -monitor unix:/tmp/qemu-monitor-win7.sock,server,nowait \
  -daemonize
```

两个必须注意的:

- `-b` 用 **basename**(相对路径)。qcow2 的 backing 名按"相对 overlay 所在目录"记录,
  写成绝对路径后换个目录/换台机器就打不开,所以 overlay 要和盘放同一目录。
- 别把压缩盘当可写盘直接挂(只读形态,写进去会报错或丢数据),必须叠 overlay。

### 盘不自足:必须配 SMB 共享

盘里只有系统 + `C:\OEM\bootstrap.bat`(注册在 `Run` 键自动启动;XP 在 `HKLM`,
Win7/Win11 在 `HKCU`)。开机后的链路是:

```plain
bootstrap.bat(Run 键自动触发)
  -> net use Z: \\10.0.2.4\qemu     # 宿主的 SMB 共享
  -> call Z:\run.bat                # 关防火墙、配 portproxy、起 execd
```

**`run.bat` 和 `execd.exe` 都不在盘里**,在宿主共享目录里。所以:

- 不给共享 → 系统能起来,但 execd 永远不会启动(`C:\Windows\Temp\bootstrap.log`
  里是 `SMB mount FAILED`)
- XP 只支持 SMB1,QEMU 自带的 `-smb` 是 SMB2/3 且不可配 → 必须用 `guestfwd` 挂自管的
  smbd,见 [smb_wrapper.sh](https://github.com/quickwinlabs/quickwin/blob/main/docker/smb_wrapper.sh)

`run.bat` 在 [ci_share/run.bat](https://github.com/quickwinlabs/quickwin/blob/main/docker/ci_share/run.bat),
共享目录是 `docker/ci_share/`(其中 `quickwin` 是指向编译产物的 symlink)。`execd.exe`
同样不在盘里,直接下
[execd-x86.exe](https://github.com/quickwinlabs/quickwin/releases/latest/download/execd-x86.exe)
→ 存成 `execd.exe`(`run.bat` 认的是这个文件名);32 位 exe 在 x64 上走 WoW64,同样能用。

也可以本地 `make execd`(源码在 [examples/execd](https://github.com/quickwinlabs/quickwin/tree/main/examples/execd)),
产出 `_build/execd.exe`。

### 端口 / 硬件对照

抄自 [run.sh](https://github.com/quickwinlabs/quickwin/blob/main/docker/run.sh) 的 case 表,
改这里前先改那边。助记:`HTTP = 8000+版本号`,`noVNC = 6000+版本号`。

| VM | hostfwd | noVNC | VNC display | machine | 网卡 | mem / smp |
|---|---|---|---|---|---|---|
| XP | 8005 | 6005 | `:1` | `pc-i440fx-5.2` + `-cpu qemu32` | rtl8139 | 1024 / 1 |
| Win7 | 8007 | 6007 | `:2` | 默认 | e1000 | 4096 / 4 |
| Win11 | 8011 | 6011 | `:3` | `q35` + OVMF 4M pflash | e1000e | 8192 / 4 |

XP/Win7 是 BIOS/MBR,Win11 是 UEFI/GPT 装的、必须 pflash 引导。两边都不需要
TPM 或 Secure Boot。

## 起来之后:用 execd

execd 常驻在 guest 的 8080,由 hostfwd 映射到宿主的 `8000+版本号`。**它是自描述的**:
任意非 API 路径返回完整端点与参数,所以下面只列最常用的三条,端点全集以服务自描述为准。

```bash
# 自描述 + 探活:免鉴权,VM 刚起来 token 还没配时也能用
curl http://127.0.0.1:8007/

# 跑命令:输出流式回来,退出码在 HTTP trailer(不在 header)
curl -X POST http://127.0.0.1:8007/exec \
  -H 'Content-Type: application/json' -d '{"cmd":"ver"}'

# 起常驻 GUI:/exec 会挂到超时且断连即 kill,常驻程序必须用 /spawn
curl -s -X POST http://127.0.0.1:8007/spawn \
  -H 'Content-Type: application/json' -d '{"cmd":"Z:\\quickwin\\app.exe"}'
```

三条容易踩的语义:

- **编码**:`/exec` 恒走 `cmd.exe /u`,cmd 内建命令(`dir`/`type`)输出是 **UTF-16LE**;
  外部程序仍是各自原生编码(中文系统 GBK)。测试输出是 UTF-8/ASCII,不受影响。
- **断连即 kill**:客户端断开,服务端 `taskkill /F /T` 递归清掉整棵进程树。
- **timeout 默认无限**:不传就一直跑;传了到点强杀,trailer 记 `X-Exit-Code: -1`。

## 刷新 / 新增资产族

- **ISO 刷新**:重跑对应 workflow——重新从镜像源下载、覆盖同名分卷并更新 notes。
- **ISO 新增类型**:复制任一 workflow(改 1 行 `publish.sh` 参数)+ 在
  `scripts/publish.sh` 的 case 表加一个 tag 映射(ISO 定义在
  `scripts/download-iso.sh`,镜像源唯一真相在那)。
- **盘刷新**:重跑 `build-image.yml`(选 type)——发布前先把该 tag 的旧资产整体
  删掉再上传,所以分卷数变化不会留下孤儿卷。
- **盘新增类型**:在 `scripts/make-image-release.sh` 的 case 表 + `build-image.yml`
  的 `type` 选项各加一项;装新系统还要加 `images/setup-<type>.sh` 与其 floppy 目录。
- **装机取 ISO**:`images/setup-*.sh` 用
  `scripts/fetch-release-iso.sh <xp|7u|tiny11|tiny11std> <目录>`
  拉**已发布的 release**(分卷 → 校验 → 拼回整盘)。
  它与 `publish.sh` 用的 `download-iso.sh` 方向相反——后者拉**上游镜像源**(发布用),
  不要互相调用。
- **装机脚本**:`images/setup-*.sh` 是装机逻辑的唯一维护地(quickwin 仓已无装机脚本,
  只剩 `docker/run.sh` 这一套运行时)。Win11 盘**不含 TPM/Secure Boot**:硬件检查由
  `Autounattend.xml` 的 `LabConfig` 键在 WinPE 阶段绕过,runner 侧因此用非 secboot
  的 4M OVMF。

## 版权说明

Windows ISO 为微软版权材料,本仓资产**仅供 quickwin 项目 CI/测试用途**,
Tiny11 为社区第三方精简构建。`win-images-*` 里是**已安装(且可能已激活)的
Windows 系统盘**,同样仅供 quickwin 项目 CI/测试用途。请勿再分发。
