# 测试Token说明

## 如何使用测试页面

1. 打开 `test-api.html` 文件在浏览器中
2. 在页面顶部的 **API配置** 部分可以：
   - 修改API地址
   - 输入不同的Token
   - 点击"更新配置"应用新的设置
   - 点击"保存Token"将当前Token保存到列表
   - 使用下拉菜单快速切换已保存的Token

## 功能特性

### Token管理
- **动态切换**：可以随时更改Token，无需刷新页面
- **本地存储**：Token会保存在浏览器的localStorage中
- **快速切换**：保存多个Token后可以快速切换测试
- **清除功能**：可以一键清除所有保存的Token

### 测试功能
- **健康检查**：验证API是否正常运行
- **创建Pod**：为当前Token对应的用户创建VNC Pod
- **查看列表**：查看用户的所有Pod
- **Pod操作**：停止、重启、删除Pod
- **更新配置**：修改Pod的CPU、内存配置

## 测试步骤

### 1. 基础测试
```
1. 输入有效的Token
2. 点击"更新配置"
3. 点击"检查API健康状态"验证连接
4. 如果显示"API运行正常"，说明Token有效
```

### 2. 创建Pod测试
```
1. 在"创建VNC Pod"部分选择配置：
   - CPU: 1-4核
   - 内存: 2-8Gi
   - 存储: 10-50Gi
2. 点击"创建Pod"
3. 等待Pod创建完成
4. 记录返回的VNC密码
```

### 3. 访问VNC
```
1. Pod创建成功后，访问URL格式：
   http://vnc.service.thinkgs.cn:31290/user/{user_id}/vnc.html
   
2. 其中user_id是Token对应的用户ID
3. 使用创建时返回的VNC密码登录
```

### 4. 多用户测试
```
1. 输入不同用户的Token
2. 点击"更新配置"
3. 为每个用户创建独立的Pod
4. 验证各用户的Pod相互隔离
```

## 注意事项

1. **Token格式**：必须以 `sk-` 开头
2. **用户隔离**：每个Token对应的用户只能管理自己的Pod
3. **资源限制**：每个用户同时只能有一个Pod
4. **访问端口**：由于使用NodePort，需要使用31290端口访问

## 故障排查

### Token无效
- 错误信息：401 Unauthorized
- 解决：确认Token在数据库中存在且未被禁用

### Pod创建失败
- 检查集群资源是否充足
- 查看Pod事件：`kubectl describe pod <pod-name> -n vnc-pods`

### 无法访问VNC
- 确认DNS解析正确
- 使用NodePort端口31290
- 检查Pod是否Running状态

## 数据库查询Token

如果需要查询可用的Token，可以连接数据库：
```sql
SELECT id, user_name, nick_name, token_key 
FROM im_platform.im_user 
WHERE token_key IS NOT NULL 
  AND token_key != '' 
  AND is_banned = 0;
```

当前已知的测试Token：
- `sk-njHDNMrSaVZH0MNQFd8607F6E52d4a5386Aa88A68f5583A1` (用户ID: 17)