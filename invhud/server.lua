ESX = nil
ServerItems = {}
itemShopList = {}

TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)

for k,v in pairs(Config.Shops) do
	if v.Society.Name then
		TriggerEvent('esx_society:registerSociety', v.Society.Name, v.Society.Name, 'society_'..v.Society.Name, 'society_'..v.Society.Name, 'society_'..v.Society.Name, {type = 'public'})
	end
end

Notify = function(src, text, timer)
	if timer == nil then
		timer = 5000
	end
	-- TriggerClientEvent('mythic_notify:client:SendAlert', src, { type = 'inform', text = text, length = timer, style = { ['background-color'] = '#ffffff', ['color'] = '#000000' } })
	-- TriggerClientEvent('pNotify:SendNotification', src, {text = text, type = 'error', queue = GetCurrentResourceName(), timeout = timer, layout = 'bottomCenter'})
	TriggerClientEvent('esx:showNotification', src, text)
end

ESX.RegisterServerCallback('invhud:getPlayerInventory', function(source, cb, target)
	local tPlayer = ESX.GetPlayerFromId(target)

	if tPlayer ~= nil then
		cb({inventory = tPlayer.inventory, money = tPlayer.getMoney(), accounts = tPlayer.accounts, weapons = tPlayer.loadout})
	else
		cb(nil)
	end
end)

AddEventHandler('esx:giveInventoryItem', function(target, itemType, itemName, count)
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	local xTarget = ESX.GetPlayerFromId(target)
	if itemName == 'money' or itemName == 'cash' then
		if xPlayer.getMoney() >= count then
			xPlayer.removeMoney(count)
			xTarget.addMoney(count)
		else
			Notify(xPlayer.source, 'You do not have enough money')
		end
	end
end)

RegisterServerEvent('invhud:tradePlayerItem')
AddEventHandler('invhud:tradePlayerItem', function(from, target, type, itemName, itemCount)
	local src = from

	local xPlayer = ESX.GetPlayerFromId(src)
	local tPlayer = ESX.GetPlayerFromId(target)

	if type == 'item_standard' then
		local xItem = xPlayer.getInventoryItem(itemName)
		local tItem = tPlayer.getInventoryItem(itemName)
		
		if xPlayer.canCarryItem ~= nil then
			if itemCount > 0 and xItem.count >= itemCount then
				if tPlayer.canCarryItem(itemName, itemCount) then
					xPlayer.removeInventoryItem(itemName, itemCount)
					tPlayer.addInventoryItem(itemName, itemCount)
				else
					Notify(xPlayer.source, 'This player can not carry that much')
					Notify(tPlayer.source, 'You can not carry that much')
				end
			else
				Notify(xPlayer.source, 'You do not have enough of that item to give')
			end
		else
			if itemCount > 0 and xItem.count >= itemCount then
				if tItem.limit == -1 or (tItem.count + itemCount) <= tItem.limit then
					xPlayer.removeInventoryItem(itemName, itemCount)
					tPlayer.addInventoryItem(itemName, itemCount)
				else
					Notify(xPlayer.source, 'This player can not carry that much')
					Notify(tPlayer.source, 'You can not carry that much')
				end
			else
				Notify(xPlayer.source, 'You do not have enough of that item to give')
			end
		end
	elseif type == 'item_account' then
		if itemCount > 0 and xPlayer.getAccount(itemName).money >= itemCount then
			xPlayer.removeAccountMoney(itemName, itemCount)
			tPlayer.addAccountMoney(itemName, itemCount)
		else
			Notify(xPlayer.source, 'You do not have enough in that account to give')
		end
	elseif type == 'item_weapon' then
		if not tPlayer.hasWeapon(itemName) then
			xPlayer.removeWeapon(itemName)
			tPlayer.addWeapon(itemName, itemCount)
		else
			Notify(xPlayer.source, 'This person already has this weapon, just give them ammo')
		end
	end
end)

IsInInv = function(inv, item)
	for k,v in pairs(inv.items) do
		if item == k then
			return true
		end
	end
	for k,v in pairs(inv.weapons) do
		if item == k then
			return true
		end
	end
	return false
end

ESX.RegisterServerCallback('invhud:getInv', function(source, cb, type, id)
	local xPlayer = ESX.GetPlayerFromId(source)
	MySQL.Async.fetchAll('SELECT * FROM inventories WHERE owner = @owner AND type = @type', {['@owner'] = id, ['@type'] = type}, function(result)
		if result[1] then
			cb(json.decode(result[1].data))
		else
			MySQL.Async.execute('INSERT INTO `inventories` (owner, type, data) VALUES (@id, @type, @data)', {
				['@id'] = id,
				['@type'] = type,
				['@data'] = json.encode({items = {}, weapons = {}, blackMoney = 0, cash = 0})
			}, function(rowsChanged)
				if rowsChanged then
					print('Inventory created for: '..id..' with type: '..type)
				end
			end)
			cb({items = {}, weapons = {}, blackMoney = 0, cash = 0})
		end
	end)
end)

RegisterServerEvent('invhud:putItem')
AddEventHandler('invhud:putItem', function(invType, owner, data, count)
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	if data.item.type == 'item_money' then
		data.item.type = 'item_account'
		data.item.name = 'money'
	end
	if data.item.type == 'item_standard' then
		local xItem = xPlayer.getInventoryItem(data.item.name)
		if xItem.count >= count then
			local inventory = {}
			MySQL.Async.fetchAll('SELECT * FROM inventories WHERE owner = @owner AND type = @type', {['@owner'] = owner, ['@type'] = invType}, function(result)
				if result[1] then
					inventory = json.decode(result[1].data)
					if IsInInv(inventory, data.item.name) then
						if xItem.limit ~= nil then
							if inventory.items[data.item.name][1].count + count > xItem.limit then
								Notify(src, 'This inventory can not hold enough of that item')
								return
							end
						end
						xPlayer.removeInventoryItem(data.item.name, count)
						inventory.items[data.item.name][1].count = inventory.items[data.item.name][1].count + count
						MySQL.Async.execute('UPDATE inventories SET data = @data WHERE owner = @owner AND type = @type', {
							['@owner'] = owner,
							['@type'] = invType,
							['@data'] = json.encode(inventory)
						}, function(rowsChanged)
							if rowsChanged then
								print('Inventory updated for: '..owner..' with type: '..invType)
							end
						end)
					else
						if xItem.limit ~= nil then
							if count > xItem.limit then
								Notify(src, 'This inventory can not hold enough of that item')
								return
							end
						end
						xPlayer.removeInventoryItem(data.item.name, count)
						inventory.items[data.item.name] = {}
						table.insert(inventory.items[data.item.name], {count = count, label = data.item.label})
						MySQL.Async.execute('UPDATE inventories SET data = @data WHERE owner = @owner AND type = @type', {
							['@owner'] = owner,
							['@type'] = invType,
							['@data'] = json.encode(inventory)
						}, function(rowsChanged)
							if rowsChanged then
								print('Inventory updated for: '..owner..' with type: '..invType)
							end
						end)
					end
				end
			end)
		else
			Notify(src, 'You do not have that much of '..data.item.name)
		end
	elseif data.item.type == 'item_weapon' then
		if xPlayer.hasWeapon(data.item.name) then
			local inventory = {}
			MySQL.Async.fetchAll('SELECT * FROM inventories WHERE owner = @owner AND type = @type', {['@owner'] = owner, ['@type'] = invType}, function(result)
				if result[1] then
					inventory = json.decode(result[1].data)
					if IsInInv(inventory, data.item.name) then
						xPlayer.removeWeapon(data.item.name)
						table.insert(inventory.weapons[data.item.name], {count = count, label = data.item.label})
						MySQL.Async.execute('UPDATE inventories SET data = @data WHERE owner = @owner AND type = @type', {
							['@owner'] = owner,
							['@type'] = invType,
							['@data'] = json.encode(inventory)
						}, function(rowsChanged)
							if rowsChanged then
								print('Inventory updated for: '..owner..' with type: '..invType)
							end
						end)
					else
						xPlayer.removeWeapon(data.item.name)
						inventory.weapons[data.item.name] = {}
						table.insert(inventory.weapons[data.item.name], {count = count, label = data.item.label})
						MySQL.Async.execute('UPDATE inventories SET data = @data WHERE owner = @owner AND type = @type', {
							['@owner'] = owner,
							['@type'] = invType,
							['@data'] = json.encode(inventory)
						}, function(rowsChanged)
							if rowsChanged then
								print('Inventory updated for: '..owner..' with type: '..invType)
							end
						end)
					end
				end
			end)
		else
			Notify(src, 'You do not have that weapon')
		end
	elseif data.item.type == 'item_account' then
		local accountName, money
		if data.item.name == 'money' then
			accountName = 'cash'
			money = xPlayer.getMoney()
		elseif data.item.name == 'black_money' then
			accountName = 'blackMoney'
			money = xPlayer.getAccount(data.item.name).money
		end
		if money >= count then
			local inventory = {}
			MySQL.Async.fetchAll('SELECT * FROM inventories WHERE owner = @owner AND type = @type', {['@owner'] = owner, ['@type'] = invType}, function(result)
				if result[1] then
					inventory = json.decode(result[1].data)
					if data.item.name == 'money' then
						xPlayer.removeMoney(count)
					else
						xPlayer.removeAccountMoney(data.item.name, count)
					end
					inventory[accountName] = inventory[accountName] + count
					MySQL.Async.execute('UPDATE inventories SET data = @data WHERE owner = @owner AND type = @type', {
						['@owner'] = owner,
						['@type'] = invType,
						['@data'] = json.encode(inventory)
					}, function(rowsChanged)
						if rowsChanged then
							print('Inventory updated for: '..owner..' with type: '..invType)
						end
					end)
				end
			end)
		else
			Notify(src, 'You do not have enough cash to do that')
		end
	end
end)

RegisterServerEvent('invhud:getItem')
AddEventHandler('invhud:getItem', function(invType, owner, data, count)
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	if data.item.type == 'item_money' then
		data.item.type = 'item_account'
		data.item.name = 'money'
	end
	if data.item.type == 'item_standard' then
		local xItem = xPlayer.getInventoryItem(data.item.name)
		if xPlayer.canCarryItem ~= nil then
			if xPlayer.canCarryItem(data.item.name, count) then
				local inventory = {}
				MySQL.Async.fetchAll('SELECT * FROM inventories WHERE owner = @owner AND type = @type', {['@owner'] = owner, ['@type'] = invType}, function(result)
					if result[1] then
						inventory = json.decode(result[1].data)
						if IsInInv(inventory, data.item.name) then
							if inventory.items[data.item.name][1].count >= count then
								xPlayer.addInventoryItem(data.item.name, count)
								inventory.items[data.item.name][1].count = inventory.items[data.item.name][1].count - count
								if inventory.items[data.item.name][1].count <= 0 then
									inventory.items[data.item.name] = nil
								end
								MySQL.Async.execute('UPDATE inventories SET data = @data WHERE owner = @owner AND type = @type', {
									['@owner'] = owner,
									['@type'] = invType,
									['@data'] = json.encode(inventory)
								}, function(rowsChanged)
									if rowsChanged then
										print('Inventory updated for: '..owner..' with type: '..invType)
									end
								end)
							else
								Notify(src, 'There is not enough of that in the inventory')
							end
						else
							Notify(src, 'There is not enough of that in the inventory')
						end
					end
				end)
			else
				Notify(src, 'You do not have that much of '..data.item.name)
			end
		else
			if xItem.count + count <= xItem.limit then
				local inventory = {}
				MySQL.Async.fetchAll('SELECT * FROM inventories WHERE owner = @owner AND type = @type', {['@owner'] = owner, ['@type'] = invType}, function(result)
					if result[1] then
						inventory = json.decode(result[1].data)
						if IsInInv(inventory, data.item.name) then
							if inventory.items[data.item.name][1].count >= count then
								xPlayer.addInventoryItem(data.item.name, count)
								inventory.items[data.item.name][1].count = inventory.items[data.item.name][1].count - count
								if inventory.items[data.item.name][1].count <= 0 then
									inventory.items[data.item.name] = nil
								end
								MySQL.Async.execute('UPDATE inventories SET data = @data WHERE owner = @owner AND type = @type', {
									['@owner'] = owner,
									['@type'] = invType,
									['@data'] = json.encode(inventory)
								}, function(rowsChanged)
									if rowsChanged then
										print('Inventory updated for: '..owner..' with type: '..invType)
									end
								end)
							else
								Notify(src, 'There is not enough of that in the inventory')
							end
						else
							Notify(src, 'There is not enough of that in the inventory')
						end
					end
				end)
			else
				Notify(src, 'You do not have that much of '..data.item.name)
			end
		end
	elseif data.item.type == 'item_weapon' then
		if not xPlayer.hasWeapon(data.item.name) then
			local inventory = {}
			MySQL.Async.fetchAll('SELECT * FROM inventories WHERE owner = @owner AND type = @type', {['@owner'] = owner, ['@type'] = invType}, function(result)
				if result[1] then
					inventory = json.decode(result[1].data)
					if IsInInv(inventory, data.item.name) then
						for i = 1,#inventory.weapons[data.item.name] do
							if inventory.weapons[data.item.name][i].count == data.item.count then
								xPlayer.addWeapon(data.item.name, inventory.weapons[data.item.name][i].count)
								table.remove(inventory.weapons[data.item.name], i)
								MySQL.Async.execute('UPDATE inventories SET data = @data WHERE owner = @owner AND type = @type', {
									['@owner'] = owner,
									['@type'] = invType,
									['@data'] = json.encode(inventory)
								}, function(rowsChanged)
									if rowsChanged then
										print('Inventory updated for: '..owner..' with type: '..invType)
									end
								end)
								break
							end
						end
					else
						Notify(src, 'There is not enough of that in the inventory')
					end
				end
			end)
		else
			Notify(src, 'You already have this weapon')
		end
	elseif data.item.type == 'item_account' then
		local accountName
		if data.item.name == 'money' then
			accountName = 'cash'
		elseif data.item.name == 'black_money' then
			accountName = 'blackMoney'
		end
		local inventory = {}
		MySQL.Async.fetchAll('SELECT * FROM inventories WHERE owner = @owner AND type = @type', {['@owner'] = owner, ['@type'] = invType}, function(result)
			if result[1] then
				inventory = json.decode(result[1].data)
				if inventory[accountName] >= count then
					if data.item.name == 'money' then
						xPlayer.addMoney(count)
					else
						xPlayer.addAccountMoney(data.item.name, count)
					end
					inventory[accountName] = inventory[accountName] - count
					MySQL.Async.execute('UPDATE inventories SET data = @data WHERE owner = @owner AND type = @type', {
						['@owner'] = owner,
						['@type'] = invType,
						['@data'] = json.encode(inventory)
					}, function(rowsChanged)
						if rowsChanged then
							print('Inventory updated for: '..owner..' with type: '..invType)
						end
					end)
				else
					Notify(src, 'There is not enough of that in the inventory')
				end
			end
		end)
	end
end)

ESX.RegisterServerCallback('invhud:getShopItems', function(source, cb, shoptype)
	itemShopList = {items = {}, weapons = {}}
	local itemResult = MySQL.Sync.fetchAll('SELECT * FROM items')
	local itemInformation = {}

	for i=1, #itemResult, 1 do

		if itemInformation[itemResult[i].name] == nil then
			itemInformation[itemResult[i].name] = {}
		end

		itemInformation[itemResult[i].name].name = itemResult[i].name
		itemInformation[itemResult[i].name].label = itemResult[i].label
		itemInformation[itemResult[i].name].limit = itemResult[i].limit
		itemInformation[itemResult[i].name].rare = itemResult[i].rare
		itemInformation[itemResult[i].name].can_remove = itemResult[i].can_remove
		itemInformation[itemResult[i].name].price = itemResult[i].price
		if Config.Shops[shoptype].Account == 'black_money' then
			itemInformation[itemResult[i].name].price = itemInformation[itemResult[i].name].price * 2
		end

		for _, v in pairs(Config.Shops[shoptype].Items) do
			if v.name == itemResult[i].name then
				table.insert(itemShopList.items, {
					type = 'item_standard',
					name = itemInformation[itemResult[i].name].name,
					label = itemInformation[itemResult[i].name].label,
					limit = itemInformation[itemResult[i].name].limit,
					rare = itemInformation[itemResult[i].name].rare,
					can_remove = itemInformation[itemResult[i].name].can_remove,
					price = itemInformation[itemResult[i].name].price,
					count = 1
				})
			end
		end
	end
	if Config.Shops[shoptype].Weapons ~= nil then
		for _, v in pairs(Config.Shops[shoptype].Weapons) do
			if Config.Shops[shoptype].Account == 'black_money' then
				v.price = v.price * 2
			end
			table.insert(itemShopList.weapons, {
				type = 'item_weapon',
				name = v.name,
				label = v.label,
				limit = 1,
				ammo = 1,
				rare = false,
				can_remove = false,
				price = v.price,
				count = 1
			})
		end
	end
	itemShopList = itemShopList
	cb(itemShopList)
end)

RegisterServerEvent('invhud:SellItemToPlayer')
AddEventHandler('invhud:SellItemToPlayer',function(invType, item, count, shop)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if invType == 'item_standard' then
		local tItem = xPlayer.getInventoryItem(item)
		if xPlayer.canCarryItem ~= nil then
			if xPlayer.canCarryItem(item, count) then
				local list = itemShopList.items
				for k,v in pairs(list) do
					if v.name == item then
						local totalPrice = count * v.price
						if shop.Account ~= 'money' and shop.Account ~= 'cash' then -- I FUCKING HATE ESX
							if xPlayer.getAccount(shop.Account).money >= totalPrice then
								xPlayer.removeAccountMoney(shop.Account, totalPrice)
								xPlayer.addInventoryItem(item, count)
								Notify(source, 'You purchased '..count..' '..v.label..' for '..Config.CurrencyIcon..totalPrice)
								if shop.Society.Name then
									TriggerEvent('esx_addonaccount:getSharedAccount', shop.Society.Name, function(account)
										account.addMoney(amount)
									end)
								end
							else
								Notify(source, 'You do not have enough money!')
							end
						else
							if xPlayer.getMoney() >= totalPrice then
								xPlayer.removeMoney()
								xPlayer.addInventoryItem(item, count)
								Notify(source, 'You purchased '..count..' '..v.label..' for '..Config.CurrencyIcon..totalPrice)
								if shop.Society.Name then
									TriggerEvent('esx_addonaccount:getSharedAccount', shop.Society.Name, function(account)
										account.addMoney(amount)
									end)
								end
							else
								Notify(source, 'You do not have enough money!')
							end
						end
					end
				end
			else
				Notify(source, 'You do not have enough space in your inventory!')
			end
		else
			if tItem.count + count <= tItem.limit then
				local list = itemShopList.items
				for k,v in pairs(list) do
					if v.name == item then
						local totalPrice = count * v.price
						if shop.Account ~= 'money' and shop.Account ~= 'cash' then -- I FUCKING HATE ESX
							if xPlayer.getAccount(shop.Account).money >= totalPrice then
								xPlayer.removeAccountMoney(shop.Account, totalPrice)
								xPlayer.addInventoryItem(item, count)
								Notify(source, 'You purchased '..count..' '..v.label..' for '..Config.CurrencyIcon..totalPrice)
								if shop.Society.Name then
									TriggerEvent('esx_addonaccount:getSharedAccount', shop.Society.Name, function(account)
										account.addMoney(amount)
									end)
								end
							else
								Notify(source, 'You do not have enough money!')
							end
						else
							if xPlayer.getMoney() >= totalPrice then
								xPlayer.removeMoney()
								xPlayer.addInventoryItem(item, count)
								Notify(source, 'You purchased '..count..' '..v.label..' for '..Config.CurrencyIcon..totalPrice)
								if shop.Society.Name then
									TriggerEvent('esx_addonaccount:getSharedAccount', shop.Society.Name, function(account)
										account.addMoney(amount)
									end)
								end
							else
								Notify(source, 'You do not have enough money!')
							end
						end
					end
				end
			else
				Notify(source, 'You do not have enough space in your inventory!')
			end
		end
	end
	
	if invType == 'item_weapon' then
		local targetWeapon = xPlayer.hasWeapon(tostring(item))
        if not targetWeapon then
            local list = itemShopList.weapons
			for k,v in pairs(list) do
				if v.name == item then
					local totalPrice = 1 * v.price
					if shop.Account ~= 'money' and shop.Account ~= 'cash' then -- I FUCKING HATE ESX
						if xPlayer.getAccount(shop.Account).money >= totalPrice then
							xPlayer.removeAccountMoney(shop.Account, totalPrice)
							xPlayer.addWeapon(v.name, v.ammo)
							Notify(source, 'You purchased a '..v.label..' for '..Config.CurrencyIcon..totalPrice)
							if shop.Society.Name then
								TriggerEvent('esx_addonaccount:getSharedAccount', shop.Society.Name, function(account)
									account.addMoney(totalPrice)
								end)
							end
						else
							Notify(source, 'You do not have enough money!')
						end
					else
						if xPlayer.getMoney() >= totalPrice then
							xPlayer.removeMoney(totalPrice)
							xPlayer.addWeapon(v.name, v.ammo)
							Notify(source, 'You purchased a '..v.label..' for '..Config.CurrencyIcon..totalPrice)
							if shop.Society.Name then
								TriggerEvent('esx_addonaccount:getSharedAccount', shop.Society.Name, function(account)
									account.addMoney(totalPrice)
								end)
							end
						else
							Notify(source, 'You do not have enough money!')
						end
					end
				end
            end
        else
            Notify(source, 'You already own this weapon!' )
        end
	end
end)

RegisterServerEvent('invhud:SellItemToShop')
AddEventHandler('invhud:SellItemToShop',function(invType, item, count, shop)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if invType == 'item_standard' then
		local tItem = xPlayer.getInventoryItem(item)
		if tItem.count >= count then
			local list = itemShopList.items
			for k,v in pairs(list) do
				if v.name == item then
					local totalPrice = count * v.price * shop.BuyBack
					if totalPrice < 1 then
						totalPrice = 0
					end
					if shop.Society.Name then
						TriggerEvent('esx_addonaccount:getSharedAccount', shop.Society.Name, function(account)
							if account.money >= totalPrice then
								if shop.Account ~= 'money' and shop.Account ~= 'cash' then -- I FUCKING HATE ESX
									xPlayer.addAccountMoney(shop.Account, totalPrice)
									xPlayer.removeInventoryItem(item, count)
									Notify(source, 'You sold '..count..' '..v.label..' for '..Config.CurrencyIcon..totalPrice)
									account.removeMoney(totalPrice)
								else
									xPlayer.addMoney(totalPrice)
									xPlayer.removeInventoryItem(item, count)
									Notify(source, 'You sold '..count..' '..v.label..' for '..Config.CurrencyIcon..totalPrice)
									account.removeMoney(totalPrice)
								end
							else
								Notify(source, 'The shop does not have enough money')
							end
						end)
					else
						if shop.Account ~= 'money' and shop.Account ~= 'cash' then -- I FUCKING HATE ESX
							xPlayer.addAccountMoney(shop.Account, totalPrice)
							xPlayer.removeInventoryItem(item, count)
							Notify(source, 'You sold '..count..' '..v.label..' for '..Config.CurrencyIcon..totalPrice)
						else
							xPlayer.addMoney(totalPrice)
							xPlayer.removeInventoryItem(item, count)
							Notify(source, 'You sold '..count..' '..v.label..' for '..Config.CurrencyIcon..totalPrice)
						end
					end
				end
			end
		else
			Notify(source, 'You do not have '..count..' '..item..' in your inventory!')
		end
	end
	
	if invType == 'item_weapon' then
		local targetWeapon = xPlayer.hasWeapon(tostring(item))
        if targetWeapon then
            local list = itemShopList.weapons
			for k,v in pairs(list) do
				if v.name == item then
					local totalPrice = 1 * v.price * shop.BuyBack
					if totalPrice < 1 then
						totalPrice = 0
					end
					if shop.Account ~= 'money' and shop.Account ~= 'cash' then -- I FUCKING HATE ESX
						xPlayer.addAccountMoney(shop.Account, totalPrice)
						xPlayer.removeWeapon(v.name, 0)
						Notify(source, 'You sold a '..v.label..' for '..Config.CurrencyIcon..totalPrice)
					else
						xPlayer.removeMoney(totalPrice)
						xPlayer.removeWeapon(v.name, 0)
						Notify(source, 'You sold a '..v.label..' for '..Config.CurrencyIcon..totalPrice)
					end
				end
            end
        else
            Notify(source, 'You do not own this weapon!' )
        end
	end
end)

for k,v in pairs(Config.Bullets) do
	ESX.RegisterUsableItem(k, function(source)
		TriggerClientEvent('invhud:usedAmmo', source, k)
	end)
end

RegisterServerEvent('invhud:usedAmmo')
AddEventHandler('invhud:usedAmmo', function(item)
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	xPlayer.removeInventoryItem(item, 1)
end)