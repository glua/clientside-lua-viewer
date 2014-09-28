require"stringtable" --all willox' stuff
require"luamio"

local javascript_escape_replacements = {
	["\\"] = "\\\\",
	["\0"] = "\\0" ,
	["\b"] = "\\b" ,
	["\t"] = "\\t" ,
	["\n"] = "\\n" ,
	["\v"] = "\\v" ,
	["\f"] = "\\f" ,
	["\r"] = "\\r" ,
	["\""] = "\\\"",
	["\'"] = "\\\'"
}

function string.JavascriptSafe( str )

	str = str:gsub( ".", javascript_escape_replacements )

	-- U+2028 and U+2029 are treated as line separators in JavaScript, handle separately as they aren't single-byte
	str = str:gsub( "\226\128\168", "\\\226\128\168" )
	str = str:gsub( "\226\128\169", "\\\226\128\169" )

	return str

end

local function GetLuaFiles(client_lua_files)
	local count = client_lua_files:Count()
	local ret = {}

	for i = 1, count - 2 do
		local path = client_lua_files:GetString(i)
		--if file.Exists(path, "MOD") then continue end --skip files we already have (this also skips files that servers modify, but eh garry forgot to include util.CRC in menu state)
		ret[i] = {
			Path = path,
			CRC = client_lua_files:GetUserDataInt(i)
		}
	end

	return ret
end

local function GetLuaFileContents(crc)
	local fs = file.Open("cache/lua/" .. crc .. ".lua", "rb", "MOD")

	fs:Seek(4)

	local contents = util.Decompress(fs:Read(fs:Size() - 4))

	return contents:sub(1, -2) -- Trim trailing null
end

local function dumbFile(path, contents)
	if not  path:match("%.lua$") then path = path..".lua" end
	local curdir = ""
	for t in path:gmatch("[^/\\*]+") do
		curdir = curdir..t
		if  curdir:match("%.lua$") then
			local f = io.open("garrysmod/data/"..curdir, "w+")
			f:write(contents)
			f:close()
		else
			curdir = curdir.."/"
			file.CreateDir(curdir)
		end
	end
end

local dumbFolderCache = ""
local function dumbFolder(node)
	for _, subnode in ipairs(node.ChildNodes:GetChildren()) do
		if subnode:HasChildren() then
			dumbFolder(subnode)
		else
			dumbFile(dumbFolderCache..subnode.pathh, GetLuaFileContents(subnode.CRC))
		end
	end
end

local VIEWER = {}

function VIEWER:Init()
	if not IsInGame() then 
		MsgC(Color(255, 0, 0), "Not in game")
		self:Close()
		return
	end
	self:SetTitle"clientsude lua viewer"
	self:SetSize(ScrW() * .75, ScrH() * .75)
	self:Center()
	self:SetSizable(true)

	self.left = vgui.Create("PANEL", self)
	self.left:SetWide(self:GetWide() * .2)
	self.left:Dock(LEFT)

	self.tree = vgui.Create("DTree", self.left)
	self.tree:Dock(FILL)
	self.tree.Directories = {}

	self.right = vgui.Create("PANEL", self)
	self.right:Dock(FILL)

	self.html = vgui.Create("DHTML", self.right)
	self.html:Dock(FILL)
	self.html:SetAllowLua(true)
	self.html:OpenURL("asset://garrysmod/lua/menu_plugins/luaviewer/index.html") --thx metastruct
	self.html:AddFunction("gmodinterface", "OnCode", function(code) self.currentCode = code end)

	self.override = vgui.Create("DButton", self.right)
	self.override:Dock(BOTTOM)
	self.override:SetTall(self.override:GetTall() * 1.5)
	self.override:SetText("Override")
	self.override.DoClick = function()
		if not (self.currentPath or self.currentCode) then return end
		dumbFile("overrides/"..self.currentPath, self.currentCode)
		print("Overwrote "..self.currentPath)
	end

	client_lua_files = stringtable.Get "client_lua_files"

	local tree_data= {}

	for i, v in ipairs(GetLuaFiles(client_lua_files)) do
		if i == 1 then continue end
		local file_name = string.match(v.Path, ".*/([^/]+%.lua)")
		local dir_path = string.sub(v.Path, 1, -1 - file_name:len())

		local file_crc = v.CRC
 
		local cur_dir = tree_data
 
		for dir in string.gmatch(dir_path, "([^/]+)/") do
			if not cur_dir[dir] then
				cur_dir[dir] = {}
			end
 
			cur_dir = cur_dir[dir]
		end
 
		cur_dir[file_name] = {fileN = file_name, CRC = file_crc}
	end

	local file_queue = {}
	local function iterate(data, node, path)
		path = path or ""
 
		for k, v in SortedPairs(data) do
			if type(v) == "table" and not v.CRC then
				local new_node = node:AddNode(k)
				new_node.DoRightClick = function()
					local dmenu = DermaMenu(new_node)
					dmenu:SetPos(gui.MouseX(), gui.MouseY())
					dmenu:AddOption("dumb", function() 
						dumbFolderCache = "dumbs/"..os.date("%d.%m.%y %H.%M").."/" 
						print("Writing files...")
						local start = CurTime() 

						dumbFolder(new_node) 

						print("Done writing files! Took "..CurTime() - start.." seconds")
					end)
					dmenu:Open()
				end
 
				iterate(v, new_node, path .. k .. "/")
			else
				table.insert(file_queue, {node = node, fileN = v.fileN, path = path .. v.fileN, CRC = v.CRC})
			end
		end
	end
 
	iterate(tree_data, self.tree)

	for k, v in ipairs(file_queue) do
			local node = v.node:AddNode(v.fileN, "icon16/page.png")
 
			node.DoClick = function()
				self.html:QueueJavascript("SetContent('"..string.JavascriptSafe(GetLuaFileContents(v.CRC)).."'); GotoLine(1);")
				self.currentPath = v.path
			end
			node.DoRightClick = function()
				local dmenu = DermaMenu(node)
				dmenu:SetPos(gui.MouseX(), gui.MouseY())
				dmenu:AddOption("dumb", function() dumbFile("dumbs/"..os.date("%d.%m.%y %H.%M").." "..v.fileN, GetLuaFileContents(v.CRC)) end)
				dmenu:Open()
			end
			node.CRC = v.CRC
			node.pathh = v.path
	end

end

derma.DefineControl("luaviewer", "views clientside lua files", VIEWER, "DFrame")

concommand.Add("lua_view_cl", function()
	vgui.Create("luaviewer"):MakePopup()
end)