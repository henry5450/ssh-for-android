# ssh-for-android

OpenSSH **10.6p1** 客户端，适用于 Android **arm64-v8a**（bionic libc，API 28+）。

- 程序安装前缀：`/data/local/tmp/home/usr`
- 配置与密钥目录：`/data/local/tmp/home`
- 预编译包：[Releases / v10.6p1](https://github.com/henry5450/ssh-for-android/releases/tag/v10.6p1)

> 本仓库和预编译包都不包含任何私钥、`known_hosts` 或设备相关密钥文件。

## 特性

- OpenSSH 10.6p1（上游提交 `26b1363c7`）
- OpenSSL 3.5.5，静态链接 `libcrypto`
- AArch64 PIE，16KB 页对齐，无 RPATH
- 运行时只依赖 Android 系统库：`libc.so`、`libdl.so`、`libz.so`
- 提供：`ssh`、`scp`、`sftp`、`ssh-add`、`ssh-agent`、`ssh-keygen`、`ssh-keyscan`、`ssh-pkcs11-helper`、`ssh-sk-helper`
- 配置和密钥强制落在 `/data/local/tmp/home`；可用 `SSH_ANDROID_HOME` 覆盖
- 针对 bionic / Android 的 6 个补丁，见下文

## 安装

下载 Release 中的 `ssh-for-android-v10.6p1-aarch64.zip`：

```sh
unzip ssh-for-android-v10.6p1-aarch64.zip
cd ssh-for-android-v10.6p1-aarch64
./install.sh --serial 192.168.3.105:5555
```

或手动部署：

```sh
adb push home/. /data/local/tmp/home/
adb shell 'chmod 0755 /data/local/tmp/home/usr/bin/* /data/local/tmp/home/usr/libexec/*; \
           chmod 0700 /data/local/tmp/home/.ssh; \
           chmod 0600 /data/local/tmp/home/.ssh/config'
```

安装脚本不会生成密钥，也不会覆盖已有的 `.ssh/config` 或 `id_*`。

## 目录结构

```
/data/local/tmp/home/
├── .ssh/
│   └── config                 # 0600，仅模板
├── tmp/                       # 0700，可选 TMPDIR
└── usr/
    ├── bin/
    │   ├── ssh  scp  sftp  ssh-add  ssh-agent  ssh-keygen  ssh-keyscan
    ├── libexec/
    │   ├── ssh-pkcs11-helper  ssh-sk-helper
    └── etc/ssh/
        └── ssh_config         # 系统级配置
```

## 使用

```sh
adb shell
export PATH=/data/local/tmp/home/usr/bin:$PATH

ssh -V
ssh user@example.com
```

生成密钥（默认路径已经是 `/data/local/tmp/home/.ssh/id_ed25519`）：

```sh
ssh-keygen -t ed25519 -N ''
```

使用 ssh-agent 时建议显式指定 socket：

```sh
eval "$(ssh-agent -a /data/local/tmp/home/.ssh/agent.sock -s)"
```

如果要把“家目录”换到别处，可设置：

```sh
export SSH_ANDROID_HOME=/some/other/home
```

注意：系统级 `ssh_config` 的路径是编译期固定的
`/data/local/tmp/home/usr/etc/ssh/ssh_config`；如果要换安装前缀，需要重新编译。

### 在 KernelSU 模块中使用 `/system/bin/ssh`（可选）

仓库提供 `scripts/install-module.sh`，它会把 `ssh` 复制进指定模块的
`system/bin/`，并保留原有的 `/system/bin/ssh` 包装脚本为
`ssh-termux-wrapper`：

```sh
./scripts/install-module.sh \
  --module /data/adb/modules/custom_system_shell \
  --binary ./home/usr/bin/ssh \
  --yes
# 然后重启
```

重启后 `/system/bin/ssh` 就是本项目的二进制。注意：

- 原包装脚本通过 `su` 调用 Termux 的 ssh；替换后 `ssh` 直接以当前用户运行。
- 模块里的 `ssh-termux` 如果内部调用裸 `ssh`，会改用新二进制；需要保持原行为时，
  请把它里面的 `ssh` 改成 `/data/data/com.termux/files/usr/bin/ssh`。
- 直接写 `/system` 是不行的，必须通过 KernelSU 模块的 overlay。

## 构建

要求：Linux x86_64、Android NDK r29（默认 API 28）、`gcc`、`make`、`perl`、
`m4`、`curl`、`patch`、`zip`。不需要 root/sudo。

```sh
export ANDROID_NDK_ROOT=/path/to/android-ndk-r29
./scripts/build.sh
```

构建脚本会自动下载并编译：

- autoconf 2.72（本机构建）
- OpenSSL 3.5.5（静态、arm64）
- OpenSSH 10.6p1（提交 `26b1363c7`）

产物：

```
build/stage/home/                                      # 可直接推送的目录树
build/dist/ssh-for-android-v10.6p1-aarch64.zip         # 发布包
build/dist/SHA256SUMS
```

重新打包已有暂存目录：

```sh
./scripts/package.sh build/stage/home build/dist
```

## 补丁说明

| 补丁 | 作用 |
| --- | --- |
| `0001-android-home.patch` | 让 `ssh`/`ssh-keygen`/`ssh-add`/`ssh-agent` 和 `~` 展开使用固定目录 `/data/local/tmp/home`（`SSH_ANDROID_HOME` 可覆盖），不再依赖 bionic 的 `pw_dir` |
| `0002-android-explicit-bzero.patch` | bionic 的 `bzero` 是 inline 宏，不能取地址；改用 `memset` |
| `0003-readconf-perm.patch` | 放宽用户配置的属主检查（仍拒绝组/其他用户可写），便于 shell 推送、root 运行 |
| `0004-android-getrrsetbyname-stub.patch` | bionic `<resolv.h>` 不提供 BIND resolver 状态；SSHFP-over-DNS 用 stub 禁用 |
| `0005-android-freerrset-stub.patch` | 为上面的 stub 补 `freerrset` |
| `0006-android-no-hardlink.patch` | Android 在 `/data/local/tmp` 拒绝硬链接；`known_hosts`、mux socket、`ssh-keygen -R` 的备份改用 `rename()` |

另外构建时使用 `CPPFLAGS=-DHAVE_ATTRIBUTE__SENTINEL__=1`，避免 bionic 的
`unistd.h` 中 `__sentinel__(1)` 与 OpenSSH 的 `__sentinel__` 宏冲突。

## 已知限制

- 仅客户端：未安装 `sshd`、`sshd-session`、`sshd-auth`、`sftp-server`、`ssh-keysign`
- FIDO2/安全密钥未验证（未交叉编译 libfido2）
- DNS SSHFP 查询已禁用（bionic resolver 限制）
- 硬链接回退使用 `rename()`，不是严格的原子操作
- 配置属主检查已放宽，适合单用户/已 root 的设备；私钥仍要求 0600
- 二进制为固定前缀 `/data/local/tmp/home` 编译；换前缀需重新构建
- 运行时依赖系统 `libz.so`

## 安全说明

- 本仓库不包含任何密钥；请自行生成并妥善保管私钥（0600）
- shell 和 root 混用时注意文件属主：root 生成的 0600 私钥，shell 用户无法读取
- 部署前可用 `sha256sum -c SHA256SUMS` 校验发布包

## 测试环境

- Redmi K90 Pro Max（`myron`），Android 16 / API 36，arm64-v8a
- KernelSU 4.2.1
- 与 Termux sshd 的本机回环测试成功协商 `mlkem768x25519-sha256`

## 许可证

- 本仓库的补丁与脚本：BSD-2-Clause，见 [LICENSE](LICENSE)
- OpenSSH：见 [LICENSE.openssh](LICENSE.openssh)
- OpenSSL：见 [LICENSE.openssl](LICENSE.openssl)

预编译二进制包含 OpenSSH 与 OpenSSL 代码，分别遵循上述两份上游许可证。

## 贡献者

henry5450
