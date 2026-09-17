# Discourse Phone Gatekeeper Plugin (`uscardforum-phone-gatekeeper`)

Discourse 手机号门禁插件，支持美国（+1）手机号短信验证码绑定、隐私脱敏、信任等级（Trust Level）联动以及板块准入自动用户组同步。

---

## 1. 核心需求与设计目标

1. **美国 (+1) 手机号短信验证**：
   - 用户在个人偏好设置（Preferences -> Account）中输入美国手机号并接收短信验证码进行绑定。
   - 严格 1:1 绑定：单个手机号在同一时间只能被一个激活用户绑定；如需更换号码，必须由用户主动发起解绑后再重新绑定。
2. **隐私与安全保护**：
   - 手机号不对外公开展示。
   - 个人偏好设置页面中对本人脱敏显示（如 `+1 (***) ***-1234`）。
   - 仅管理员 / Staff 在管理后台（Admin -> Users -> 详情页）可见完整手机号。
   - 短信防刷：单用户 60 秒发送冷却、每日发送次数上限、验证码有效期（10分钟）、最大重试错误次数（5次）。
3. **复合门禁与用户组联动**：
   - **基础同步**：插件内置轻量级加组服务，支持将满足条件的用户自动同步至 `phone_verified` 用户组。
   - **动态规则（推荐）**：与 [discourse-dynamic-groups](https://github.com/communiteq/discourse-dynamic-groups) 深度配合，支持通过灵活的 SQL 规则构建诸如「Trust Level X 且已验证手机号」的复合门禁组。
   - **原生板块权限**：管理员通过 Discourse 原生 `Category -> Security` 权限为门禁组分配 `See / Reply / Create` 访问控制。
4. **可扩展 SMS Provider 架构**：
   - 抽象通用短信适配器接口，首发实现 **AWS SNS**，并支持配置 AWS IAM Role / Access Key。

---

## 2. 前置依赖与安装指南 (Installation)

### ⚠️ 前置依赖声明 (Prerequisites)
如需实现 **“Trust Level X 且 Phone Verified”** 等复合条件门禁，建议在安装本插件的同时安装 [discourse-dynamic-groups](https://github.com/communiteq/discourse-dynamic-groups) 插件。

若启用插件后未检测到 `discourse-dynamic-groups`，Discourse 管理员后台仪表盘（Dashboard）会自动提示问题警告。

### 安装步骤（Docker 部署）
编辑服务器上的 `containers/app.yml`（或对应容器配置文件），在 `hooks.after_code` 中添加两个插件的 Git 仓库：

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          # 1. 动态用户组插件（推荐先引入）
          - git clone https://github.com/communiteq/discourse-dynamic-groups.git
          # 2. 手机号验证门禁插件
          - git clone https://github.com/uscardforum/uscardforum-phone-gatekeeper.git
```

添加后，在 `/var/discourse` 目录下重新构建容器：
```bash
./launcher rebuild app
```

---

## 3. 插件配置与站点设置 (Site Settings)

进入 Discourse 管理员后台，搜索 `phone_gatekeeper` 配置项：

| 设置项 | 默认值 | 说明 |
| :--- | :--- | :--- |
| `phone_gatekeeper_enabled` | `false` | 启用/禁用手机号门禁插件 |
| `phone_gatekeeper_min_trust_level` | `1` | 内置门禁所需的最低信任等级 (0 ~ 4) |
| `phone_gatekeeper_group_name` | `phone_verified` | 内置同步的目标用户组名称 |
| `phone_gatekeeper_sms_provider` | `aws_sns` | 短信网关服务商驱动（`aws_sns` 或 `twilio`） |
| `phone_gatekeeper_aws_region` | `us-east-1` | AWS SNS 服务所在 Region |
| `phone_gatekeeper_aws_access_key_id` | `""` | AWS Access Key ID（留空使用 IAM 角色） |
| `phone_gatekeeper_aws_secret_access_key` | `""` | AWS Secret Access Key |
| `phone_gatekeeper_sms_sender_id` | `""` | 可选 AWS 短信 Sender ID（支持的国家/地区有效） |
| `phone_gatekeeper_twilio_account_sid` | `""` | Twilio Account SID |
| `phone_gatekeeper_twilio_auth_token` | `""` | Twilio Auth Token |
| `phone_gatekeeper_twilio_from_phone_number` | `""` | Twilio 发送方电话号码（E.164 格式，如 `+14155552671`） |
| `phone_gatekeeper_twilio_messaging_service_sid` | `""` | 可选 Twilio Messaging Service SID（`MG...`） |
| `phone_gatekeeper_sms_daily_limit_per_user` | `5` | 单用户每日允许发送验证码最大次数 |
| `phone_gatekeeper_verification_code_expiry_minutes` | `10` | 验证码有效时长（分钟） |
| `phone_gatekeeper_debug_mode` | `false` | 调试模式开关（开启后跳过真实短信发送与单日发送限制，任意 6 位数字均可通过） |

---

## 4. 配合 discourse-dynamic-groups 配置板块门禁 (Best Practice)

Discourse 原生的板块权限（Category Security）在多个组之间采用 **OR（满足任一即可）** 逻辑。为了实现 **“Trust Level 2 且 手机号已验证”** 的复合门禁，推荐通过动态组进行组合：

### 步骤 1：在后台创建动态用户组
进入 `Admin -> Groups -> New Dynamic Group`，配置动态规则：

#### 示例 A：所有已验证手机号的用户
```sql
SELECT user_id 
FROM user_phone_records 
WHERE active = TRUE
```

#### 示例 B：Trust Level >= 2 且 已验证手机号（未封禁）
```sql
SELECT u.id AS user_id
FROM users u
JOIN user_phone_records r ON r.user_id = u.id AND r.active = TRUE
WHERE u.trust_level >= 2
  AND u.active = TRUE
  AND NOT u.suspended
```

#### 示例 C：高门槛复合组（TL3 + 手机验证 + 注册满 30 天）
```sql
SELECT u.id AS user_id
FROM users u
JOIN user_phone_records r ON r.user_id = u.id AND r.active = TRUE
WHERE u.trust_level >= 3
  AND u.created_at <= NOW() - INTERVAL '30 days'
  AND u.active = TRUE
  AND NOT u.suspended
```

### 步骤 2：为目标板块设置权限 (Category Security)
1. 前往 `Admin -> Categories -> [目标板块] -> Security`。
2. 移除 `everyone` 组或降低其权限。
3. 添加刚刚创建的动态组（例如 `phone_verified_tl2`）。
4. 授予该动态组 `See / Reply / Create` 权限并保存。

---

## 5. 开发与测试

进入 Discourse 开发容器执行 RSpec 测试：
```bash
docker exec -u discourse discourse_dev bash -c "cd /src && LOAD_PLUGINS=1 bundle exec rspec plugins/uscardforum-phone-gatekeeper/spec"
```

---

## 6. 详细技术规范
完整的架构设计、数据库表结构、API 契约及实施规范请参阅：
👉 [DESIGN.md](./DESIGN.md)
