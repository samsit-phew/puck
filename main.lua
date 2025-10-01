local json = require("dkjson")
local lfs = require("lfs")

-- determine script directory (where main.lua lives) so we can find the cheatsheet folder
local function script_dir()
	local info = debug.getinfo(1, "S")
	local source = info and info.source or ""
	if source:sub(1, 1) == "@" then
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

# init_git: When true, puck will run `git init` in new projects.
init_git: false

# init_docker: When true, puck will create a basic Dockerfile for new projects.
init_docker: false

# use_docker_run: When true, puck will prefer building/running projects via Docker
# if a Dockerfile is present or when creating projects with --docker flag.
use_docker_run: false

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
				if not f then
					return cfg
				end
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
				if v:lower() == "true" then
					cfg[k] = true
				elseif v:lower() == "false" then
					cfg[k] = false
				else
					cfg[k] = v
				end
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

-- perform lightweight syntax checks for common languages
local function syntax_check(pname)
	local meta = read_json(pname .. "/puck.json")
	if not meta then
		local alt = PUCK_ROOT .. "/" .. pname .. "/puck.json"
		meta = read_json(alt)
		if meta then pname = PUCK_ROOT .. "/" .. pname end
	end
	local lang = nil
	if meta and meta.language then
		lang = meta.language
	end
	if not lang then
		-- try heuristics based on file layout
		if file_exists(pname .. "/main.py") then lang = "python"
		elseif file_exists(pname .. "/main.lua") then lang = "lua"
		elseif file_exists(pname .. "/src/main.c") then lang = "c"
		elseif file_exists(pname .. "/src/main.cpp") then lang = "cpp"
		elseif file_exists(pname .. "/main.ts") or file_exists(pname .. "/src/main.ts") then lang = "ts"
		elseif file_exists(pname .. "/main.js") then lang = "js"
		elseif file_exists(pname .. "/style.css") or file_exists(pname .. "/main.css") then lang = "css"
		elseif file_exists(pname .. "/index.html") then lang = "html"
		elseif file_exists(pname .. "/main.go") or file_exists(pname .. "/src/main.go") then lang = "go"
		else
			-- detect Java by looking for any .java files in src/
			local srcdir = pname .. "/src"
			local ok, attr = pcall(function() return lfs.attributes(srcdir, "mode") end)
			if ok and attr == "directory" then
				for f in lfs.dir(srcdir) do
					if f:match("%.java$") then lang = "java" break end
				end
			end
			if not lang and file_exists(pname .. "/src/main.asm") then lang = "assembly" end
			if not lang and file_exists(pname .. "/Cargo.toml") then lang = "rust" end
		end
	end
	if not lang then
		print("Could not determine project language for syntax check for: " .. pname)
		return
	end
	print("Running syntax check for language: " .. lang)
	if lang == "python" then
		local file = pname .. "/main.py"
		if not file_exists(file) then print("No main.py to check.") return end
		local ok = os.execute("python3 -m py_compile " .. string.format('%q', file) .. " >/dev/null 2>&1")
		if ok == 0 then print("Python syntax OK") else print("Python syntax errors or python3 not available") end
	elseif lang == "lua" then
		local file = pname .. "/main.lua"
		if not file_exists(file) then print("No main.lua to check.") return end
		if os.execute("luac -p " .. string.format('%q', file) .. " >/dev/null 2>&1") == 0 then print("Lua syntax OK") else print("Lua syntax errors or 'luac' not installed") end
	elseif lang == "c" then
		local file = pname .. "/src/main.c"
		if not file_exists(file) then print("No src/main.c to check.") return end
		if os.execute("gcc -fsyntax-only " .. string.format('%q', file) .. " >/dev/null 2>&1") == 0 then print("C syntax OK") else print("C syntax errors or gcc not installed") end
	elseif lang == "cpp" then
		local file = pname .. "/src/main.cpp"
		if not file_exists(file) then print("No src/main.cpp to check.") return end
		if os.execute("g++ -fsyntax-only " .. string.format('%q', file) .. " >/dev/null 2>&1") == 0 then print("C++ syntax OK") else print("C++ syntax errors or g++ not installed") end
	elseif lang == "rust" then
		if not file_exists(pname .. "/Cargo.toml") then print("No Cargo.toml found for Rust project") return end
		if os.execute("cd " .. string.format('%q', pname) .. " && cargo check >/dev/null 2>&1") == 0 then print("Rust syntax OK (cargo check)") else print("Rust check failed or cargo not installed") end
	elseif lang == "js" then
		local file = pname .. "/main.js"
		if not file_exists(file) then print("No main.js to check.") return end
		if os.execute("node --check " .. string.format('%q', file) .. " >/dev/null 2>&1") == 0 then print("JS syntax OK (node --check)") else print("JS syntax errors or node doesn't support --check") end
	elseif lang == "html" then
		local file = pname .. "/index.html"
		if not file_exists(file) then print("No index.html to check.") return end
		if os.execute("tidy -errors -q " .. string.format('%q', file) .. " >/dev/null 2>&1") == 0 then print("HTML looks OK (tidy)") else print("HTML check failed or 'tidy' not installed; file exists") end
	elseif lang == "css" then
		local file = pname .. "/style.css"
		if not file_exists(file) then file = pname .. "/main.css" end
		if not file_exists(file) then print("No style.css/main.css to check.") return end
		if os.execute("stylelint " .. string.format('%q', file) .. " >/dev/null 2>&1") == 0 then print("CSS looks OK (stylelint)")
		elseif os.execute("csslint " .. string.format('%q', file) .. " >/dev/null 2>&1") == 0 then print("CSS looks OK (csslint)")
		else print("CSS check failed or no CSS linter installed (stylelint/csslint)") end
	elseif lang == "ts" then
		local file = pname .. "/main.ts"
		if not file_exists(file) then file = pname .. "/src/main.ts" end
		if not file_exists(file) then print("No main.ts/src/main.ts to check.") return end
		if os.execute("tsc --noEmit " .. string.format('%q', file) .. " >/dev/null 2>&1") == 0 then print("TypeScript syntax OK (tsc)") else print("TypeScript check failed or tsc not installed") end
	elseif lang == "go" then
		local ok = os.execute("cd " .. string.format('%q', pname) .. " && go build ./... >/dev/null 2>&1")
		if ok == 0 then print("Go build OK") else print("Go build failed or go not installed") end
	elseif lang == "java" then
		-- try Makefile (jar) first
		if file_exists(pname .. "/Makefile") then
			local ok = os.execute("cd " .. pname .. " && make")
			if ok == 0 then
				if file_exists(pname .. "/app.jar") then
					os.execute("java -jar " .. pname .. "/app.jar")
					return
				end
			else
				print("Java build failed (Makefile). Ensure javac/jar are installed.")
			end
		end
		if os.execute("javac -version > /dev/null 2>&1") == 0 then
			local srcfiles = pname .. "/src/*.java"
			local ok = os.execute("cd " .. pname .. " && javac " .. srcfiles .. " >/dev/null 2>&1")
			if ok == 0 then
				os.execute("cd " .. pname .. " && java -cp src Main")
			else
				print("javac failed or compile errors present.")
			end
		else
			print("javac not found. Install JDK to build/run Java projects.")
		end
	elseif lang == "assembly" then
		local file = pname .. "/src/main.asm"
		if not file_exists(file) then print("No src/main.asm to check.") return end
		if os.execute("nasm -f elf64 -o /dev/null " .. string.format('%q', file) .. " >/dev/null 2>&1") == 0 then print("Assembly syntax OK (nasm)") else print("Assembly syntax errors or nasm not installed") end
	else
		print("No syntax checker implemented for language: " .. lang)
	end
end

local PUCK_ROOT = script_dir()

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
		java = "*.class\n/bin/\n*.jar\n.DS_Store\n",
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
			java = string.format(
			[[
package %s;

public class Main {
    public static void main(String[] args) {
        System.out.println("Hello, %s");
    }
}
]],
				-- placeholder; package will be omitted when writing file
				"", author
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
		assembly = string.format(
			[[
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
]],
			author
		),
	}
	if lang == "cpp" or lang == "c" or lang == "assembly" then
		lfs.mkdir(pname .. "/src")
		if lang == "cpp" then
			write_file(pname .. "/src/main.cpp", hello.cpp)
		elseif lang == "c" then
			write_file(pname .. "/src/main.c", hello.c)
		elseif lang == "java" then
			-- Java: write Main.java
			local mainjava = string.format([[public class Main {
    public static void main(String[] args) {
        System.out.println("Hello, %s");
    }
}
]], author)
			write_file(pname .. "/src/Main.java", mainjava)
			-- simple Makefile for building jar
			local jmk = [[
JAVAC=javac
JAR=jar
SRC=src
OUT=out
all:
	mkdir -p $(OUT)
	$(JAVAC) -d $(OUT) $(SRC)/*.java
	cd $(OUT) && $(JAR) cf ../app.jar .

clean:
	rm -rf $(OUT) app.jar
]]
			write_file(pname .. "/Makefile", jmk)
		elseif lang == "assembly" then
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
	if not inf then
		return false, "source not found: " .. src
	end
	local data = inf:read("*a")
	inf:close()
	local outf = io.open(dst, "wb")
	if not outf then
		return false, "failed to open dest: " .. dst
	end
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
		java = { "javacheatsheet.pdf" },
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
	if not files then
		return
	end
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

	-- create Dockerfile if requested (cmd-line flag overrides config)
	local want_docker = false
	if opts and opts.init_docker ~= nil then
		want_docker = opts.init_docker
	else
		want_docker = PUCK_CONFIG.init_docker
	end
	if want_docker then
		local df = nil
		if lang == "python" then
			df = [[
FROM python:3.11-slim
WORKDIR /app
COPY . /app
RUN python -m pip install --no-cache-dir -r requirements.txt || true
CMD ["python", "main.py"]
]]
		elseif lang == "lua" then
			df = [[
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y lua5.4
WORKDIR /app
COPY . /app
CMD ["lua", "main.lua"]
]]
		elseif lang == "node" or lang == "js" then
			df = [[
FROM node:18-alpine
WORKDIR /app
COPY . /app
CMD ["node", "main.js"]
]]
		elseif lang == "html" then
			df = [[
FROM nginx:alpine
COPY . /usr/share/nginx/html
CMD ["nginx", "-g", "daemon off;"]
]]
		elseif lang == "assembly" then
			df = [[
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y nasm build-essential
WORKDIR /app
COPY . /app
RUN nasm -f elf64 src/main.asm -o src/main.o && ld src/main.o -o main
CMD ["/app/main"]
]]
		end
		if df then
			write_file(pname .. "/Dockerfile", df)
			print("Created Dockerfile for " .. lang)
		end
	end

	-- init git if requested (cmd-line overrides config)
	local want_git = false
	if opts and opts.init_git ~= nil then
		want_git = opts.init_git
	else
		want_git = PUCK_CONFIG.init_git
	end
	if want_git then
		os.execute("cd " .. pname .. " && git init >/dev/null 2>&1 || true")
		print("Initialized git repository in " .. pname)
	end
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
		-- if Dockerfile exists and config requests docker run, try building and running in docker
		local dockerfile_path = pname .. "/Dockerfile"
		if file_exists(dockerfile_path) and PUCK_CONFIG.use_docker_run then
			local img = "puck_" .. meta.name
			print("Building Docker image: " .. img)
			local ok = os.execute("cd " .. pname .. " && docker build -t " .. img .. " .")
			if ok == 0 then
				os.execute("docker run --rm " .. img)
				return
			else
				print("Docker build failed, falling back to local run.")
			end
		end
		-- use opts passed in (from top-level arg parsing); provide defaults if nil
		opts = opts or { no_cheatsheet = false, init_git = nil, init_docker = nil }
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
	elseif lang == "java" then
		-- try Makefile (jar) first
		if file_exists(pname .. "/Makefile") then
			local ok = os.execute("cd " .. pname .. " && make")
			if ok == 0 then
				if file_exists(pname .. "/app.jar") then
					os.execute("java -jar " .. pname .. "/app.jar")
					return
				end
			else
				print("Java build failed (Makefile). Ensure javac/jar are installed.")
			end
		end
		-- fallback: compile with javac and run
		if os.execute("javac -version > /dev/null 2>&1") == 0 then
			local srcfiles = pname .. "/src/*.java"
			local ok = os.execute("cd " .. pname .. " && javac " .. srcfiles .. " >/dev/null 2>&1")
			if ok == 0 then
				-- try to run Main
				os.execute("cd " .. pname .. " && java -cp src Main")
			else
				print("javac failed or compile errors present.")
			end
		else
			print("javac not found. Install JDK to build/run Java projects.")
		end
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
	local ok = os.execute("rm -rf " .. string.format("%q", pname))
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

	local status, err = pcall(function()
		rmdir(pname)
	end)
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

local function print_help()
	print([[

Usage:
	puck <project> <language> [flags]   Create a new project named <project> in <language>
	puck <project> b                    Build / run the project (or if run from inside project)
	puck <project> r                    Remove (delete) the project directory
	puck <project> s                    Syntax-check the project sources
	puck config                         Create a default puck_config.yaml in PUCK_ROOT
	puck c                              Show license / copyright

Global flags (for create):
	--no-cheatsheet, -n                 Skip copying the language cheatsheet into the project
	--git / --no-git                    Initialize a git repository (overrides config)
	--docker / --no-docker              Create a Dockerfile for the project (overrides config)

Other options:
	--help, -h                          Show this help text
	--gen howtouse                      Generate a short HOWTO file (how_to_use_puck.md)


]])
end

local function gen_howtouse()
	local doc = [[# How to use puck

puck is a tiny, focused tool to scaffold, run, check, and manage small language projects.
It is intentionally lightweight — it creates a minimal project layout, copies local cheatsheets
when available, and helps you build/run or lint the project using common toolchains.

---

## Quick start

Create a new project named `myproj` in Python:

```bash
puck myproj python
```

This will create `myproj/` containing:

- `main.py` — a small hello-world entrypoint
- `puck.json` — metadata (name, language, author, created_at)
- `project_info.yaml` — a tiny README containing the author and timestamp
- `.gitignore` — sensible ignores for the language
- optional cheatsheet PDF copied from `cheatsheet/` (unless disabled)

To run or build the project:

```bash
puck myproj b
```

To delete the project:

```bash
puck myproj r
```

To run a syntax-only check of the project sources:

```bash
puck myproj s
```

---

## Commands (detailed)

- `puck <project> <language> [flags]` — Create a project
  - `<language>` accepts: `python`, `lua`, `c`, `cpp`, `rust`, `js`, `html`, `css`, `assembly`, `java`, `go`, `ts`
  - Example: `puck demo lua --git --docker`

- `puck <project> b` — Build / Run the project
  - The tool will attempt to use sensible defaults to compile/run: `python3`, `lua`, `gcc/g++`, `cargo`, `node`, `nasm`, etc.
  - If a Dockerfile exists and `use_docker_run` is enabled in `puck_config.yaml`, puck will use Docker to build & run.

- `puck <project> s` — Syntax-check the project sources
  - Uses common tools where available:
    - Python: `python3 -m py_compile`
    - Lua: `luac -p`
    - C/C++: `gcc -fsyntax-only` / `g++ -fsyntax-only`
    - Rust: `cargo check`
    - JavaScript: `node --check`
    - HTML: `tidy -errors -q`
    - CSS: `stylelint` or `csslint` (if installed)
    - TypeScript: `tsc --noEmit`
    - Go: `go build` (validates the package)
    - Java: `javac` over `src/*.java`
    - Assembly: `nasm -f elf64` (syntax check)

- `puck <project> r` — Delete the project (prompts for confirmation unless `delete_force: true`)

- `puck config` — Generate a default `puck_config.yaml` in the `puck` root

- `puck --gen howtouse` — Create (or overwrite) `how_to_use_puck.md` in the puck root

---

## Flags (create-time)

- `--no-cheatsheet` / `-n` — Skip copying cheatsheets into the created project.
- `--git` / `--no-git` — Initialize or skip `git init` for the newly created project (overrides config).
- `--docker` / `--no-docker` — Create or skip a basic `Dockerfile` for the project (overrides config).

These flags are processed after the language and project name. Example:

```bash
puck myweb html --no-cheatsheet --docker
```

---

## Configuration (puck_config.yaml)

`puck_config.yaml` lives next to `main.lua` (the `PUCK_ROOT`). Use `puck config` to generate a commented default.

Important keys:

- `copy_cheatsheet` (true/false) — global default for copying cheatsheets on project create
- `auto_venv` (true/false) — if true, Python projects get a `env/` virtualenv created
- `assembly_build` (true/false) — whether assembly projects are built/run automatically
- `init_git` (true/false) — whether to `git init` projects by default
- `init_docker` (true/false) — whether to create a Dockerfile by default
- `use_docker_run` (true/false) — when true, `puck b` prefers Docker for build/run if a Dockerfile is present

---

## Troubleshooting & tips

- Missing tools: syntax checks and builds depend on local toolchains (gcc, rustc/cargo, nasm, node, python3, etc.). The script will print helpful messages when a tool isn't found.
- Windows: puck is written for Unix-like environments. Tools and paths assume Linux/macOS shells.
- Add or customize cheatsheets by placing PDFs in `cheatsheet/` next to `main.lua`. Assembly cheatsheets will copy any file beginning with `assemblycheatsheet`.

## Contributing small fixes

If you want to tweak the behavior (change the Dockerfile templates, extend language checks, or improve the help), edit `main.lua`.

A few useful places to look at in the source:

- `syntax_check(pname)` — controls syntax checking behavior
- `create_project(pname, lang, opts)` — scaffolding and templates
- `run_project(pname)` — build/run dispatch per language

---

If you'd like I can expand this document to include explicit examples per language (commands to compile/run locally and in Docker), CI snippets, or even small tests that validate the syntax checks; tell me which and I'll add them.
# How to use puck

puck is a small helper to scaffold, run, and manage tiny language projects.

Basic commands

- Create a project: `puck myproj python` — creates `myproj/` with `main.py`, `puck.json`, README, and optional cheatsheet.
- Build / Run: `puck myproj b` — builds/runs the project; if you run from inside the project folder, just `puck . b`.
- Delete: `puck myproj r` — asks for confirmation and removes the project directory.
- Syntax check: `puck myproj s` — runs a lightweight syntax check using common toolchains (py_compile, luac, gcc, g++, cargo, node --check, tidy, nasm, etc.).
- Generate config: `puck config` — creates `puck_config.yaml` in the puck directory with toggles for cheatsheets, docker, git, etc.

Flags

- `--no-cheatsheet` / `-n`: don't copy cheatsheets into the created project.
- `--git` / `--no-git`: initialize (or skip) `git init` for the created project.
- `--docker` / `--no-docker`: create (or skip) a basic `Dockerfile` for the project.



]]
	local out = PUCK_ROOT .. "/how_to_use_puck.md"
	write_file(out, doc)
	print("Wrote how-to: " .. out)
end

if #arg < 1 then
	print(
		"Usage: puck [project name] [language] [--no-cheatsheet] | puck [project name] b | puck [project name] r | puck [project name] s | puck c | puck config"
	)
	os.exit(1)
end

local pname = arg[1]
local opt = arg[2]

-- top-level flags: help and generators
for i = 1, #arg do
	if arg[i] == "--help" or arg[i] == "-h" then
		print_help()
		os.exit(0)
	end
	if arg[i] == "--gen" and arg[i + 1] == "howtouse" then
		gen_howtouse()
		os.exit(0)
	end
end

if pname and pname:lower() == "c" then
	show_copyright()
	os.exit(0)
end

if pname and pname:lower() == "config" then
	write_default_config()
	os.exit(0)
end

-- build opts from args (positions >=3)
local global_opts = { no_cheatsheet = false, init_git = nil, init_docker = nil }
for i = 3, #arg do
	local a = arg[i]
	if a == "--no-cheatsheet" or a == "-n" then
		global_opts.no_cheatsheet = true
	end
	if a == "--git" then
		global_opts.init_git = true
	end
	if a == "--no-git" then
		global_opts.init_git = false
	end
	if a == "--docker" then
		global_opts.init_docker = true
	end
	if a == "--no-docker" then
		global_opts.init_docker = false
	end
end

if opt and opt == "r" then
	delete_project(pname)
elseif opt and opt == "s" then
	syntax_check(pname)
elseif opt and opt ~= "b" then
	create_project(pname, opt, global_opts)
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
