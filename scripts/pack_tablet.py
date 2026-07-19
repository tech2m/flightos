import os
import sys
import urllib.request
import urllib.parse

def get_lua_long_string(content):
    equals_count = 4
    while True:
        closing_seq = "]" + "=" * equals_count + "]"
        if closing_seq not in content:
            break
        equals_count += 1
    eq_str = "=" * equals_count
    return f"[{eq_str}[\n{content}]{eq_str}]"

def main():
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except AttributeError:
        pass
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    
    files_to_pack = {}
    
    for filename in ["startup.lua", "remote.lua"]:
        filepath = os.path.join(base_dir, "tablet", filename)
        if os.path.exists(filepath):
            with open(filepath, "r", encoding="utf-8") as f:
                files_to_pack[filename] = f.read()

    if not files_to_pack:
        print("Error: No files found to pack.")
        sys.exit(1)
        
    print(f"Packed {len(files_to_pack)} files.")
    
    installer_template = """local files = {}

"""
    for rel_path, content in sorted(files_to_pack.items()):
        long_str = get_lua_long_string(content)
        installer_template += f'files["{rel_path}"] = {long_str}\n\n'
        
    installer_template += """print("FlightOS Remote Installer")
print("========================")

for path, content in pairs(files) do
    local f = fs.open(path, "w")
    if f then
        f.write(content)
        f.close()
        print("Installed: " .. path)
    else
        print("Failed to write: " .. path)
    end
end
print("")
print("Installation complete!")
print("Rebooting in 3 seconds...")
sleep(3)
os.reboot()
"""

    installer_path = os.path.join(base_dir, "tablet", "installer.lua")
    with open(installer_path, "w", encoding="utf-8") as f:
        f.write(installer_template)
    print(f"Locally saved: {installer_path}")
    
    print("\n--- Uploading to dpaste.com ---")
    try:
        data = urllib.parse.urlencode({
            'content': installer_template,
            'lexer': 'lua',
            'format': 'url',
            'expires': '30days'
        }).encode('utf-8')
        
        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
            'Content-Type': 'application/x-www-form-urlencoded'
        }
        req = urllib.request.Request("https://dpaste.com/api/", data=data, headers=headers)
        with urllib.request.urlopen(req) as response:
            dpaste_url = response.read().decode('utf-8').strip()
            if not dpaste_url.endswith(".txt"):
                if dpaste_url.endswith("/"):
                    dpaste_url = dpaste_url[:-1]
                dpaste_url += ".txt"
            print(f"Success! dpaste URL (raw): {dpaste_url}")
    except Exception as e:
        print(f"dpaste upload failed: {e}")

if __name__ == "__main__":
    main()
