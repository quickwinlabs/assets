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
| Tiny11 标准盘 | `win-images-win11` | `win-isos-tiny11-std` | `win11_ready.qcow2` | 12.0GiB → 10.1GiB (84%) | 6 |

(以上为 2026-10 实测值。win11 压不动是有原因的:25H2 盘里大部分是已压缩内容
——installer 载荷、Defender 定义库,不像 XP/Win7 那样满是可压的系统文件。)

压缩用 qcow2 原生压缩簇(`qemu-img convert -c -o compression_type=zstd`):qemu
能直接读(不必先解压),同时把整盘压小、再按 <2GiB 分卷。**代价:需要 qemu
≥ 5.4,且压缩盘是只读形态,使用时要叠 overlay**(quickwin 的 `run.sh` 本来
就是叠 overlay 跑的)。

### 消费方式

```bash
# 1. 拉分卷 + 校验 + 重组
gh release download win-images-win7 -D .
cat win7_ready.qcow2.part* > win7_ready.qcow2
sha256sum -c SHA256SUMS.txt

# 2. 交给 quickwin:放到 docker/snapshots/ 后即可
#    cd quickwin/docker && ./run.sh win7
#    (run.sh 自己创建 overlay;单独手动跑则:)
qemu-img create -f qcow2 -b win7_ready.qcow2 -F qcow2 overlay.qcow2
```

装机侧取 ISO 用 `scripts/fetch-release-iso.sh <xp|7u|tiny11|tiny11std> <目录>`
(拉对应 ISO release 的分卷 → 校验 → 拼回整盘)。注意它与 `publish.sh` 用的
`download-iso.sh` 方向相反:后者拉**上游镜像源**(发布用),前者拉**已发布的
release**(装机用),不要互相调用。

## 刷新 / 新增资产族

- **ISO 刷新**:重跑对应 workflow——重新从镜像源下载、覆盖同名分卷并更新 notes。
- **ISO 新增类型**:复制任一 workflow(改 1 行 `publish.sh` 参数)+ 在
  `scripts/publish.sh` 的 case 表加一个 tag 映射(ISO 定义在
  `scripts/download-iso.sh`,镜像源唯一真相在那)。
- **盘刷新**:重跑 `build-image.yml`(选 type)——发布前先把该 tag 的旧资产整体
  删掉再上传,所以分卷数变化不会留下孤儿卷。
- **盘新增类型**:在 `scripts/make-image-release.sh` 的 case 表 + `build-image.yml`
  的 `type` 选项各加一项;装新系统还要加 `images/setup-<type>.sh` 与其 floppy 目录。
- **装机脚本**:`images/setup-*.sh` 是 quickwin `docker/setup-*.sh` 的副本,
  改装机逻辑时两边都要改(差异只在 ISO 来源、OVMF 路径与产物用途)。
  Win11 两侧都**不含 TPM/Secure Boot**:硬件检查由 `Autounattend.xml` 的
  `LabConfig` 键在 WinPE 阶段绕过,runner 侧因此用非 secboot 的 4M OVMF。

## 版权说明

Windows ISO 为微软版权材料,本仓资产**仅供 quickwin 项目 CI/测试用途**,
Tiny11 为社区第三方精简构建。`win-images-*` 里是**已安装(且可能已激活)的
Windows 系统盘**,同样仅供 quickwin 项目 CI/测试用途。请勿再分发。
