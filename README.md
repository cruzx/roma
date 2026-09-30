# 漫游 · Roam

原生 SwiftUI 旅行规划 App，支持 iPhone 和 Mac（Mac Catalyst）。

## 功能

- 旅行首页、自适应卡片、长按拖动排序与搜索。
- 全程表格和按天查看，行程、交通、餐饮、住宿与备注。
- 地点搜索、多地点选择、地图路线与路线顺序调整。
- 自选封面：相册或图片文件，自动缩放压缩。
- 同一 iCloud 账户的私人数据库同步，离线保存及冲突副本。

## 项目

- `iOS/Roam.xcodeproj`：iPhone 工程。
- `macOS/Roam.xcodeproj`：Mac Catalyst 工程。
- 每个工程包含模型测试和 UI 测试。

使用 Xcode 27.1 打开工程，选择 `Roam` scheme 和对应运行设备。部署版本以工程设置为准（当前为 26.0）。

## iCloud 与签名

两端使用同一 CloudKit 私有容器 `iCloud.com.xiangchengjin.roam`。照片随行程 payload 作为 CKAsset 同步，应用也保留本机副本。仓库不包含实际私人行程、上传照片、开发证书或描述文件。

换开发团队时，请在 Signing & Capabilities 设置自己的团队和 Bundle ID，并为两个 App ID 关联同一容器；同步修改 `CloudSync.swift` 与 `Roam.entitlements` 的容器名。CloudKit 记录类型为 `RoamLibrary`，字段 `payload` 为 Asset。

当前安装测试使用 Development 环境；正式分发前需要部署生产 schema，并使用相应的分发签名。地图中的虚线是地点顺序示意，App 内道路计算支持步行和驾车；公共交通请在苹果地图查看。

## 验证

最近验证包括：两端构建通过，14 项模型测试通过；照片压缩、云端数据编码往返及无效图片测试通过；Mac 编辑、保存、重启持久化 UI 测试通过。Mac 私有云上传读取已实测。照片跨实体设备同步尚未独立验收。

UI 测试使用 `--uitesting` 的独立数据文件，不能对正常行程数据使用 `--reset`。
