# Discourse Phone Gatekeeper Plugin (`uscardforum-phone-gatekeeper`)

Discourse 手机号门禁插件，支持美国（+1）手机号短信验证码绑定、隐私脱敏、信任等级（Trust Level）联动以及板块准入自动用户组同步。

---

## 1. 核心需求与设计目标

1. **美国 (+1) 手机号短信验证**：
   - 用户在个人偏好设置（Preferences）中输入美国手机号并接收短信验证码进行绑定。
   - 严格 1:1 绑定：单个手机号在同一时间只能被一个激活用户绑定；如需更换号码，必须由用户主动发起解绑后再重新绑定。
2. **隐私与安全保护**：
   - 手机号不对外公开展示。
   - 个人偏好设置页面中对本人脱敏显示（如 `+1 (***) ***-1234`）。
   - 仅管理员 / Staff 在管理后台可见完整手机号。
   - 短信防刷：单用户 60 秒发送冷却、每日发送次数上限、验证码有效期（10分钟）、最大重试错误次数（5次）。
3. **板块准入与用户组联动（Gatekeeper Engine）**：
   - 满足「指定最低 Trust Level」+「已完成美国手机号验证」的用户，自动加入指定的门禁用户组（如 `phone_verified`）。
   - 条件失效（解绑手机号、用户降级、封禁）时，自动移出该用户组。
   - 管理员通过 Discourse 原生 Category Security 权限直接为该组分配一个或多个板块的访问/发帖权限。
4. **可扩展 SMS Provider 架构**：
   - 抽象通用短信适配器接口，首发实现 **AWS SNS**，并支持配置 AWS IAM / Access Key。

---

## 2. 详细技术规范与设计文档

完整的架构设计、数据库表结构、API 契约及实施规范请参阅：
👉 [DESIGN.md](./DESIGN.md)

---

## 3. 快速安装与配置（开发计划）

### 插件启用与配置
在 Discourse 管理员后台搜索 `phone_gatekeeper` 相关 Site Settings：
- `phone_gatekeeper_enabled`：启用/禁用插件。
- `phone_gatekeeper_min_trust_level`：准入所需的最低信任等级（0 ~ 4）。
- `phone_gatekeeper_group_name`：绑定的目标用户组标识（默认 `phone_verified`）。
- `phone_gatekeeper_sms_provider`：短信服务商（默认 `aws_sns`）。
- `phone_gatekeeper_aws_region` / `phone_gatekeeper_aws_access_key_id` / `phone_gatekeeper_aws_secret_access_key`：AWS SNS 凭据与区域。

### 板块权限配置
1. 插件激活后会自动确保 `phone_verified` 用户组存在。
2. 前往 `Admin -> Categories -> [目标板块] -> Security`。
3. 添加 `phone_verified` 用户组，并为其授予 `See / Reply / Create` 权限即可完成板块门禁准入控制。
