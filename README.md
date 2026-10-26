# 漫屿

面向 HarmonyOS 的原生多书源漫画阅读器。

## 功能

- **书架**：作品归一、来源关联、分类、筛选、排序、批量管理与精确续读。
- **更新**：检查书架作品的新章节，查看最近阅读与下载任务。
- **书源**：内置在线书源，连接 Suwayomi 服务，导入本地 CBZ、ZIP 或图片。各书源独立启停、浏览和设置。
- **搜索与换源**：按书源分组搜索；作品信息充分一致时自动关联，有歧义时手动确认。目标章节可以明确匹配时支持阅读失败自动换源，章节页数不同时按比例定位。
- **阅读**：连续纵向、纵向翻页、从左向右、从右向左与双页阅读；支持封面偏移、宽图单页、裁白边、护眼遮罩、九宫格点按、书签与每本漫画独立偏好。
- **离线**：下载完整漫画后在应用内阅读，并可导出 CBZ。下载完成后，即使停用对应书源，也可继续离线阅读。
- **外观与数据**：浅色、深色和跟随系统；手机悬浮底栏、大屏侧边导航；本地阅读统计和备份恢复。

## 使用书源

在“书源”中打开浏览入口，或输入漫画编号直达作品。镜像切换、镜像测速和屏蔽标签位于该书源的“设置”中。

添加 Suwayomi 时填写服务地址，按服务端配置选择无需认证、基础认证或账号登录。漫屿连接一个 Suwayomi 服务，服务下的多个扩展分别参与检索；重新连接会同步现有扩展。服务端需先安装所需扩展。书架、阅读进度与下载由漫屿本地管理。认证失效后，请进入该书源设置重新连接。

本地导入支持单个 CBZ、ZIP，或同一本漫画的多张图片。文件按自然顺序排列，压缩包内的图片文件夹作为章节；存在 `ComicInfo.xml` 时读取作品名和作者。导入后读取应用内保存的副本。

## 备份

在“我的”中导出或恢复漫屿备份。当前使用 v3 格式，包含书架、书源连接配置、阅读记录、书签、漫画阅读偏好及统计，不包含认证凭据、漫画文件或下载文件。恢复将整体替换对应记录并立即生效；需要认证的书源须重新连接，本地漫画须重新导入。旧版备份不支持导入。

## 开发与构建

工程使用 HarmonyOS 26.0.0 SDK（API 26），由 DevEco Studio 打开根目录后同步和构建。界面设计参考 [LuminaManga 设计规格](docs/material/LuminaManga_HarmonyOS_UIUX_Design_Specification.docx)。

主要代码位于 `entry/src/main/ets/`：

- `data/Sources.ets`、`SourceApi.ets`、`Suwayomi.ets`、`LocalSource.ets`：书源身份、统一访问与来源实现。
- `data/Library.ets`、`SourceSwitch.ets`、`OfflineStore.ets`：作品关联、换源与离线内容。
- `pages/MainShell.ets`、`LibraryPage.ets`、`UpdatesPage.ets`、`SourcesPage.ets`、`ProfilePage.ets`：主导航与四个主页。
- `pages/SearchAllPage.ets`、`WorkDetailPage.ets`、`ReaderPage.ets`、`DownloadsPage.ets`：搜索、详情、阅读和下载。

使用 DevEco 命令行工具构建：

```powershell
$env:DEVECO_CLI_STUDIO_PATH = 'D:\Program Files\DevEco Studio'
devecocli build
```

默认产物为 `entry/build/default/outputs/default/entry-default-unsigned.hap`。工程未配置签名；安装运行前，需在 DevEco Studio 的 Signing Configs 中配置调试或发行签名。

核心逻辑回归检查使用 DevEco 自带的 Node.js 与 TypeScript，无须安装额外依赖。请按本机安装目录调整路径：

```powershell
& 'D:\Program Files\DevEco Studio\tools\node\node.exe' scripts/check-core.mjs 'D:\Program Files\DevEco Studio\sdk\default\openharmony\ets\build-tools\ets-loader\node_modules\typescript'
```

## 许可与致谢

沿用 [相关开源参考](https://github.com/jinmanji/jinmanji-app) 的协议访问与图片还原实现，遵循原项目 GNU GPL-3.0 许可。相关算法知识同时致谢原项目列出的社区项目。

本项目为非官方第三方客户端。请遵守内容来源的使用条款及适用法律。
