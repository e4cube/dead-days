extends CanvasLayer
## UI reads authoritative state and invokes existing model transactions.
var game
var window: PanelContainer
var body: VBoxContainer
var content: HBoxContainer
var status: Label
var details: RichTextLabel
var detail_icon
var detail_name: Label
var kind:=""
var target:=""
var selected:="food"
var category:="全部"
var map_view

func setup(owner_game) -> void:
    game=owner_game
    layer=15
    window=PanelContainer.new()
    add_child(window)
    window.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    window.offset_left=40; window.offset_right=-40
    window.offset_top=70; window.offset_bottom=-45
    var style:=StyleBoxFlat.new()
    style.bg_color=Color("15201ff5")
    style.content_margin_left=18; style.content_margin_right=18
    style.content_margin_top=15; style.content_margin_bottom=15
    window.add_theme_stylebox_override("panel",style)
    body=VBoxContainer.new()
    window.add_child(body)
    window.hide()

func is_open() -> bool:
    return is_instance_valid(window) and window.visible
func close() -> void:
    window.hide()
    if is_instance_valid(game.map_toggle): game.map_toggle.show()
    game.get_viewport().gui_release_focus()
func action(parent: Node, text: String, callback: Callable, blocked: String="") -> Button:
    var button:=Button.new()
    button.text=text
    button.disabled=not blocked.is_empty()
    button.tooltip_text=blocked
    button.pressed.connect(callback)
    parent.add_child(button)
    return button
func label(parent: Node,text: String) -> Label:
    var result:=Label.new()
    result.text=text
    parent.add_child(result)
    return result
func clear() -> void:
    for child in body.get_children():
        body.remove_child(child)
        child.queue_free()
func open(mode: String, container: String="") -> void:
    kind=mode; target=container
    if is_instance_valid(game.map_toggle): game.map_toggle.hide()
    window.show()
    refresh()
func group(id: String) -> String:
    var rule: Dictionary=game.model.rules.items[id]
    if rule.get("kind","")=="weapon": return "武器"
    if rule.get("kind","")=="ammo": return "弹药"
    return "医疗" if rule.get("stat","")=="health" else "补给"
func refresh() -> void:
    clear()
    var header:=HBoxContainer.new()
    body.add_child(header)
    var title:=label(header,"区域地图" if kind=="map" else ("背包" if kind=="inventory" else game.model.container_name(target)+" / 物资存取"))
    title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
    action(header,"关闭 [Esc]",close)
    status=label(body,"负重 %.2f / %.1f kg    生命 %.0f    饥饱 %.0f    饮水 %.0f"%[game.model.weight(),game.model.rules.capacity,game.model.state.stats.health,game.model.state.stats.hunger,game.model.state.stats.thirst])
    var feedback:=label(body,game.last_notice)
    feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
    if kind=="map":
        build_map()
        return
    var filters:=HBoxContainer.new()
    body.add_child(filters)
    for name in ["全部","补给","医疗","武器","弹药"]:
        action(filters,name,func(): category=name; refresh())
    content=HBoxContainer.new()
    content.size_flags_vertical=Control.SIZE_EXPAND_FILL
    body.add_child(content)
    if kind=="storage": item_list(true)
    item_list(false)
    var right:=VBoxContainer.new()
    right.custom_minimum_size.x=260
    right.size_flags_horizontal=Control.SIZE_EXPAND_FILL
    content.add_child(right)
    var header_row:=HBoxContainer.new()
    right.add_child(header_row)
    detail_icon=preload("res://scripts/item_icon.gd").new()
    header_row.add_child(detail_icon)
    detail_icon.setup(selected,40)
    detail_name=label(header_row,game.model.rules.items[selected].name)
    detail_name.add_theme_font_size_override("font_size",19)
    details=RichTextLabel.new()
    details.size_flags_vertical=Control.SIZE_EXPAND_FILL
    right.add_child(details)
    show_detail()
    if kind=="storage":
        action(right,"取出 1 件",func(): transfer(false,1))
        action(right,"取出 5 件",func(): transfer(false,5))
        action(right,"尽可能取出所选",func(): transfer(false,10000))
        action(right,"存入 1 件",func(): transfer(true,1))
        action(right,"存入 5 件",func(): transfer(true,5))
        action(right,"存入全部所选",func(): transfer(true,10000))
    else:
        action(right,"使用 / 装备 / 装填",func(): game.use(selected); refresh())
        action(right,"放下 1 件",drop_selected)
        action(right,"放下 5 件",func(): drop_selected(5))
        action(right,"卸下手枪弹药",func(): game.model.Firearms.unload(game.model); refresh())
    label(body,"[E] 快速搜刮 · [B] 容器逐件/批量存取 · [I] 背包 · [Tab] 地图 · 灰色图标=当前不可用")
## Selected-row highlight; the accent matches the map marker colour.
func select_style() -> StyleBoxFlat:
    var style:=StyleBoxFlat.new()
    style.bg_color=Color("2b3f38")
    style.border_width_left=3
    style.border_color=Color("dfac60")
    style.content_margin_left=6
    style.content_margin_right=6
    style.content_margin_top=2
    style.content_margin_bottom=2
    return style

func plain_style() -> StyleBoxFlat:
    var style:=StyleBoxFlat.new()
    style.bg_color=Color("182220")
    style.content_margin_left=6
    style.content_margin_right=6
    style.content_margin_top=2
    style.content_margin_bottom=2
    return style

func item_list(stored: bool) -> void:
    var column:=VBoxContainer.new()
    column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
    content.add_child(column)
    label(column,"容器 %.2f / %.1f kg"%[game.model.container_weight(target),game.model.container_capacity(target)] if stored else "随身物品")
    var scroll:=ScrollContainer.new()
    scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
    column.add_child(scroll)
    var rows:=VBoxContainer.new()
    rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL
    scroll.add_child(rows)
    var source: Dictionary=game.model.state.containers[target] if stored else game.model.state.inventory
    var count:=0
    for id in game.model.rules.items:
        if source.get(id,0)<=0 or (category!="全部" and group(id)!=category): continue
        var rule: Dictionary=game.model.rules.items[id]
        var row:=HBoxContainer.new()
        rows.add_child(row)
        var badge:=preload("res://scripts/item_icon.gd").new()
        row.add_child(badge)
        badge.setup(id,26)
        var reason: String
        if stored:
            reason = game.model.transfer_reason(target,id,false)
        else:
            reason = game.item_action_reason(id)
        var caption := "%s  ×%d   %.2fkg" % [rule.name, source[id], float(rule.weight)*source[id]]
        if not reason.is_empty():
            caption += "   · " + reason
        var button:=Button.new()
        button.text=caption
        button.alignment=HORIZONTAL_ALIGNMENT_LEFT
        button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
        button.add_theme_stylebox_override("normal", select_style() if id==selected else plain_style())
        button.pressed.connect(func(): selected=id; refresh())
        row.add_child(button)
        badge.set_dimmed(not reason.is_empty())
        count+=1
    if count==0: label(rows,"没有此类物品")
func show_detail() -> void:
    var rule: Dictionary=game.model.rules.items[selected]
    if is_instance_valid(detail_icon):
        detail_icon.setup(selected,40)
    if is_instance_valid(detail_name):
        detail_name.text=rule.name
    var blocked: String = game.model.transfer_reason(target,selected,false) if kind=="storage" else game.item_action_reason(selected)
    details.text="%s / %s\n单件重量 %.3fkg\n随身数量 %d\n"%[rule.name,group(selected),rule.weight,game.model.state.inventory.get(selected,0)]
    if rule.has("restore"): details.text+="使用恢复 %s +%.0f\n"%[{"health":"生命","hunger":"饥饱","thirst":"饮水"}.get(rule.stat,rule.stat),rule.restore]
    if rule.get("kind","")=="weapon":
        var weapon: Dictionary=game.model.rules.weapons[selected]
        details.text+="伤害 %.0f · 距离 %.1fm\n体力消耗 %.0f\n"%[weapon.damage,weapon.range,weapon.stamina]
    details.text+="\n手枪弹匣 %d/%d\n备用9mm ×%d\n"%[game.model.Firearms.loaded(game.model),game.model.rules.weapons.pistol.magazine,game.model.state.inventory.get("ammo_9mm",0)]
    details.text+="\n当前操作："+result_reason(blocked)+"\n"
    if kind=="storage":
        details.text+="\n取出："+result_reason(game.model.transfer_reason(target,selected,false))+"\n存入："+result_reason(game.model.transfer_reason(target,selected,true))
func result_reason(reason: String) -> String:
    return "可操作" if reason.is_empty() else reason
func transfer(deposit: bool, limit: int) -> void:
    if game.nearby().get("id","")!=target:
        game.last_notice="请靠近当前容器。"
        close()
        return
    var moved:=0
    for i in limit:
        if not game.model.transfer_item(target,selected,deposit): break
        moved+=1
    game.last_notice="%s%s ×%d"%["存入" if deposit else "取出",game.model.rules.items[selected].name,moved]
    game.refresh_hud()
    refresh()
func drop_selected(times: int = 1) -> void:
    game.sync_position()
    var pile: String=""
    var moved:=0
    for index in times:
        pile=game.model.GroundDrops.put_one(game.model,selected,game.player.position,"")
        if pile.is_empty(): break
        moved+=1
    var reason: String=game.model.GroundDrops.reason(game.model,selected)
    game.last_notice="已放下 %s ×%d"%[game.model.rules.items[selected].name,moved] if moved>0 else (reason if not reason.is_empty() else "此处无法放下：请在可用楼层平地操作，或清理已满物资堆。")
    game.refresh_hud(true)
    refresh()
func build_map() -> void:
    var bar:=HBoxContainer.new()
    body.add_child(bar)
    var note:=LineEdit.new()
    note.placeholder_text="标记备注；右键地图放置（最多64个）"
    note.max_length=80
    note.size_flags_horizontal=Control.SIZE_EXPAND_FILL
    bar.add_child(note)
    map_view=preload("res://scripts/world_map.gd").new()
    map_view.game=game
    map_view.marker_text=note
    map_view.size_flags_vertical=Control.SIZE_EXPAND_FILL
    body.add_child(map_view)
    action(bar,"地面",func(): map_view.floor_index=0; map_view.queue_redraw())
    action(bar,"二层",func(): map_view.floor_index=1; map_view.queue_redraw())
    action(bar,"撤销末个标记",func():
        if not game.model.state.exploration.markers.is_empty(): game.model.state.exploration.markers.pop_back()
        map_view.queue_redraw())
    action(bar,"居中玩家",func(): map_view.pan=-(Vector2(game.player.position.x,game.player.position.z)-Vector2(90,-14))*map_view.scale_factor(); map_view.queue_redraw())
    label(body,"北↑ · 滚轮缩放 / 左键拖动 / 右键标记 · 空心点=未观察过，实心=上次见到有物资，×=上次已空（不显示实时库存）· 室内按 G 设为据点")
