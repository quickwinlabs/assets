# quickwinlabs/assets

quickwin CI/开发用的二进制资产仓:Windows 测试 ISO(分卷),将来也放 XP 可用的
ffmpeg 等工具链二进制。一个资产族 = 一个 release(tag + 分卷 + `SHA256SUMS.txt`)。

## Windows 测试 ISO

由 CI(`workflow_dispatch` 手动触发)从公开镜像源下载、校验、分卷后发布。
单文件 < 2GiB 的 GitHub release 硬限故采用 `split -b 1800m` 分卷。

| 类型 | release tag | workflow | 原始文件 | 大小 |
|---|---|---|---|---|
| XP | `win-isos-xp` | `build-xp.yml` | `zh-hans_windows_xp_professional_with_service_pack_3_x86_cd_vl_x14-74070.iso` | 602MB |
| Win7 | `win-isos-win7` | `build-win7.yml` | `cn_windows_7_ultimate_with_sp1_x64_dvd_u_677408.iso` | 3.2GB |
| Tiny11 | `win-isos-tiny11` | `build-tiny11.yml` | `Tiny11Core-25H2-...iso` 或备源 `tiny11core_25H2_Nov25.iso` | 3.0GB |

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

## 刷新 / 新增资产族

- **刷新**:重跑对应 workflow——重新从镜像源下载、覆盖同名分卷并更新 notes。
- **新增类型**:复制任一 workflow(改 1 行 `publish.sh` 参数)+ 在
  `scripts/publish.sh` 的 case 表加一个 tag 映射(ISO 定义在
  `scripts/download-iso.sh`,镜像源唯一真相在那)。

## 版权说明

Windows ISO 为微软版权材料,本仓资产**仅供 quickwin 项目 CI/测试用途**,
Tiny11 为社区第三方精简构建。请勿再分发。
