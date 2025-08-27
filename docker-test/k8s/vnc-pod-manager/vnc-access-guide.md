# VNC访问指南

## 访问URL格式

### 方式1：使用vnc.html带参数（推荐）
```
http://vnc.service.thinkgs.cn:31290/user/{user_id}/vnc.html?path=user/{user_id}/websockify
```

例如用户17：
```
http://vnc.service.thinkgs.cn:31290/user/17/vnc.html?path=user/17/websockify
```

### 方式2：使用vnc_lite.html（简化版）
```
http://vnc.service.thinkgs.cn:31290/user/{user_id}/vnc_lite.html?path=user/{user_id}/websockify
```

### 方式3：自动连接URL
```
http://vnc.service.thinkgs.cn:31290/user/{user_id}/vnc.html?autoconnect=true&path=user/{user_id}/websockify&password={vnc_password}
```

## WebSocket路径说明

由于我们使用了路径重写，WebSocket连接需要特别处理：

1. **页面访问路径**：`/user/17/vnc.html`
2. **WebSocket路径**：`/user/17/websockify` 
3. **实际后端路径**：通过Ingress重写为 `/websockify`

## 常见问题

### Q: 为什么WebSocket连接失败？
A: noVNC默认使用相对路径 `websockify`，但在我们的Ingress配置下需要完整路径。使用URL参数 `?path=user/17/websockify` 可以解决。

### Q: 如何自动连接？
A: 添加URL参数：
- `autoconnect=true` - 自动连接
- `password=xxx` - 自动填充密码
- `path=user/17/websockify` - 指定WebSocket路径

### Q: 端口为什么是31290？
A: Kubernetes Ingress Controller使用NodePort类型，31290是分配的节点端口。

## 完整示例

用户17的完整访问URL（自动连接）：
```
http://vnc.service.thinkgs.cn:31290/user/17/vnc.html?autoconnect=true&path=user/17/websockify&password=kFOn7Dki
```

## 测试步骤

1. 获取Pod信息和VNC密码
2. 构造访问URL（注意添加path参数）
3. 在浏览器中打开URL
4. 如果没有使用autoconnect，手动点击"Connect"
5. 输入VNC密码

## 技术细节

### Ingress路径处理
- 匹配：`/user/17/websockify(/|$)(.*)`
- 重写：`/$2`
- 结果：`/user/17/websockify` → `/websockify`

### noVNC配置
- 默认WebSocket路径：`websockify`（相对路径）
- 需要通过URL参数覆盖为：`user/17/websockify`
- 这样完整的WebSocket URL为：`ws://vnc.service.thinkgs.cn:31290/user/17/websockify`