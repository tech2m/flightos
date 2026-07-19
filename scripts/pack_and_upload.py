import os
import sys
import json
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
    
    startup_path = os.path.join(base_dir, "startup.lua")
    if os.path.exists(startup_path):
        with open(startup_path, "r", encoding="utf-8") as f:
            files_to_pack["startup.lua"] = f.read()
            
    flightos_dir = os.path.join(base_dir, "flightos")
    if os.path.exists(flightos_dir):
        for root, dirs, filenames in os.walk(flightos_dir):
            for filename in filenames:
                if filename.endswith(".lua"):
                    full_path = os.path.join(root, filename)
                    rel_path = os.path.relpath(full_path, base_dir).replace("\\", "/")
                    with open(full_path, "r", encoding="utf-8") as f:
                        files_to_pack[rel_path] = f.read()

    if not files_to_pack:
        print("Error: No files found to pack.")
        sys.exit(1)
        
    print(f"Packed {len(files_to_pack)} files.")
    
    installer_template = """local files = {}

"""
    for rel_path, content in sorted(files_to_pack.items()):
        long_str = get_lua_long_string(content)
        installer_template += f'files["{rel_path}"] = {long_str}\n\n'
        
    installer_template += """print("FlightOS Installer: cleaning up old files...")
local has_config = fs.exists("flightos/config.dat")
if has_config then
    fs.copy("flightos/config.dat", "config.dat.bak")
    print("Backed up config.dat")
end
if fs.exists("flightos") then
    fs.delete("flightos")
    print("Deleted old flightos/ folder")
end
if fs.exists("startup.lua") then
    fs.delete("startup.lua")
    print("Deleted old startup.lua")
end

print("FlightOS Installer: generating directories...")
fs.makeDir("flightos")
fs.makeDir("flightos/apps")

if has_config then
    fs.copy("config.dat.bak", "flightos/config.dat")
    fs.delete("config.dat.bak")
    print("Restored config.dat")
end

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
print("\\nFlightOS installation complete!")
print("Rebooting in 3 seconds to apply all changes...")
sleep(3)
os.reboot()
"""

    installer_path = os.path.join(base_dir, "installer.lua")
    with open(installer_path, "w", encoding="utf-8") as f:
        f.write(installer_template)
    print(f"Locally generated and saved: {installer_path}")
    
    print("\n--- Uploading to paste services ---")
    
    try:
        print("Uploading to dpaste.com...")
        data = urllib.parse.urlencode({
            'content': installer_template,
            'lexer': 'lua',
            'format': 'url',
            'expires': '30days'
        }).encode('utf-8')
        
        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
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
        print(f"Failed to upload to dpaste: {e}")
        
    pastebin_config_path = os.path.join(base_dir, "pastebin_config.json")
    api_key = None
    if os.path.exists(pastebin_config_path):
        try:
            with open(pastebin_config_path, "r") as f:
                cfg = json.load(f)
                api_key = cfg.get("api_dev_key")
        except Exception:
            pass
            
    if api_key:
        try:
            print("Uploading to Pastebin...")
            data = urllib.parse.urlencode({
                'api_dev_key': api_key,
                'api_option': 'paste',
                'api_paste_code': installer_template,
                'api_paste_private': '1',
                'api_paste_name': 'FlightOS Installer',
                'api_paste_expire_date': '1M',
                'api_paste_format': 'lua'
            }).encode('utf-8')
            
            headers = {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
            }
            req = urllib.request.Request("https://pastebin.com/api/api_post.php", data=data, headers=headers)
            with urllib.request.urlopen(req) as response:
                pb_resp = response.read().decode('utf-8').strip()
                if pb_resp.startswith("https://pastebin.com/"):
                    raw_pb = pb_resp.replace("https://pastebin.com/", "https://pastebin.com/raw/")
                    print(f"Success! Pastebin URL: {pb_resp}")
                    print(f"Raw Pastebin URL (for CC): {raw_pb}")
                else:
                    print(f"Pastebin upload failed with response: {pb_resp}")
        except Exception as e:
            print(f"Failed to upload to Pastebin: {e}")
    else:
        print("\nNote: Pastebin upload skipped because no 'api_dev_key' was configured in pastebin_config.json.")

if __name__ == "__main__":
    main()
