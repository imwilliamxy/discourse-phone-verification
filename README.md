# Discourse Phone Verification Plugin (`uscardforum-phone-verification`)

Discourse 手机号验证插件，支持美国（+1）手机号短信验证码绑定、隐私脱敏、信任等级（Trust Level）联动以及板块准入自动用户组同步。

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
3. **多重限制与用户组联动**：
   - **基础同步**：插件内置轻量级加组服务，支持将满足条件的用户自动同步至 `phone_verified` 用户组。
   - **动态规则（推荐）**：与 [discourse-dynamic-groups](https://github.com/communiteq/discourse-dynamic-groups) 深度配合，支持通过灵活的 SQL 规则构建诸如「Trust Level X 且已验证手机号」的复合限制策略。
   - **原生板块权限**：管理员通过 Discourse 原生 `Category -> Security` 权限为用户组分配 `See / Reply / Create` 访问控制。
4. **防接码小号与虚拟号码 (VoIP) 拦截**：
   - **一次性接码号拦截 (Disposable)**：内置开源接码数据库（基于 `iP1SMS/disposable-phone-numbers` 每日同步至 Redis Set）与自定义黑名单，以 $O(1)$ 速度在短信发送前直接拦截廉价接码平台号码，零 API 费用。
   - **虚拟运营商 (VoIP) 与固定电话拦截**：支持通过 Twilio Lookup v2 或 AWS Pinpoint 实时检测号码运营商线路类型（Line Type），仅放行实体移动卡（`mobile` / `prepaid`），拦截 Google Voice、TextNow、Skype 等虚拟号，并对查询结果进行 Redis 长期缓存（默认 30 天）以严格控制 API 成本。
5. **可扩展 SMS Provider 架构**：
   - 抽象通用短信适配器接口，已实现 **AWS SNS** 与 **Twilio**，并支持灵活扩展。

---

## 2. 前置依赖与安装指南 (Installation)

### ⚠️ 前置依赖声明 (Prerequisites)
如需实现 **“Trust Level X 且 Phone Verified”** 等复合条件限制，建议在安装本插件的同时安装 [discourse-dynamic-groups](https://github.com/communiteq/discourse-dynamic-groups) 插件。

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
          # 2. 手机号验证插件
          - git clone https://github.com/uscardforum/uscardforum-phone-verification.git
```

添加后，在 `/var/discourse` 目录下重新构建容器：
```bash
./launcher rebuild app
```

---

## 3. 插件配置与站点设置 (Site Settings)

进入 Discourse 管理员后台，搜索 `phone_verification` 配置项：

| 设置项 | 默认值 | 说明 |
| :--- | :--- | :--- |
| `phone_verification_enabled` | `false` | 启用/禁用手机号验证插件 |
| `phone_verification_min_trust_level` | `1` | 验证手机号用户所需的最低信任等级 (0 ~ 4) |
| `phone_verification_group_name` | `phone_verified` | 内置同步的目标用户组名称 |
| `phone_verification_sms_provider` | `aws_sns` | 短信网关服务商驱动（`aws_sns` 或 `twilio`） |
| `phone_verification_aws_region` | `us-east-1` | AWS SNS 服务所在 Region |
| `phone_verification_aws_access_key_id` | `""` | AWS Access Key ID（留空使用 IAM 角色） |
| `phone_verification_aws_secret_access_key` | `""` | AWS Secret Access Key |
| `phone_verification_sms_sender_id` | `""` | 可选 AWS 短信 Sender ID（支持的国家/地区有效） |
| `phone_verification_twilio_account_sid` | `""` | Twilio Account SID |
| `phone_verification_twilio_auth_token` | `""` | Twilio Auth Token |
| `phone_verification_twilio_from_phone_number` | `""` | Twilio 发送方电话号码（E.164 格式，如 `+14155552671`） |
| `phone_verification_twilio_messaging_service_sid` | `""` | 可选 Twilio Messaging Service SID（`MG...`） |
| `phone_verification_sms_daily_limit_per_user` | `5` | 单用户每日允许发送验证码最大次数 |
| `phone_verification_verification_code_expiry_minutes` | `10` | 验证码有效时长（分钟） |
| `phone_verification_debug_mode` | `false` | 调试模式开关（开启后跳过真实短信发送与单日发送限制，任意 6 位数字均可通过） |
| `phone_verification_block_disposable` | `true` | 启用一次性接码平台手机号拦截 |
| `phone_verification_disposable_list_url` | jsDelivr URL | 开源一次性接码号段数据源 URL (iP1SMS) |
| `phone_verification_custom_disposable_numbers` | `""` | 管理员自定义黑名单手机号列表（`\|` 分隔） |
| `phone_verification_block_voip` | `false` | 启用虚拟运营商 (VoIP) 及固定电话拦截 |
| `phone_verification_lookup_cache_ttl_days` | `30` | 线路类型查询结果在 Redis 中的缓存保留天数 |

---

## 4. 配合 discourse-dynamic-groups 配置板块限制 (Best Practice)

Discourse 原生的板块权限（Category Security）在多个组之间采用 **OR（满足任一即可）** 逻辑。为了实现 **“Trust Level 2 且 手机号已验证”** 的复合限制，推荐通过动态组进行组合：

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

## 5. 内置用户组自动创建与生命周期管理 (Automatic Group Lifecycle)

插件内置了目标用户组的自动保障与同步机制：

### 5.1 自动创建机制
- **触发时机**：当在管理后台启用插件（`phone_verification_enabled = true`）或修改插件相关设置（如最低信任等级、组名称）并保存时，Discourse 会触发 `site_setting_changed` 事件。
- **自动初始化**：插件会自动检查数据库中是否存在名为 `phone_verification_group_name`（默认 `phone_verified`）的用户组；若不存在（例如在全新环境或重置数据库后），插件会自动调用 `Group.create!` 创建该用户组。

### 5.2 默认安全属性
- **仅员工可见 (`visibility_level: staff`)**：普通用户无法在用户组列表查看谁验证了手机号，保护用户隐私。
- **禁止自行申请 (`public_admission: false`)**：不允许用户手动申请加入，完全由插件自动化业务逻辑托管。
- **非主用户组 (`primary_group: false`)**：不覆盖用户的原生主用户组头衔或徽章展示。

### 5.3 自动化成员同步
- **自动加入**：当用户完成手机号短信验证，且当前信任等级达到设定门槛（`Trust Level >= phone_verification_min_trust_level`）且账号未被封禁时，插件自动将其加入该组。
- **自动移出**：当用户**主动解绑手机号**、**账号被封禁 (Suspended)** 或**信任等级下降**至门槛以下时，插件会自动将其从该组移除。

---

## 6. 本地开发、环境重置与测试 (Development, Reset & Testing)

在 Discourse 官方 Docker 开发环境（`discourse/discourse_dev`）下，插件代码通过挂载 `/src/plugins` 目录实时生效。

### 6.1 清理历史数据与全新初始化启动（Clean Slate）
若需要彻底清理旧数据库和缓存数据并重新启动：

```bash
cd /path/to/discourse

# 1. 停止并删除现有的开发容器
./bin/docker/shutdown_dev

# 2. 清空 PostgreSQL 本地持久化数据
rm -rf data/postgres/*

# 3. 重新启动容器并执行初始化（自动创建数据库、主工程迁移并创建管理员）
./bin/docker/boot_dev --init
```

> 💡 **快速重置数据库（保留容器）**：
> 若无需删除容器，可直接执行 `./bin/docker/reset_db`。

### 6.2 插件加载与迁移
1. **自动加载**：只要插件目录位于 `plugins/uscardforum-phone-verification`，容器启动时便会自动加载。
2. **执行数据库迁移**：
   ```bash
   ./bin/docker/rake db:migrate
   ```
3. **创建/重设管理员账号**：
   ```bash
   ./bin/docker/rake admin:create
   ```

### 6.3 启动开发服务器
```bash
./bin/docker/dev
```
- 访问：`http://localhost:3000`
- 登录管理员后前往 `Admin -> Settings -> Plugins` 启用 `phone_verification_enabled`。

### 6.4 运行测试与代码检查
```bash
# 运行插件全部 RSpec 测试套件
LOAD_PLUGINS=1 ./bin/docker/rspec plugins/uscardforum-phone-verification/spec

# 运行前端 Lint 检查
./bin/docker/exec bin/lint plugins/uscardforum-phone-verification
```

---

## 7. 详细技术规范
完整的架构设计、数据库表结构、API 契约及实施规范请参阅：
👉 [DESIGN.md](./DESIGN.md)

