# 楼层追击 V1：僵尸真的会追上二楼（2026-10-28）

生存循环 V1 收尾后的第一件事。目标是让"上楼躲僵尸"不再是绝对安全：
玩家上二楼，楼下的僵尸要能沿着楼梯追上来，而且**不能隔着楼板砍人**。

---

## 1. 之前是什么状态

别墅（`villa_07`）本来就有二层：二楼地板 `upper_floor_main / _front / _back`、
一段斜着的楼梯楔形 `VillaStairWedge`、二楼床和二楼储物箱。玩家一直能靠物理走上去。

僵尸不行，原因有三层：

| 位置 | 问题 |
| --- | --- |
| `navigation.gd` | 只有一张 2D 网格，`path()` 返回的路点 y 恒为 0 |
| `zombie.gd` `sees_player()` | `absf(offset.y) > 2.0` 直接返回 false，注释写着 "Planar AI cannot attack a different floor" |
| `zombie.gd` `tick()` | `record.target` 存的是 `[x, 0, z]`，高度信息在写入时就丢了 |

还有两个连带问题，是这次才查出来的：

- **二楼地板把一楼封死了**。`upper_floor_main` 是一块 11.1 × 9.0 × 0.2 的碰撞体，
  顶面 3.56 m > 0.3 m 的入图阈值，于是被当成障碍盖进那张唯一的平面网格。
  别墅一楼整片变成不可走——这正是 `docs/survival-loop-v1.md` 里记的
  "别墅厨房柜在实机里永远打不开"的真正原因（不是净空余量，是天花板进了导航）。
- **隔层伤害**。攻击判定用的是平面距离 `Vector2(dx, dz).length()`。
  玩家在二楼床边、僵尸在一楼正下方，平面距离 0.4 m < 攻击距离 1.15 m，
  僵尸隔着楼板就能砍。

## 2. 多层导航

`navigation.gd` 从"一张网格"改成"每层一张网格"：

- 碰撞源入图时带上 `min_y` / `max_y`（`game.gd box()`、`integrated_world.gd _collider_box()`）；
- `connected_world.json` 的 `navigation.floors` 声明层带：

  | 层 | y 范围 | 地面高度 |
  | --- | --- | --- |
  | 0 | -1.0 ~ 3.0 | 0.0 |
  | 1 | 3.0 ~ 6.9 | 3.56 |

- 一个碰撞源只挡它**垂直重叠**的层；
- **薄板（厚度 ≤ 0.35 m）算这一层的地面，不算障碍**。二楼地板因此只在第 1 层
  作为"可走高度"存在，一楼不再被它盖住；
- 没有 `floors` 配置时（老街区 `rules.json`）退化成单层，行为与改动前完全一致。

顺带的效果：一楼东南角的柜子/冰箱/衣柜前重新出现可站格（0.32 ~ 0.96 m），
别墅不再是"进得去、摸不到"。

## 3. 跨层路径

`navigation.path(from, to)` 先按 y 判断起止层：

- 同层 → 和以前一样一次 A*；
- 跨层 → 找 `navigation.stairs` 里连这两层的楼梯，拆成
  **本层 A\* 到楼梯脚 → 斜梯段 → 目标层 A\* 到终点**，三段拼成一条路点序列。
  一次跨层只花一个 A\* 预算名额，不会把别的僵尸饿死。

楼梯配置（`connected_world.json`）：

```json
{"id": "villa_stairs", "from": 0, "to": 1, "building": "villa_07",
 "bottom": [111.35, -18.6], "top": [110.4, -23.1]}
```

`bottom` 是**地面层可站的接驳点**（楼梯侧面那块空地），`top` 是二楼楼梯口。
斜梯段在两点之间线性插 4 个路点，y 从 0 走到 3.56。

## 4. 僵尸怎么上楼

一段 3.56 m 高、32° 的斜面，靠 `move_and_collide` 走不上去：重力把它压向斜面，
楔形东侧还是垂直面，僵尸会贴在侧壁上抖。试过"给正向 y 速度"，结果是
在斜面上来回滑（y 在 0.16 ~ 0.75 之间震荡）。

最终做法是**把爬楼当成一次直连位移**：

```gdscript
if toward.y > 0.5:            # follow_path：发现这一段是爬升
    var top := route_index    # 一路找到攀升段最后一个点
    while top + 1 < route.size() and route[top + 1].y > route[top].y + 0.1:
        top += 1
    climb_point = route[top]
    route_index = top
    return Vector3.ZERO
```

`tick()` 开头若有 `climb_point`，就直接 `position.move_toward(climb_point, climb_speed * delta)`，
跳过碰撞与分离，到位后清空。

两个细节是必须的，否则会出现"在楼梯上抽搐"：

1. **整段一次爬完**，不在每个斜坡采样点停；否则每次重规划都会把 actor 拉回梯脚；
2. 爬升期间 `tick()` 提前 return，不进 `follow_path`，也就不会重规划打断。

## 5. 听得见楼上

僵尸的视觉仍然按层隔断（楼板挡视线），追击靠听觉接上。但 `hear()` 原来对所有
"视线不通"的噪音乘 `wall_multiplier`，玩家一上二楼，楼下僵尸立刻聋了。

改成：**同一个 region 内不做遮蔽衰减**（`zombie._same_room()`，读
`world_definition.regions`）。同一栋楼里脚步、家具声沿结构传导，跨层听得见；
出了这栋楼才按墙衰减。

## 6. 隔层伤害修掉

```gdscript
var in_reach: bool = distance <= rule.attack_range \
    and absf(game.player.position.y - position.y) <= float(rule.get("floor_reach", 1.2))
```

`floor_reach = 1.2 m`：同一段楼梯上（高差 < 1.2）能打，隔一层楼板（3.5 m）打不到。
`in_reach` 同时替换了"贴太近就不移动"的判断——原来那一句用平面距离，会让
楼下的僵尸误以为已经贴脸，站在玩家正下方不动。

## 7. 一个差点漏掉的连带 bug：A\* 预算被吃光

`record.target` 从 `[x, 0, z]` 改成带真实高度 `[x, y, z]` 之后，
`test_connected_expedition` 立刻挂了：玩家在市场 (66.96, -10.14) 原地卡住，
被围殴到 0 血，kills 从 17 掉到 11。

排查过程（值得记下来）：

1. 先怀疑多层网格把市场弄堵了 —— 复算 `market_square` 的每个 collider，
   新规则下**一个都没被排除**，网格没变；
2. 把 `floors` 从 JSON 里删掉跑单层模式 —— **照样失败，卡同一个坐标**；
3. `git checkout -- scripts/zombie.gd` 还原僵尸脚本 —— 立刻回到
   `hp=79 / kills=17`。锁定在 zombie.gd。

真正的机制：

```gdscript
# 旧
if replan_left <= 0 or nav_revision != ... or path_goal.distance_squared_to(goal) > .01:
```

`goal` 现在带着玩家的 y。玩家每帧都有微小的落地抖动（-0.059 ↔ -0.05），
于是这个距离判定**每帧都为真**，每只僵尸每帧重规划。而 A\* 有
`PATH_BUDGET = 8` 次/物理帧 的全局预算 —— 十几只僵尸一拥而上就把预算吃干净，
**连测试里玩家自己的路线预览都拿不到路径**，于是站在原地看着自己被围。

修法是只比较平面：

```gdscript
var flat_goal := Vector3(goal.x, 0.0, goal.z)
if replan_left <= 0 or nav_revision != game.navigation.revision or path_goal.distance_squared_to(flat_goal) > .01:
```

教训：给一条"以前恒为 0"的坐标分量塞进真实值之前，先找出所有拿它做
**相等/距离比较来控制频率**的地方。这里高度变化本身无害，害的是它变成了
一个每帧都成立的重新规划触发器。

## 8. 验收

`godot/tests/test_floor_chase.gd` → `FLOOR_CHASE_OK`：

1. `navigation.floors.size() == 2`，第 1 层地面高度 3.56；
2. 一楼厨房柜 / 冰箱 / 衣柜前、二楼储物箱前、二楼楼梯口都有可站格（< 1.2 m）；
3. 一楼→二楼的路径确实经过 y > 2.5 的点（是爬楼梯，不是平面直走）；
4. 玩家在二楼、僵尸在一楼正下方，强制起手 → 血量不变；
5. 持续噪音 1080 帧内，僵尸爬到 y > 3.0 **并且**在到达后打出伤害
   （实测 `{"hp": 94, "y": 3.51}`，一次 6 点）；
6. 存档→读档后僵尸仍在第 1 层（`floor_index(y) == 1`）。

回归：`godot/tests/` 下 **42 个测试全部通过**（41 个既有 + 新增 `test_floor_chase`），
`tools/run_checks.py --godot ...` → `ALL_CHECKS_OK`。其中 `test_connected_expedition`
维持基线成绩 `17 kills / 回城 79 血`，证明分层改造没有改变既有战斗平衡。
