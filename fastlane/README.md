fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios fetch_cert

```sh
[bundle exec] fastlane ios fetch_cert
```

获取/创建 Apple Distribution 证书（用于从证书 subject 读取 Team ID）

### ios build

```sh
[bundle exec] fastlane ios build
```

生成 Xcode 工程并构建 Release 包（自动签名）

### ios beta

```sh
[bundle exec] fastlane ios beta
```

打包并上传 TestFlight

### ios upload

```sh
[bundle exec] fastlane ios upload
```

仅上传已打好的 IPA 到 TestFlight

### ios register_bundle_id

```sh
[bundle exec] fastlane ios register_bundle_id
```

通过 API 注册 Bundle ID 和 App Group（App 记录需用户在 ASC 网页点一次新建）

### ios create_app

```sh
[bundle exec] fastlane ios create_app
```

创建 App Store 应用记录（首次）

### ios metadata

```sh
[bundle exec] fastlane ios metadata
```

上传元数据 + 截图（不提交审核）

### ios submit

```sh
[bundle exec] fastlane ios submit
```

提交审核（需用户口头确认后执行）

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
