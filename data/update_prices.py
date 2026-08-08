import urllib.request
import ssl
import csv
import io
import os

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

url = 'https://docs.google.com/spreadsheets/d/1VezKZkoRFzTnB0hLpTroTRFG40NH5vEpfMjWtWCCXIc/export?format=csv&gid=520277830'
req = urllib.request.Request(url)
with urllib.request.urlopen(req, context=ctx) as response:
    text = response.read().decode('utf-8')

reader = csv.reader(io.StringIO(text))
next(reader) # skip header

lua_output = "local AH_PRICES = {\n"

for row in reader:
    if not row or not row[0].isdigit():
        continue
    item_id = row[0]
    avg24 = row[2]
    avg7 = row[4]
    avg30 = row[6]
    
    # Prioritiza 7d, depois 30d, depois 24h average
    price = avg7 if avg7 else (avg30 if avg30 else avg24)
    
    # Strip any non-numeric characters (like 'g') except for decimal points
    price = ''.join(c for c in price if c.isdigit() or c == '.')
    
    if price:
        lua_output += f"    [{item_id}] = {{ average = {price} }},\n"

lua_output += "}\nreturn AH_PRICES\n"

current_dir = os.path.dirname(os.path.abspath(__file__))
out_file = os.path.join(current_dir, "auction_house_prices.lua")

with open(out_file, "w", encoding="utf-8") as f:
    f.write(lua_output)
    
print("Prices updated successfully.")
