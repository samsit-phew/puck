local json = require("dkjson")
local lfs = require("lfs")

-- determine script directory (where main.lua lives) so we can find the cheatsheet folder
local function script_dir()
	local info = debug.getinfo(1, "S")
	local source = info and info.source or ""
	if source:sub(1,1) == "@" then
		local path = source:sub(2)
		return path:match("^(.*)/") or "."
	end
	return "."
end
local PUCK_ROOT = script_dir()

-- Simple config parser for puck_config.yaml placed in PUCK_ROOT
local function write_default_config()
	local cfg_path = PUCK_ROOT .. "/puck_config.yaml"
	local fcheck = io.open(cfg_path, "r")
	if fcheck then
		fcheck:close()
		print("Config already exists at: " .. cfg_path)
		return
	end
	local content = [[
# puck_config.yaml - puck global configuration
# Set the following options to true or false to enable/disable features.
# Lines starting with '#' are comments. Example: copy_cheatsheet: true

# copy_cheatsheet: When true, puck copies language cheatsheets from puck/cheatsheet
# into newly created projects. You can still override per-create with --no-cheatsheet.
copy_cheatsheet: true

# auto_venv: When true, puck will create a Python virtual environment for new
# python projects. Set to false to skip automatic venv creation.
auto_venv: true

# assembly_build: When true, puck will attempt to build/run assembly projects
# (using Makefile or nasm/ld). Set to false to disable building assembly projects.
assembly_build: true

# delete_force: When true, deleting a project will NOT ask for confirmation.
# Use with caution; this will permanently delete the specified project.
delete_force: false

]]
	local f = io.open(cfg_path, "w")
	if not f then
		print("Failed to write config to: " .. cfg_path)
		return
	end
	f:write(content)
	f:close()
	print("Created default config at: " .. cfg_path)
end

local function read_config()
	local cfg = {
		copy_cheatsheet = true,
		auto_venv = true,
		assembly_build = true,
		delete_force = false,
	}
	local path = PUCK_ROOT .. "/puck_config.yaml"
	local f = io.open(path, "r")
	if not f then
		-- prompt user to create a default config if running interactively
		if io.type(io.stdin) == "file" and os.getenv("TERM") then
			io.stdout:write("No puck_config.yaml found. Create default config? (y/n): ")
			local ans = io.read()
			if ans and ans:lower() == "y" then
				write_default_config()
				f = io.open(path, "r")
				if not f then return cfg end
			else
				print("Proceeding with default configuration values.")
				return cfg
			end
		else
			-- non-interactive: proceed with defaults
			return cfg
		end
	end
	for line in f:lines() do
		line = line:match("^%s*(.-)%s*$") -- trim
		if line ~= "" and not line:match("^#") then
			local k, v = line:match("^(%w+)%s*:%s*(%w+)")
			if k and v then
				if v:lower() == "true" then cfg[k] = true
				elseif v:lower() == "false" then cfg[k] = false
				else cfg[k] = v end
			end
		end
	end
	f:close()
	return cfg
end

-- load global config once
local PUCK_CONFIG = read_config()

local function execute(cmd)
	local f = io.popen(cmd)
	local res = f:read("*a")
	f:close()
	return res
end

local function file_exists(name)
	local f = io.open(name, "r")
	if f then
		f:close()
		return true
	else
		return false
	end
end

local function write_file(name, content)
	local f = io.open(name, "w")
	assert(f, "Failed to open file for writing: " .. name)
	f:write(content)
	f:close()
end

local function read_json(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local data = f:read("*a")
	f:close()
	return json.decode(data)
end

local function create_gitignore(lang)
	local ignores = {
		lua = "*.luac\n*.bak\n.DS_Store\n",
		python = "*.pyc\n__pycache__/\nenv/\n.venv/\n.DS_Store\n",
		cpp = "*.o\n*.out\n*.exe\n.DS_Store\nbuild/\n",
		c = "*.o\n*.out\n*.exe\n.DS_Store\nbuild/\n",
		rust = "target/\nCargo.lock\n.DS_Store\n",
		html = "node_modules/\n.DS_Store\n",
		js = "node_modules/\ndist/\n.DS_Store\n.env\n",
		css = ".DS_Store\n",
		assembly = "*.o\n*.bin\n.DS_Store\nbuild/\n",
	}
	return ignores[lang] or ".DS_Store\n"
end

local function get_username()
	return (os.getenv("USER") or execute("whoami"):gsub("\n", "")):gsub("%s+", "")
end

local function get_timestamp()
	local t = os.date("!*t")
	return string.format("%04d-%02d-%02dT%02d:%02d:%02dZ", t.year, t.month, t.day, t.hour, t.min, t.sec)
end
--these are boilerplate
local function boilerplate(lang, pname, author, created_at)
	local hello = {
		lua = string.format(
			[[
local function main()
    print("Hello, %s")
end

main()
]],
			author
		),
		python = string.format(
			[[
def main():
    print("Hello, %s")

if __name__ == "__main__":
    main()
]],
			author
		),
		cpp = string.format(
			[[
#include <iostream>

int main() {
    std::cout << "Hello, %s" << std::endl;
    return 0;
}
]],
			author
		),
		c = string.format(
			[[
#include <stdio.h>

int main() {
    printf("Hello, %s\\n");
    return 0;
}
]],
			author
		),
		rust = string.format(
			[[
fn main() {
    println!("Hello, %s");
}
]],
			author
		),
		html = string.format(
			[[
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Hello, World!</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
    <h1>Hello, %s</h1>
    <script src="main.js"></script>
</body>
</html>
]],
			author
		),
		js = string.format(
			[[
console.log("Hello, %s");
]],
			author
		),
		css = string.format([[
body {
    font-family: sans-serif;
    margin: 2em;
}
h1 {
    color: #333;
}
]]),
		assembly = string.format([[
section .data
	hello: db "Hello, %s", 10
	hello_len: equ $-hello

section .text
	global _start
_start:
	mov rax, 1
	mov rdi, 1
	mov rsi, hello
	mov rdx, hello_len
	syscall
	mov rax, 60
	xor rdi, rdi
	syscall
]], author),
	}
	if lang == "cpp" or lang == "c" or lang == "assembly" then
		lfs.mkdir(pname .. "/src")
		if lang == "cpp" then
			write_file(pname .. "/src/main.cpp", hello.cpp)
		elseif lang == "c" then
			write_file(pname .. "/src/main.c", hello.c)
		else -- assembly
			write_file(pname .. "/src/main.asm", hello.assembly)
			-- simple Makefile for NASM (elf64) default
			local mk = [[
NASM=nasm
LD=ld
ASM_SRC=src/main.asm
OBJ=src/main.o
all:
	$(NASM) -f elf64 $(ASM_SRC) -o $(OBJ)
	$(LD) $(OBJ) -o main

clean:
	rm -f $(OBJ) main
]]
			write_file(pname .. "/Makefile", mk)
		end
	elseif lang == "html" then
		write_file(pname .. "/index.html", hello.html)
		write_file(pname .. "/main.js", hello.js)
		write_file(pname .. "/style.css", hello.css)
	else
		local ext = (lang == "python" and "py") or lang
		write_file(pname .. "/main." .. ext, hello[lang])
	end
end

-- copy binary file (pdf) from src to dst
local function copy_file(src, dst)
	local inf = io.open(src, "rb")
	if not inf then return false, "source not found: " .. src end
	local data = inf:read("*a")
	inf:close()
	local outf = io.open(dst, "wb")
	if not outf then return false, "failed to open dest: " .. dst end
	outf:write(data)
	outf:close()
	return true
end

local function copy_cheatsheet(pname, lang)
	-- mapping uses the actual filenames in puck/cheatsheet for common languages
	local map = {
		python = { "pythoncheatsheet.pdf" },
		lua = { "luacheatsheet.pdf" },
		rust = { "rustcheatsheet.pdf" },
		c = { "ccheatsheet.pdf" },
		cpp = { "cppcheatsheet.pdf" },
		js = { "jscheatsheet.pdf" },
		html = { "htmlcheatsheet.pdf", "jscheatsheet.pdf", "csscheatsheet.pdf" },
	}
	if lang == "assembly" then
		-- collect any assembly cheatsheet files (pdf and markdown variants)
		local found = {}
		for file in lfs.dir(PUCK_ROOT .. "/cheatsheet") do
			if file:match("^assemblycheatsheet.*%.pdf$") or file:match("^assemblycheatsheet.*%.mark") then
				table.insert(found, file)
			end
		end
		if #found == 0 then
			print("No assembly cheatsheets found in " .. PUCK_ROOT .. "/cheatsheet")
			return
		end
		for _, fname in ipairs(found) do
			local src = PUCK_ROOT .. "/cheatsheet/" .. fname
			local dst = pname .. "/" .. fname
			local ok, err = copy_file(src, dst)
			if ok then
				print("Copied cheatsheet " .. fname .. " to project.")
			else
				print("Failed to copy cheatsheet: " .. err)
			end
		end
		return
	end
	local files = map[lang]
	if not files then return end
	for _, fname in ipairs(files) do
		local src = PUCK_ROOT .. "/cheatsheet/" .. fname
		local dst = pname .. "/" .. fname
		if file_exists(src) then
			local ok, err = copy_file(src, dst)
			if ok then
				print("Copied cheatsheet " .. fname .. " to project.")
			else
				print("Failed to copy cheatsheet: " .. err)
			end
		else
			print("Cheatsheet not found: " .. src)
		end
	end
end

local function write_readme(pname, lang, author, created_at)
	local content = string.format(
		[[
project_name: %s

Language: **%s**

**Author:** `%s`

**Created:** %s

]],
		pname,
		lang,
		author,
		created_at
	)
	write_file(pname .. "/project_info.yaml", content)
end

local function create_project(pname, lang, opts)
	if file_exists(pname) then
		print("Directory already exists: " .. pname)
		return
	end
	local author = get_username()
	local created_at = get_timestamp()
	if lang == "rust" then
		execute("cargo new " .. pname)
		local main_rs = pname .. "/src/main.rs"
		if file_exists(main_rs) then
			local orig = io.open(main_rs, "r"):read("*a")
			local header = string.format('fn main() {\n    println!("Hello, %s");\n}\n', author)
			write_file(main_rs, header)
		end
	else
		lfs.mkdir(pname)
		if lang == "python" then
			if PUCK_CONFIG.auto_venv then
				local venv_path = "env"
				local venv_cmd = string.format("cd %s && python3 -m venv %s", pname, venv_path)
				os.execute(venv_cmd)
				print("Python virtual environment created at: " .. pname .. "/env")
			else
				print("Skipping virtualenv creation (auto_venv=false in config)")
			end
		end
		boilerplate(lang, pname, author, created_at)
	end
	write_file(pname .. "/.gitignore", create_gitignore(lang))
	write_readme(pname, lang, author, created_at)
	local meta = {
		name = pname,
		language = lang,
		author = author,
		created_at = created_at,
		dependencies = {},
	}
	write_file(pname .. "/puck.json", json.encode(meta, { indent = true }))
	-- attempt to copy cheatsheet (if available in puck/cheatsheet)
	if not (opts and opts.no_cheatsheet) and PUCK_CONFIG.copy_cheatsheet then
		copy_cheatsheet(pname, lang)
	elseif opts and opts.no_cheatsheet then
		print("Skipping cheatsheet copy (no-cheatsheet flag enabled)")
	else
		print("Skipping cheatsheet copy (disabled in puck_config.yaml)")
	end
	print(string.format("Project '%s' (%s) created by %s at %s.", pname, lang, author, created_at))
end

local function ensure_tool(cmd, install_cmd)
	if os.execute(cmd .. " --version > /dev/null 2>&1") ~= 0 then
		print("Installing " .. cmd .. " ...")
		os.execute(install_cmd)
	end
end

local function run_project(pname)
	local meta = read_json(pname .. "/puck.json")
	-- if not found relative to cwd, also try puck script root (where main.lua lives)
	if not meta then
		local alt = PUCK_ROOT .. "/" .. pname .. "/puck.json"
		meta = read_json(alt)
		if meta then
			-- adjust pname to absolute path used for subsequent commands
			pname = PUCK_ROOT .. "/" .. pname
		end
	end
	if not meta then
		-- fallback: if puck.json exists but json.decode failed, try a crude parse for `"language":"..."`
		if file_exists(pname .. "/puck.json") then
			local f = io.open(pname .. "/puck.json", "r")
			if f then
				local data = f:read("*a")
				f:close()
				local lang = data:match('"language"%s*:%s*"(.-)"')
				if lang then
					meta = { language = lang }
				end
			end
		end
		if not meta then
			if file_exists(pname .. "/Cargo.toml") then
				os.execute("cd " .. pname .. " && cargo run")
			else
				print("No puck.json or Cargo.toml found.")
			end
			return
		end
	end
	local lang = meta.language
	if lang == "python" then
		ensure_tool("python3", "sudo apt-get install python3 -y")
		ensure_tool("pip3", "sudo apt-get install python3-pip -y")
		os.execute("cd " .. pname .. " && python3 main.py")
	elseif lang == "lua" then
		ensure_tool("lua", "sudo apt-get install lua5.4 -y")
		ensure_tool("luarocks", "sudo apt-get install luarocks -y")
		os.execute("cd " .. pname .. " && lua main.lua")
	elseif lang == "cpp" then
		if os.execute("clang++ --version > /dev/null 2>&1") == 0 then
			os.execute("cd " .. pname .. "/src && clang++ main.cpp -o ../main && cd .. && ./main")
		elseif os.execute("g++ --version > /dev/null 2>&1") == 0 then
			os.execute("cd " .. pname .. "/src && g++ main.cpp -o ../main && cd .. && ./main")
		else
			print("Neither clang++ nor g++ is installed.")
		end
	elseif lang == "c" then
		if os.execute("clang --version > /dev/null 2>&1") == 0 then
			os.execute("cd " .. pname .. "/src && clang main.c -o ../main && cd .. && ./main")
		elseif os.execute("gcc --version > /dev/null 2>&1") == 0 then
			os.execute("cd " .. pname .. "/src && gcc main.c -o ../main && cd .. && ./main")
		else
			print("Neither clang nor gcc is installed.")
		end
	elseif lang == "rust" then
		os.execute("cd " .. pname .. " && cargo run")
	elseif lang == "html" then
		os.execute("xdg-open " .. pname .. "/index.html")
	elseif lang == "js" then
		ensure_tool("node", "sudo apt-get install nodejs -y")
		os.execute("cd " .. pname .. " && node main.js")
	elseif lang == "assembly" then
		-- try Makefile first
		if file_exists(pname .. "/Makefile") then
			local ok = os.execute("cd " .. pname .. " && make")
			if ok == 0 then
				os.execute("cd " .. pname .. " && ./main")
			else
				print("Build failed (Makefile). Ensure nasm/ld are installed and Makefile is correct.")
			end
		else
			-- fallback: try nasm + ld directly
			if os.execute("nasm -v > /dev/null 2>&1") == 0 and os.execute("ld --version > /dev/null 2>&1") == 0 then
				local asm = pname .. "/src/main.asm"
				local obj = pname .. "/src/main.o"
				local cmd = string.format("nasm -f elf64 %s -o %s && ld %s -o %s/main", asm, obj, obj, pname)
				local ok = os.execute(cmd)
				if ok == 0 then
					os.execute("cd " .. pname .. " && ./main")
				else
					print("Build failed (nasm/ld). Ensure nasm and ld are available and the assembly file is valid.")
				end
			else
				print("nasm or ld not found. Install nasm and ld (binutils) to build assembly projects.")
			end
		end
	else
		print("Unknown language: " .. lang)
	end
end

local function delete_project(pname)
	-- safety: ensure pname is not empty and not root
	if not pname or pname == "/" or pname == "." or pname == ".." then
		print("Refusing to delete unsafe path: " .. tostring(pname))
		return
	end

	local mode = lfs.attributes(pname, "mode")
	if mode ~= "directory" then
		print("No such project directory: " .. pname)
		return
	end

	local confirm = true
	if PUCK_CONFIG.delete_force then
		confirm = false
	end
	if confirm then
		io.stdout:flush()
		io.write("Are you sure you want to permanently delete project '" .. pname .. "'? (y/n): ")
		local response = io.read()
		if response:lower() ~= "y" then
			print("Deletion cancelled.")
			return
		end
	else
		print("delete_force=true in puck_config.yaml: skipping confirmation")
	end

	-- prefer using a single system rm -rf for speed; include safety check
	local ok = os.execute("rm -rf " .. string.format('%q', pname))
	if ok == 0 then
		print("Project '" .. pname .. "' deleted successfully.")
		return
	end

	-- fallback: recursive delete using lfs if rm failed
	local function rmdir(path)
		for file in lfs.dir(path) do
			if file ~= "." and file ~= ".." then
				local full = path .. "/" .. file
				local m = lfs.attributes(full, "mode")
				if m == "directory" then
					rmdir(full)
				else
					os.remove(full)
				end
			end
		end
		lfs.rmdir(path)
	end

	local status, err = pcall(function() rmdir(pname) end)
	if not status then
		print("Failed to delete project recursively: " .. tostring(err))
	else
		print("Project '" .. pname .. "' deleted successfully.")
	end
end

local function show_copyright()
	print([[
----------------------------------------------------------
Copyright (C) 2025 samsitkarki
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
----------------------------------------------------------
]])
end

if #arg < 1 then
	print("Usage: puck [project name] [language] [--no-cheatsheet] | puck [project name] b | puck [project name] r | puck c | puck config")
	os.exit(1)
end

local pname = arg[1]
local opt = arg[2]

if pname and pname:lower() == "c" then
	show_copyright()
	os.exit(0)
end

if pname and pname:lower() == "config" then
	write_default_config()
	os.exit(0)
end

local third = arg[3]
local opts = { no_cheatsheet = false }
if third == "--no-cheatsheet" or third == "-n" then
	opts.no_cheatsheet = true
end

if opt and opt == "r" then
	delete_project(pname)
elseif opt and opt ~= "b" then
	create_project(pname, opt, opts)
elseif opt == "b" or (not opt and file_exists(pname .. "/puck.json")) then
	run_project(pname)
else
	print("Invalid arguments.")
end
--[basic algorithm of this project:
--listens to puck comand and use sys.argv or arg on lua
--and yk like it takes first argument as project name and second argument as project language
--and it creetes direcotry same as name of project and writes boiler plate of lanugae and does whoami command whoami is a linux command
--that helps to find out linux username of current user eg : mine is samsit and / it creates .js .css file if its html and
--it creates puck.json that has information of author and time it was created on language used depedencies etc
--and if we do puck b then it shows that lisense thingy (ngl i copied copyright from chatgpt)
--and i mean that puck. json has information on other stuff like it supports rust c cpp and downloads compiler if not installlllllllllllled and whenever we do puck b then
--it yk installs depedencies and comiler i fnot installed and runs it and removes project on puck <projectname> r
--thats it
--]
