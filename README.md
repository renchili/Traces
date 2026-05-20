# Traces

Traces 是一个 macOS SwiftUI 应用，用于把 Google Timeline / Google Maps 时间轴导出的 JSON 数据转换成可预览、可筛选、可导出的日历事件。

它的目标不是做统计报表，而是把日常轨迹整理成可以导入 Apple Calendar 或其他日历应用的 `.ics` 文件。

## 核心功能

- 打开 Google Timeline JSON
- 提取停留事件
- 过滤停留时间过短的记录
- 过滤长时间 Home 停留
- 自动合并同一地点或相近时间段的连续停留
- 使用 Google placeID 解析真实地点名称
- 本地缓存地点解析结果，避免重复调用 Google API
- 支持打开 `.ics` 文件进行本地预览
- 支持导出 `.ics`
- 支持重启后恢复上次预览内容
- 支持搜索事件标题、地点、描述

## 当前定位

Traces 当前主要解决这个问题：

```text
Google Timeline JSON
    ↓
提取 visit / placeID / 坐标
    ↓
地点解析与缓存
    ↓
合并停留事件
    ↓
生成可预览的日历事件
    ↓
导出 ICS
```

## 为什么需要 Traces

Google Timeline 数据里通常会包含 `placeID`、坐标、开始时间、结束时间、语义类型，例如 `Home`、`Unknown`、`Aliased Location`。

但这些数据不能直接导入日历。Traces 会把这些 Timeline 记录整理成更像真实行程的事件，例如：

```text
Waterway Point
5 May 2026 14:34 → 5 May 2026 20:38
```

并生成标准 `.ics` 文件。

## 地点解析逻辑

Traces 不使用硬编码半径表猜测地点。

正确解析流程是：

```text
placeID / 坐标
    ↓
本地缓存查询
    ↓
Google Places / Geocoding API 查询
    ↓
成功后写入本地缓存
    ↓
生成事件标题和地点信息
```

## 缓存优先

每次导入 Timeline JSON 时，Traces 会先提取所有唯一地点：

```text
placeID:ChIJxxxx
coord:1.40936,103.90078
```

然后先查内存缓存，再查本地持久缓存。只有缓存未命中时才调用 Google API。API 成功后写入本地缓存，后续历史数据不再重复解析。

## Google API 使用说明

如果需要真实地点名，需要配置 Google API Key。

建议启用：

```text
Places API
Places API (New)
Geocoding API
```

当前解析顺序：

```text
Places API New
    ↓
Places API Legacy
    ↓
Geocoding by place_id
    ↓
Geocoding by lat,lng
    ↓
坐标 / placeID fallback
```

如果不填写 API Key，Traces 仍然可以工作，但地点会显示为坐标或 Place ID fallback。

例如：

```text
Location 1.409361,103.900785
```

或者：

```text
Place ID: ChIJ...
```

## 费用说明

Google Places / Geocoding API 不是完全免费。因此 Traces 采用本地缓存策略：

```text
同一个 placeID 成功解析一次后，本地长期复用
```

对于个人使用，这通常可以显著减少 API 调用次数。

如果未来发布正式 App，不建议在客户端内置 Google API Key。更合理的架构是：

```text
macOS App
    ↓
你的后端 API
    ↓
全局缓存 / 限流 / 配额控制
    ↓
Google Places / Geocoding API
```

## 数据处理逻辑

### 1. 解析 Timeline JSON

从 Google Timeline JSON 中提取：

- `startTime`
- `endTime`
- `visit`
- `topCandidate`
- `placeID`
- `placeLocation`
- `semanticType`

### 2. 停留过滤

默认配置：

```text
最近 14 天
最小停留 15 分钟
Home 停留超过 60 分钟过滤
```

这些参数可以在设置面板中调整。

### 3. 地点解析

对于每个唯一地点：

```text
placeID 优先
没有 placeID 时使用坐标
```

成功解析后生成：

- `title`
- `subtitle`
- `url`
- `mergeKey`
- `source`
- `confidence`
- `debugMessage`

### 4. 事件合并

事件会基于以下条件合并：

```text
同一个 mergeKey
或坐标距离足够近
并且时间重叠或间隔较短
```

默认合并参数：

```text
localMergeGapMinutes = 30
localMergeDistanceMeters = 250
```

### 5. 生成 ICS

最终事件会转换为标准 iCalendar 格式：

```text
BEGIN:VCALENDAR
BEGIN:VEVENT
SUMMARY:
LOCATION:
DESCRIPTION:
URL:
DTSTART:
DTEND:
END:VEVENT
END:VCALENDAR
```

## 当前文件结构

```text
Traces
├── Models.swift
├── LocationCacheStore.swift
├── GoogleLocationResolver.swift
├── TimelineProcessor.swift
├── ICSCodec.swift
├── ContentView.swift
├── TimelineGeneratorSettingsView.swift
├── EventViews.swift
└── Preview.swift
```

## 文件职责

### `Models.swift`

定义核心数据结构：

- `ICSEvent`
- `TimelineEntry`
- `TimelineVisit`
- `TimelineCandidate`
- `TimelineOptions`
- `ResolvedLocation`
- `LocationResolveRequest`

### `LocationCacheStore.swift`

负责地点解析结果的本地持久化缓存。

缓存内容：

```text
placeID / coord key -> ResolvedLocation
```

### `GoogleLocationResolver.swift`

负责地点解析。

解析顺序：

```text
本地缓存
Google Places API New
Google Places API Legacy
Google Geocoding by place_id
Google Geocoding by lat,lng
fallback
```

### `TimelineProcessor.swift`

负责 Timeline JSON 的业务处理：

- 解析 visit
- 过滤停留
- 提取唯一地点
- 调用 resolver 批量解析
- 合并事件
- 生成 `ICSEvent`

### `ICSCodec.swift`

负责：

- 生成 `.ics`
- 解析 `.ics`
- 处理 ICS 字段转义
- 处理 ICS line folding

### `ContentView.swift`

主界面：

- 打开 JSON / ICS
- 触发生成
- 搜索事件
- 导出 ICS
- 恢复上次会话
- 清理会话

### `TimelineGeneratorSettingsView.swift`

设置面板：

- Google API Key
- 最近天数
- 最小停留时间
- Home 过滤时间
- 地点缓存状态
- 清空缓存

### `EventViews.swift`

事件列表和事件详情视图。

## 使用方式

### 1. 打开 App

运行 Traces。

### 2. 配置 Google API Key

点击设置按钮，填入 Google API Key。

如果不配置，也可以使用坐标 fallback 模式。

### 3. 打开 Timeline JSON

点击：

```text
Open → Open Timeline JSON & Generate
```

选择 Google Timeline JSON 文件。

### 4. 预览事件

左侧显示事件列表。右侧显示事件详情。

可以搜索：

```text
title
location
description
```

### 5. 导出 ICS

点击：

```text
Export ICS
```

导出 `.ics` 文件，然后可以导入 Apple Calendar。

## 本地缓存

Traces 会缓存成功解析的地点。

缓存命中时，不会再次调用 Google API。

设置面板中可以看到：

```text
Location Cache
N cached places
```

也可以点击：

```text
Clear Cache
```

清空地点缓存。

## 会话恢复

Traces 会保存上次预览状态：

- 上次生成的事件
- 上次选中的事件
- 上次生成的 ICS 内容
- 上次文件名
- 设置项

重启 App 后会自动恢复。

## 注意事项

### API Key 安全

当前开发版本使用 `@AppStorage` 保存 Google API Key，适合本地测试。

正式发布时不建议这样做。

发布版建议：

```text
Keychain
或后端代理
```

### 发布版建议架构

如果要发布给其他用户，推荐：

```text
App
    ↓
后端 resolver API
    ↓
后端全局缓存
    ↓
Google API
```

不要把 Google API Key 直接放进客户端。

### App Sandbox 网络权限

如果 API 请求报错：

```text
A server with the specified hostname could not be found
```

或者无法访问 Google API，请检查：

```text
Target
→ Signing & Capabilities
→ App Sandbox
→ Network
→ Outgoing Connections (Client)
```

需要勾选。

## Debug 信息

事件详情中会显示 resolver 信息：

```text
Resolver source
Resolver confidence
Resolver debug
Google Maps URL
```

常见 source：

```text
google_places_new
google_places_legacy
google_geocode_place_id
google_reverse_geocode_latlng
place_id_fallback
coordinate_fallback
google_places_new_local_cache
google_places_new_memory_cache
```

如果看到：

```text
place_id_fallback
```

说明地点名没有成功解析，通常是：

- API Key 未填
- API 未启用
- Billing 未启用
- Key 限制错误
- DNS / 网络问题
- Sandbox 未开启外网权限

## Roadmap

后续可以继续增强：

- Keychain 保存 API Key
- 后端解析模式
- 手动地点 alias
- 批量刷新缺失地点
- 只解析新 placeID
- 可视化展示缓存命中率
- 支持导入 Google Takeout ZIP
- 支持按日期导出多个 ICS
- 支持 Apple Calendar 事件去重
- 支持自定义合并规则
- 支持地点黑名单 / 白名单
