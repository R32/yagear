local NAME, ADDON = ...

local function location_unpack(location)
	if location < 0  then
		return false, false, false, 0
	end
	local player = (bit.band(location, ITEM_INVENTORY_LOCATION_PLAYER) ~= 0)
	local bank = (bit.band(location, ITEM_INVENTORY_LOCATION_BANK) ~= 0)
	local bags = (bit.band(location, ITEM_INVENTORY_LOCATION_BAGS) ~= 0)
	if player then
		location = location - ITEM_INVENTORY_LOCATION_PLAYER
	elseif bank then
		location = location - ITEM_INVENTORY_LOCATION_BANK
	end
	if not bags then
		return player, bank, bags, location
	end
	location = location - ITEM_INVENTORY_LOCATION_BAGS
	local bag = bit.rshift(location, ITEM_INVENTORY_BAG_BIT_OFFSET)
	local slot = location - bit.lshift(bag, ITEM_INVENTORY_BAG_BIT_OFFSET)
	if bank then
		bag = bag + ITEM_INVENTORY_BANK_BAG_OFFSET
	end
	return player, bank, bags, slot, bag
end

local function player_icons(popup)
	local icons = {}
	-- gear manager set, *make sure the sets icon at the beginning*
	local sets = C_EquipmentSet.GetEquipmentSetIDs()
	for _, id in ipairs(sets) do
		local _, tex = C_EquipmentSet.GetEquipmentSetInfo(id)
		if tex then
			tinsert(icons, tex)
		end
	end
	-- equips
	local equips = {}
	for i = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
		local list = {}
		GetInventoryItemsForSlot(i, list)
		for location in next, list do
			local tex
			local player, bank, bags, slot, bag = location_unpack(location)
			if not bags then
				tex = GetInventoryItemTexture("player", slot)
			else
				tex = C_Item.GetItemIconByID(C_Container.GetContainerItemID(bag, slot))
			end
			if tex then
				equips[tex] = true -- removed duplicate textures
			end
		end
	end
	for tex in next, equips do
		tinsert(icons, tex)
	end
	-- talents
	local talents = {}
	for i = 1, GetNumTalentTabs() do
		for j = 1, GetNumTalents(i) do
			local _, tex = GetTalentInfo(i, j)
			talents[tex] = true
		end
	end
	for tex in next, talents do
		tinsert(icons, tex)
	end
	return icons
end

local function put_cursor_item()
	if C_Container.GetContainerNumFreeSlots(0) > 0 then
		PutItemInBackpack()
		return
	end
	for i = 1, 4 do
		if C_Container.GetContainerNumFreeSlots(i) > 0 then
			PutItemInBag(C_Container.ContainerIDToInventoryID(i))
			return
		end
	end
	-- bank
	local slots = C_Container.GetContainerFreeSlots(-1)
	if slots[1] and slots[1] < NUM_BANKGENERIC_SLOTS then
		PickupInventoryItem(slots[1] + BankButtonIDToInvSlotID(0))
		return
	end
	for i = 5, 10 do
		if C_Container.GetContainerNumFreeSlots(i) > 0 then
			PutItemInBag(C_Container.ContainerIDToInventoryID(i))
			return
		end
	end
	ClearCursor()
	UIErrorsFrame:AddMessage(ERR_EQUIPMENT_MANAGER_BAGS_FULL, 1.0, 0.1, 0.1, 1.0)
end

local function tip_onleave(self)
	GameTooltip:Hide()
end

local function tip_onenter(self)
	local text = self.name
	if not text or text == "" then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(text, 1., 1., 1.)
end

local POP_CX, POP_CY = 7, 6

local function popup_icon_select_inner(popup, offset, selected, state)
	if not selected then
		return
	end
	local i = selected - offset * POP_CX
	if not (i > 0 and i <= POP_CX * POP_CY) then
		return
	end
	popup.items[i]:SetChecked(state)
end
local function popup_icon_select(popup, offset, selected)
	popup_icon_select_inner(popup, offset, popup.selected, false)
	popup_icon_select_inner(popup, offset, selected, true)
	popup.selected = selected
end

local function manager_item_select(manager, selected)
	if not selected then
		manager.selected = nil
	elseif selected ~= manager.selected then
		if manager.selected then
			manager.selected:SetChecked(false)
		end
		manager.selected = selected
	end
	if selected then
		selected:SetChecked(true)
	end
	local enable = selected and true or false
	manager.button_delete:SetEnabled(enable)
	manager.button_equip:SetEnabled(enable)
end

local function manager_ignores_clear(manager)
	C_EquipmentSet.ClearIgnoredSlotsForSave()
	for _, slot in ipairs(manager.lslot) do
		slot.ignored = nil
		slot.ignore_texture:Hide()
	end
end

local function manager_ignores_refresh(manager, sid)
	local ignores = C_EquipmentSet.GetIgnoredSlots(sid)
	C_EquipmentSet.ClearIgnoredSlotsForSave()
	local lslot = manager.lslot
	for id, t in ipairs(ignores) do
		local slot = lslot[id]
		slot.ignored = t
		slot.ignore_texture:SetShown(t)
		if t then
			C_EquipmentSet.IgnoreSlotForSave(id)
		end
	end
end

local function manager_item_onclick(item)
	local manager = item:GetParent()
	if not item.name or item.name == "" then
		item:Disable()
		item:SetChecked(false)
		return
	end
	if item == manager.selected then
		manager.selected = nil
		return
	end
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	manager_ignores_refresh(manager, item.sid)
	manager_item_select(manager, item)
	if manager.popup:IsShown() then
		local popup = manager.popup
		popup.editor:SetText(item.name)
		local pos = item:GetID()
		if item.icon:GetTexture() == popup.icons[pos] then
			popup_icon_select(popup, 0, pos)
		end
	end
end

local function manager_item_onenter(item)
	if not item.name or item.name == "" then
		return
	end
	GameTooltip_SetDefaultAnchor(GameTooltip, item)
	GameTooltip:SetEquipmentSet(item.name)
end

local function manager_item_ondrag(item)
	if not item.name or item.name == "" then
		return
	end
	C_EquipmentSet.PickupEquipmentSet(item.sid)
end

local function manager_button_onsave(button)
	local manager = button:GetParent()
	manager.popup:Show()
end

local function manager_button_ondelete(button)
	local manager = button:GetParent()
	local item = manager.selected
	if not item then
		return
	end
	local dialog = StaticPopup_Show("CONFIRM_DELETE_EQUIPMENT_SET", item.name)
	if dialog then
		dialog.data = item.sid
	else
		UIErrorsFrame:AddMessage(ERR_CLIENT_LOCKED_OUT, 1.0, 0.1, 0.1, 1.0)
	end
end

local function manager_button_onequip(button)
	local manager = button:GetParent()
	local item = manager.selected
	if not item then
		return
	end
	if C_EquipmentSet.EquipmentSetContainsLockedItems(item.sid) or UnitCastingInfo("player") then
		UIErrorsFrame:AddMessage(ERR_CLIENT_LOCKED_OUT, 1.0, 0.1, 0.1, 1.0)
		return
	end
	C_EquipmentSet.UseEquipmentSet(item.sid)
end

-- GearManagerDialog_Update
local function manager_update(manager)
	local items = manager.items
	local sets = C_EquipmentSet.GetEquipmentSetIDs()
	for i, sid in ipairs(sets) do
		local name, texture = C_EquipmentSet.GetEquipmentSetInfo(sid)
		local item = items[i]
		item:Enable()
		item.name = name
		item.sid = sid
		item.text:SetText(name)
		item.icon:SetTexture(texture or "Interface/Icons/INV_Misc_QuestionMark")
		item:SetChecked(false)
	end
	for i = #sets + 1, 10 do
		local item = items[i]
		item:Disable()
		item:SetChecked(false)
		item.name = nil
		item.sid = nil
		item.text:SetText("")
		item.icon:SetTexture("")
	end
	if manager.selected and not manager.selected:IsEnabled() then
		-- when deleting a set
		manager.selected = nil
	end
	manager_item_select(manager, manager.selected)
end

--  If the ignores are inconsistent after calling "CreateEquipmentSet"
local function manager_ignores_hackfixed(manager, sid)
	for _, t in ipairs(C_EquipmentSet.GetIgnoredSlots(sid)) do
		if t then
			return -- Means that the "CreateEquipmentSet" successfully saved the "ignores"
		end
	end
	local found = false
	for _, slot in ipairs(manager.lslot) do
		if slot.ignored then
			found = true
			break
		end
	end
	if not found then return end
	-- Calling "SaveEquipmentSet" in event "EQUIPMENT_SETS_CHANGED" will cause BUG, So delay it
	C_Timer.After(0.5, function()
		C_EquipmentSet.SaveEquipmentSet(sid)
	end)
end

local function manager_onevent(manager, event, ...)
	if event == "EQUIPMENT_SETS_CHANGED" then
		manager_update(manager)
		if not manager.nsets then
			return
		end
		local item = manager.items[manager.nsets + 1]
		manager.nsets = nil
		if not item.sid then
			return
		end
		manager_item_select(manager, item)
		manager_ignores_hackfixed(manager, item.sid)
	elseif event == "EQUIPMENT_SWAP_FINISHED" then
		local success, sid = ...
		if not success or not manager:IsShown() then
			return
		end
		manager_update(manager)
		manager_ignores_refresh(manager, sid)
	end
end

local function manager_onshow(manager)
	ADDON.gear:SetButtonState("PUSHED", 1)
	manager:RegisterEvent("EQUIPMENT_SETS_CHANGED")
	PlaySound(SOUNDKIT.IG_BACKPACK_OPEN)
	manager.selected = nil
	manager_ignores_clear(manager)
	manager_update(manager)
end

local function manager_onhide(manager)
	ADDON.gear:SetButtonState("NORMAL")
	manager:UnregisterEvent("EQUIPMENT_SETS_CHANGED")
	PlaySound(SOUNDKIT.IG_BACKPACK_CLOSE)
	manager.selected = nil
	manager_ignores_clear(manager)
end

local function flyout_seat_onenter(seat)
	local location = seat.location
	if not location then
		return
	end
	GameTooltip:SetOwner(seat, "ANCHOR_RIGHT")
	if location < 0 then
		GameTooltip:SetText(seat.name)
		return
	end
	local bags, slot, bag = unpack(seat.info)
	if not bags then
		GameTooltip:SetInventoryItem("player", slot)
	else
		GameTooltip:SetBagItem(bag, slot)
	end
end
local function flyout_seat_display(seat, bslot, location)
	seat.info = nil
	seat.location = location
	if not location then
		return
	end
	seat:Show()
	if location >= 0 then
		local player, bank, bags, slot, bag = location_unpack(location)
		if not bags then
			seat.icon:SetTexture(GetInventoryItemTexture("player", slot))
		else
			local itemid = C_Container.GetContainerItemID(bag, slot)
			seat.icon:SetTexture(C_Item.GetItemIconByID(itemid))
		end
		seat.info = {bags, slot, bag}
	elseif location == -2 then
		seat.icon:SetTexture("Interface/PaperDollInfoFrame/UI-GearManager-ItemIntoBag")
		seat.name = EQUIPMENT_MANAGER_PLACE_IN_BAGS
	elseif location == -1 then
		seat.icon:SetTexture(bslot.ignored and "Interface/PaperDollInfoFrame/UI-GearManager-Undo" or "Interface/PaperDollInfoFrame/UI-GearManager-LeaveItem-Opaque")
		seat.name = bslot.ignored and EQUIPMENT_MANAGER_UNIGNORE_SLOT or EQUIPMENT_MANAGER_IGNORE_SLOT
	end
	seat.icon:Show()
	if seat:IsMouseOver() then
		flyout_seat_onenter(seat)
	end
end

-- PaperDollFrameItemFlyoutButton_OnClick
local function flyout_seat_onclick(seat, button, down)
	local location = seat.location
	local flyout = ADDON.flyout
	local bslot = flyout.owner
	if not location or not bslot then
		return
	end
	local id = bslot:GetID()
	if location == -1 then
		if bslot.ignored then
			bslot.ignored = nil
			bslot.ignore_texture:Hide()
			C_EquipmentSet.UnignoreSlotForSave(id)
		else
			bslot.ignored = 1
			bslot.ignore_texture:Show()
			C_EquipmentSet.IgnoreSlotForSave(id)
		end
		flyout_seat_display(seat, bslot, location)
		return
	end
	if UnitAffectingCombat("player") then
		return
	end
	-- pickup
	flyout:UnregisterAllEvents()
	if location >= 0 then
		local bags, slot, bag = unpack(seat.info)
		if not bags then
			PickupInventoryItem(slot)
		else
			C_Container.PickupContainerItem(bag, slot)
		end
	elseif location == -2 then
		PickupInventoryItem(id)
	end
	if not CursorHasItem() then
		return
	end
	flyout:RegisterEvent("ITEM_LOCK_CHANGED")
	-- put in bag
	if location >= 0 then
		PickupInventoryItem(id)
		ClearCursor()
	elseif location == -2 then
		put_cursor_item()
	end
end

local function flyout_zone_onleave(zone)
	if zone:IsMouseOver() then
		return
	end
	GameTooltip:Hide()
	zone:GetParent():Hide()
end

local function flyout_onhide(flyout)
	local slot = flyout.owner
	flyout.owner = nil
	if slot and slot.hasItem and GameTooltip:IsShown() then
		local seat = GameTooltip:GetOwner()
		if seat and seat:GetParent() == flyout.zone then
			GameTooltip:SetOwner(slot, "ANCHOR_RIGHT")
			GameTooltip:SetInventoryItem("player", slot:GetID(), nil, true)
		end
	end
end

local function flyout_display(flyout, slot)
	if not slot then return end
	local id = slot:GetID()
	local list = {}
	local locations = {}
	if slot.hasItem then
		tinsert(locations, -2)
	end
	if ADDON.manager and ADDON.manager:IsShown() then
		tinsert(locations, -1)
	end
	GetInventoryItemsForSlot(id, list)
	for location in next, list do
		if location - id ~= ITEM_INVENTORY_LOCATION_PLAYER then
			tinsert(locations, location)
		end
	end
	table.sort(locations)
	local num = min(#locations, 23) -- PDFITEMFLYOUT_MAXITEMS = 23
	if num == 0 then
		flyout:Hide()
		return
	end
	flyout.owner = slot
	-- update
	local zone = flyout.zone
	local seats = zone.seats
	while #seats < num do
		local seat = CreateFrame("BUTTON", nil, zone, "ItemButtonTemplate")
		seat:SetScript("OnEnter", flyout_seat_onenter)
		seat:SetScript("OnClick", flyout_seat_onclick)
		local len = #seats
		local cy = len / 5
		if cy == 0 then
			seat:SetPoint("TOPLEFT", zone, "TOPLEFT", 3, -3)
		elseif floor(cy) == cy then -- 5, 10, 25
			seat:SetPoint("TOPLEFT", seats[len - 4], "BOTTOMLEFT", 0, -3)
		else
			seat:SetPoint("TOPLEFT", seats[len], "TOPRIGHT", 4, 0)
		end
		tinsert(seats, seat)
	end
	for i, seat in ipairs(seats) do
		if i <= num then
			flyout_seat_display(seat, slot, locations[i])
		else
			seat:Hide()
		end
	end
	flyout:ClearAllPoints()
	flyout:SetFrameLevel(slot:GetFrameLevel() - 1)
	flyout:SetPoint("TOPLEFT", slot, "TOPLEFT", -3, 3)
	if id >= 16 and id <= 18 then
		zone:SetPoint("TOPLEFT", flyout, "BOTTOMLEFT", 0, -3)
	else
		zone:SetPoint("TOPLEFT", flyout, "TOPRIGHT", 0, 0)
	end
	local cx = min(5, num)
	zone:SetSize(cx * 37 + (cx - 1) * 4 + 5, 43 + floor((num - 1) / 5) * 43)
	-- zone:GetRegions():SetAllPoints() -- texture debug
	flyout:Show()
	flyout:Raise()
	if slot.hasItem and GameTooltip:IsOwned(slot) then
		GameTooltip:SetOwner(seats[cx], "ANCHOR_RIGHT", 4, 0)
		GameTooltip:SetInventoryItem("player", id, nil, true)
	end
end

local function flyout_onitem_changed(flyout, event, slot, state)
	-- if event ~= "ITEM_LOCK_CHANGED" then return end
	flyout:UnregisterAllEvents()
	flyout_display(flyout, flyout.owner)
end

local function flyout_onmodify(slot, event, key, down)
	-- IsModifiedClick("SHOWITEMFLYOUT")
	if event ~= "MODIFIER_STATE_CHANGED" or not (key == "LALT" or key == "RALT") then
		return
	end
	local flyout = ADDON.flyout
	if down == 1 then
		flyout_display(flyout, slot)
	else
		flyout:Hide()
	end
end
local function equipslot_onenter(slot)
	flyout_onmodify(slot, "MODIFIER_STATE_CHANGED", "LALT", IsAltKeyDown() and 1 or 0)
end

local function equipslot_onupdate(slot)
	if not slot.ignore_texture then
		return
	end
	if not ADDON.manager:IsShown() then
		slot.ignored = nil
	end
	if slot.ignored then
		slot.ignore_texture:Show()
	else
		slot.ignore_texture:Hide()
	end
end

-- GearManagerDialogPopupOkay_OnClick
local function popup_button_onokey(button)
	local popup = button:GetParent()
	local name = strtrim(popup.editor:GetText())
	if name == "" then
		popup.editor:SetFocus()
		return
	end
	local sid = C_EquipmentSet.GetEquipmentSetID(name)
	local icon = popup.icons[popup.selected]
	local manager = popup:GetParent()
	manager.nsets = nil
	if sid then
		local dialog = StaticPopup_Show("CONFIRM_OVERWRITE_EQUIPMENT_SET" .. "_"  .. NAME, name)
		if dialog then
			dialog.data = sid
			dialog.selectedIcon = icon
		else
			UIErrorsFrame:AddMessage(ERR_CLIENT_LOCKED_OUT, 1.0, 0.1, 0.1, 1.0)
		end
		return
	end
	local nsets = C_EquipmentSet.GetNumEquipmentSets()
	if nsets >= 10 then
		UIErrorsFrame:AddMessage(EQUIPMENT_SETS_TOO_MANY, 1.0, 0.1, 0.1, 1.0)
		return
	end
	manager.nsets = nsets
	C_EquipmentSet.CreateEquipmentSet(name, icon) -- BUGBUG : This doesn't work with "C_EquipmentSet.IgnoreSlotForSave"
	popup:Hide()
end
local function popup_button_oncancel(button)
	local popup = button:GetParent()
	popup:Hide()
end

local function popup_onhide(popup)
	popup.editor:SetText("")
	popup.editor:ClearFocus()
	popup.selected = nil
	popup.icons = nil
	local manager = popup:GetParent()
	manager.button_save:Enable()
end

local function popup_update(popup)
	local items = popup.items
	local icons = popup.icons
	local scroll = popup.scroll
	local slider = scroll.slider
	local offset = floor(slider:GetValue() + 0.5)
	local range = ceil(#popup.icons / POP_CX)
	slider.ScrollUpButton:SetEnabled(offset > 0)
	slider.ScrollDownButton:SetEnabled(offset < range - POP_CY)
	for i = 1, POP_CX * POP_CY do
		local item = items[i]
		local icon = icons[(offset * POP_CX) + i]
		item.icon:SetTexture(icon or "")
		item:SetChecked(false)
		item:SetEnabled(icon and true or false)
	end
	popup_icon_select_inner(popup, offset, popup.selected, true)
end

local function popup_scroll_onwheel(scroll, offset)
	local slider = scroll.slider
	slider:SetValue(slider:GetValue() - offset)
end

local function popup_scroll_onscroll(scroll, offset)
	popup_update(scroll:GetParent())
end

local function popup_onshow(popup)
	PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
	local manager = popup:GetParent()
	manager.button_save:Disable()
	popup.editor:SetFocus()
	popup.icons = player_icons()
	local range = ceil(#popup.icons / POP_CX)
	local scroll = popup.scroll
	local slider = scroll.slider
	if range > POP_CY then
		-- thumb size / scroll bar size = page size / scroll bar range
		local h = slider:GetHeight() * POP_CY / range
		if h > 24 then
			slider.ThumbTexture:SetHeight(h)
		end
		slider:SetMinMaxValues(0, range - POP_CY)
		scroll:SetScript("OnVerticalScroll", popup_scroll_onscroll)
		scroll:SetScript("OnMouseWheel", popup_scroll_onwheel)
	else
		slider:SetMinMaxValues(0, 0)
		slider.ScrollDownButton:Disable()
		slider.ScrollUpButton:Disable()
		scroll:SetScript("OnVerticalScroll", nil)
		scroll:SetScript("OnMouseWheel", nil)
	end
	slider:SetValue(0)
	if manager.selected then
		local set = manager.selected
		local pos = set:GetID()
		if set.icon:GetTexture() == popup.icons[pos] then
			popup.selected = pos -- make sure the icon is at the beginning
		end
		popup.editor:SetText(set.name)
	end
	popup_update(popup)
end

local function popup_icon_onclick(icon)
	local popup = icon:GetParent()
	local scroll = popup.scroll
	local offset = floor(scroll.slider:GetValue() + 0.5)
	local selected = (offset * POP_CX) + icon:GetID()
	if selected == popup.selected then
		popup.selected = nil
		return
	end
	popup_icon_select(popup, offset, selected)
end

local function popup_scroll_up(self)
	local slider = self:GetParent()
	slider:SetValue(slider:GetValue() - 1)
	PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
end

local function popup_scroll_down(self)
	local slider = self:GetParent()
	slider:SetValue(slider:GetValue() + 1)
	PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
end

local function popup_scroll_init(popup)
	local scroll = CreateFrame("ScrollFrame", nil, popup)
	scroll:SetSize(344, 266)
	scroll:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -13, -88)
	local slider = CreateFrame("Slider", nil, scroll, "UIPanelScrollBarTemplate")
	slider:SetPoint("TOPLEFT", scroll, "TOPRIGHT", -20, -16)
	slider:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 16)
	slider:SetMinMaxValues(0, 0)
	slider:SetValue(0)
	scroll.slider = slider
	slider.ScrollUpButton:SetScript("OnClick", popup_scroll_up)
	slider.ScrollDownButton:SetScript("OnClick", popup_scroll_down)
	slider.ThumbTexture:SetTextureSliceMargins(6, 8, 6, 8)
	return scroll
end

local function popup_init(manager)
	local popup = CreateFrame("Frame", nil, manager, "SelectionFrameTemplate")
	popup:Hide()
	popup:ClearAllPoints()
	popup:SetSize(372, 392)
	popup:SetPoint("TOPLEFT", manager, "BOTTOMLEFT", 0, 8)
	popup:SetScript("OnShow", popup_onshow)
	popup:SetScript("OnHide", popup_onhide)
	popup.OnCancel = popup_button_oncancel
	popup.OnOkay = popup_button_onokey
	-- layers
	local label = popup:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	label:SetPoint("TOPLEFT", 24, -18)
	label:SetText(GEARSETS_POPUP_TEXT)
	local label = popup:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	label:SetPoint("TOPLEFT", 24, -69)
	label:SetText(MACRO_POPUP_CHOOSE_ICON)
	local bg = popup:CreateTexture(nil, "BACKGROUND")
	bg:SetPoint("TOPLEFT", 7, -7)
	bg:SetPoint("BOTTOMRIGHT", -7, 7)
	bg:SetColorTexture(0, 0, 0, 0.8)

	local editor = CreateFrame("EditBox", nil, popup, "InputBoxTemplate")
	editor:SetSize(182, 20)
	editor:SetPoint("TOPLEFT", 26, -35)
	editor:SetMaxLetters(16)
	editor:SetAutoFocus(false)
	editor:SetHistoryLines(0)
	editor:SetScript("OnEscapePressed", popup_button_oncancel)
	popup.editor = editor

	popup.scroll = popup_scroll_init(popup)

	local items = {}
	for i = 1, POP_CX * POP_CY do
		local item = CreateFrame("CheckButton", nil, popup, "SimplePopupButtonTemplate")
		item:SetID(i)
		item:SetScript("OnClick", popup_icon_onclick)
		item:SetNormalTexture("")
		local icon = item:GetNormalTexture()
		icon:SetPoint("CENTER", 0, -1)
		icon:SetSize(36, 36)
		item.icon = icon
		item:SetHighlightTexture("Interface/Buttons/ButtonHilight-Square", "ADD")
		item:SetCheckedTexture("Interface/Buttons/CheckButtonHilight")
		item:GetCheckedTexture():SetBlendMode("ADD")
		local cy = (i - 1) / POP_CX
		if cy == 0 then
			item:SetPoint("TOPLEFT", 24, -90)
		elseif cy == floor(cy) then
			item:SetPoint("TOPLEFT", items[i - POP_CX], "BOTTOMLEFT", 0, -8)
		else
			item:SetPoint("TOPLEFT", items[i - 1], "TOPRIGHT", 8, 0)
		end
		tinsert(items, item)
	end
	popup.items = items
	return popup
end

local function manager_confirm_overwrite(self)
	C_EquipmentSet.SaveEquipmentSet(self.data, self.selectedIcon)
	ADDON.manager.popup:Hide()
end

local function manager_init(parent)
	-- GearManagerDialog
	local manager = CreateFrame("Frame", nil, parent, "UIPanelDialogTemplate")
	manager:SetSize(261, 155)
	manager:SetPoint("TOPLEFT", parent, "TOPRIGHT", -38, -10)
	manager:SetFrameStrata("MEDIUM")
	manager:SetToplevel(true)
	manager.Title:SetText(EQUIPMENT_MANAGER)
	-- fixed the close button position
	local close = manager:GetChildren()
	close:SetPoint("TOPRIGHT", 2, 1)
	-- items
	local items = {}
	for i = 1, 10 do
		local item = CreateFrame("CheckButton", nil, manager, "PopupButtonTemplate") -- GearSetButtonTemplate
		item:SetID(i)
		if i == 1 then
			item:SetPoint("TOPLEFT", manager, "TOPLEFT", 16, -32)
		elseif i == 6 then
			item:SetPoint("TOP", items[1], "BOTTOM", 0, -10)
		else
			item:SetPoint("LEFT", items[i - 1], "RIGHT", 13, 0)
		end
		item:SetScript("OnClick", manager_item_onclick)
		item:SetScript("OnEnter", manager_item_onenter)
		item:SetScript("OnLeave", tip_onleave)
		item:SetScript("OnDragStart", manager_item_ondrag)
		item:RegisterForDrag("LeftButton")
		local text, _, icon = item:GetRegions() -- PopupButtonTemplate (ItemButtonTemplate.lua)
		item.text = text
		item.icon = icon
		tinsert(items, item)
	end
	manager.items = items
	manager:Hide()
	manager:SetScript("OnShow", manager_onshow)
	manager:SetScript("OnHide", manager_onhide)
	manager:RegisterEvent("EQUIPMENT_SWAP_FINISHED")
	manager:SetScript("OnEvent", manager_onevent)
	-- save/delete/equip buttons
	local mk = function(anchor, pt, x, y, text, onclick)
		local button = CreateFrame("Button", nil, anchor, "UIPanelButtonTemplate")
		button:SetSize(78, 22)
		button:SetPoint(pt, x, y)
		button:SetScript("OnClick", onclick)
		button:SetText(text)
		return button
	end
	manager.button_equip = mk(manager, "BOTTOMLEFT", 93, 12, EQUIPSET_EQUIP or "Equip", manager_button_onequip)
	manager.button_delete = mk(manager, "BOTTOMLEFT", 11, 12, DELETE or "Delete", manager_button_ondelete)
	manager.button_save = mk(manager, "BOTTOMRIGHT", -8, 12, SAVE or "Save", manager_button_onsave)
	-- paperdoll slot buttons
	local buttons = {PaperDollItemsFrame:GetChildren()}
	local lslot = {}
	for i = 1, 19 do
		local button = buttons[i]
		lslot[button:GetID()] = button
		local tex = button:CreateTexture(nil, "OVERLAY")
		tex:Hide()
		tex:SetSize(40, 40)
		tex:SetPoint("CENTER")
		tex:SetTexture("Interface/PaperDollInfoFrame/UI-GearManager-LeaveItem-Transparent")
		button.ignore_texture = tex
	end
	manager.lslot = lslot
	hooksecurefunc("PaperDollItemSlotButton_Update", equipslot_onupdate)
	-- popup
	manager.popup = popup_init(manager)
	-- hack
	local overwrite = CreateFromMixins(StaticPopupDialogs["CONFIRM_OVERWRITE_EQUIPMENT_SET"], { OnAccept = manager_confirm_overwrite })
	StaticPopupDialogs["CONFIRM_OVERWRITE_EQUIPMENT_SET" .. "_"  .. NAME] = overwrite
	return manager
end

local function gear_toggle(gear)
	local manager = ADDON.manager
	if not manager then
		manager = manager_init(gear:GetParent())
		ADDON.manager = manager
	end
	if manager:IsShown() then
		manager:Hide()
	else
		manager:Show()
		manager:Raise()
	end
end

local function init(parent)
	-- Blizzard_CharacterFrame/PaperDollFrame.xml
	if GearManagerToggleButton and GearManagerToggleButton:IsShown() then
		return
	end
	local gear = CreateFrame("Button", nil, parent)
	gear:SetSize(32, 32)
	gear:SetPoint("TOPRIGHT", -44, -39)
	gear:SetNormalTexture("Interface/PaperDollInfoFrame/UI-GearManager-Button")
	gear:SetPushedTexture("Interface/PaperDollInfoFrame/UI-GearManager-Button-Pushed")
	gear:SetHighlightTexture("Interface/Buttons/UI-MicroButton-Hilight", "ADD")
	gear:GetHighlightTexture():SetTexCoord(0, 1, 0.390625, 0.96875)
	gear:SetScript("OnEnter", tip_onenter)
	gear:SetScript("OnLeave", tip_onleave)
	gear:SetScript("OnClick", gear_toggle)
	gear.name = EQUIPMENT_MANAGER or GetAddOnMetadata(NAME, "Title")

	parent[NAME] = gear
	ADDON.gear = gear
	-- PaperDollFrameItemFlyout
	local flyout = CreateFrame("Frame", nil, parent)
	flyout:SetSize(43, 43)
	flyout:EnableMouse(false)
	flyout:SetFrameStrata("HIGH")
	flyout:Hide()
	flyout:SetScript("OnEvent", flyout_onitem_changed)
	flyout:SetScript("OnHide", flyout_onhide)
	local tex = flyout:CreateTexture(nil, "OVERLAY")
	tex:SetSize(50, 50)
	tex:SetPoint("LEFT", -4, 0)
	tex:SetTexture("Interface/PaperDollInfoFrame/UI-GearManager-ItemButton-Highlight")
	tex:SetTexCoord(0, 0.78125, 0, 0.78125)

	local zone = CreateFrame("Frame", nil, flyout)
	zone:SetPoint("TOPLEFT", flyout, "TOPRIGHT")
	zone:SetFrameStrata("HIGH")
	zone:SetScript("OnLeave", flyout_zone_onleave)
	-- TODO
	-- local tex = zone:CreateTexture(nil, "BACKGROUND")
	-- tex:SetPoint("TOPLEFT", -5, 4)
	-- tex:SetColorTexture(1., 0, 0, 0.8)
	---- tex:SetTexture("Interface/PaperDollInfoFrame/UI-GearManager-Flyout")
	zone.seats = {}
	flyout.zone = zone
	ADDON.flyout = flyout
	-- equipslot hook
	hooksecurefunc("PaperDollItemSlotButton_OnEvent", flyout_onmodify)
	hooksecurefunc("PaperDollItemSlotButton_OnEnter", equipslot_onenter)
end

local function main()
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_LOGIN")
	frame:SetScript("OnEvent", function(frame)
		frame:SetScript("OnEvent", onevent)
		frame:UnregisterEvent("PLAYER_LOGIN")
		init(PaperDollFrame)
	end)
end

local _ = main()
