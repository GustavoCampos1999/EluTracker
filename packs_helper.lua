packs_helper = {}

local zonesInfo = {
    [1] = "Gweonid",
    [2] = "Marianople",
    [3] = "Dewstone",
    [4] = "Solis",
    [5] = "Solzreed",
    [6] = "Lilyut",
    [7] = "Arcum",
    [8] = "Two Crowns",
    [9] = "Mahadevi",
    [10] = "Airain",
    [11] = "Falcorth",
    [12] = "Villanelle",
    [13] = "Sunbite",
    [14] = "Windscour",
    [15] = "Perinoor",
    [16] = "Rookborne",
    [17] = "Ynystere",
    [18] = "White Arden",
    [19] = "Karkasse",
    [20] = "Cinderstone",
    [21] = "Aubre Cradle",
    [22] = "Halcyona",
    [23] = "Hasla",
    [24] = "Tigerspine",
    [25] = "Silent Forest",
    [26] = "Hellswamp",
    [27] = "Sanddeep",
    [93] = "Ahnimar",
    [99] = "Rokhala"
}
packs_helper.zonesInfo = zonesInfo

local zoneIds = {
    ["Gweonid Forest"] = 1,
    ["Marianople"] = 2,
    ["Dewstone Plains"] = 3,
    ["Solis Headlands"] = 4,
    ["Solzreed Peninsula"] = 5,
    ["Lilyut Hills"] = 6,
    ["Arcum Iris"] = 7,
    ["Two Crowns"] = 8,
    ["Mahadevi"] = 9,
    ["Airain Rock"] = 10,
    ["Falcorth Plains"] = 11,
    ["Villanelle"] = 12,
    ["Sunbite Wilds"] = 13,
    ["Windscour Savannah"] = 14,
    ["Perinoor Ruins"] = 15,
    ["Rookborne Basin"] = 16,
    ["Ynystere"] = 17,
    ["White Arden"] = 18,
    ["Karkasse Ridgelands"] = 19,
    ["Cinderstone Moor"] = 20,
    ["Aubre Cradle"] = 21,
    ["Halcyona"] = 22,
    ["Hasla"] = 23,
    ["Tigerspine Mountains"] = 24,
    ["Silent Forest"] = 25,
    ["Hellswamp"] = 26,
    ["Sanddeep"] = 27,
    ["Ahnimar"] = 93,
    ["Rokhala Mountains"] = 99
}

function packs_helper:GetZoneIdByName(zoneName)
    if zoneName[zoneName] ~= nil then
        return zoneIds[zoneName]
    else
        return nil
    end
end

local packRecipes = {
}

local packsInfo = {
    [20090] = { name = "Solzreed Aged Cordial", zone = 0, destinations = {

    }},
    [20091] = { name = "Gweonid Willow Arrows", zone = 0, destinations = {

    }},
    [20093] = { name = "Arcum Iris Seed Oil", zone = 0, destinations = {

    }},
    [20094] = { name = "Falcorth Tanned Leather", zone = 0, destinations = {

    }},
    [20096] = { name = "Original Lilyut Anvil Casts", zone = 0, destinations = {

    }},
    [20098] = { name = "Tigerspine Mastercraft Ingots", zone = 0, destinations = {

    }},
    [20099] = { name = "Dewstone Plains Rainbow Dye", zone = 0, destinations = {

    }},
    [20100] = { name = "Mahadevi Finest Rubber", zone = 0, destinations = {

    }},
    [20101] = { name = "White Arden Silver Lumber", zone = 0, destinations = {

    }},
    [20102] = { name = "Solis Golden Spice", zone = 0, destinations = {

    }},
    [20103] = { name = "Marianople Embroidered Fabric", zone = 0, destinations = {

    }},
    [20104] = { name = "Villanelle Aged Cordial", zone = 0, destinations = {

    }},
    [20105] = { name = "Two Crowns First Harvest Tea", zone = 0, destinations = {

    }},
    [20106] = { name = "Silent Forest Ship Lumber", zone = 0, destinations = {

    }},
    [20107] = { name = "Cinderstone Shock Absorber", zone = 0, destinations = {

    }},
    [20108] = { name = "Ynystere Starshard Spice", zone = 0, destinations = {

    }},
    [20109] = { name = "Halcyona Organic Grains", zone = 0, destinations = {

    }},
    [20110] = { name = "Hellswamp Spore Farm Wood", zone = 0, destinations = {

    }},
    [20111] = { name = "Sanddeep Seafood Jerky", zone = 0, destinations = {

    }},
    [20112] = { name = "Rookborne Basin Amber Spirits", zone = 0, destinations = {

    }},
    [20113] = { name = "Windscour Alchemical Catalyst", zone = 0, destinations = {

    }},
    [20114] = { name = "Perinoor Moonshine", zone = 0, destinations = {

    }},
    [20115] = { name = "Hasla Light Synthetic Fiber", zone = 0, destinations = {

    }},
    [24920] = { name = "Solzreed Strawberry Jam", zone = 0, destinations = {

    }},
    [24921] = { name = "Solzreed Acorn Jelly", zone = 0, destinations = {

    }},
    [24922] = { name = "Gweonid Grilled Goose", zone = 0, destinations = {

    }},
    [24923] = { name = "Gweonid Goose Down", zone = 0, destinations = {

    }},
    [24924] = { name = "Arcum Iris Dried Seed", zone = 0, destinations = {

    }},
    [24925] = { name = "Arcum Iris Turmeric Powder", zone = 0, destinations = {

    }},
    [24926] = { name = "Falcorth Plains Clover Feed", zone = 0, destinations = {

    }},
    [24927] = { name = "Falcorth Plains Bedding", zone = 0, destinations = {

    }},
    [24928] = { name = "Lilyut Alchemy Catalyst", zone = 0, destinations = {

    }},
    [24929] = { name = "Lilyut Square Bricks", zone = 0, destinations = {

    }},
    [24930] = { name = "Tigerspine Souvenirs", zone = 0, destinations = {

    }},
    [24931] = { name = "Tigerspine Round Bricks", zone = 0, destinations = {

    }},
    [24932] = { name = "Dewstone Corn Meal", zone = 0, destinations = {

    }},
    [24933] = { name = "Dewstone Petal Dye", zone = 0, destinations = {

    }},
    [24934] = { name = "Mahadevi Banana Nectar", zone = 0, destinations = {

    }},
    [24935] = { name = "Mahadevi Straight-Grain Plywood", zone = 0, destinations = {

    }},
    [24936] = { name = "White Arden Plywood", zone = 0, destinations = {

    }},
    [24937] = { name = "White Arden Pinecone Powder", zone = 0, destinations = {

    }},
    [24938] = { name = "Solis Saffron", zone = 0, destinations = {

    }},
    [24939] = { name = "Solis Dried Rosemary", zone = 0, destinations = {

    }},
    [24940] = { name = "Marianople Wool", zone = 0, destinations = {

    }},
    [24941] = { name = "Marianople Facial Cleanser", zone = 0, destinations = {

    }},
    [24942] = { name = "Villanelle Sticky Rice Snack", zone = 0, destinations = {

    }},
    [24943] = { name = "Villanelle Crusty Bread", zone = 0, destinations = {

    }},
    [24944] = { name = "Two Crowns Lemon Juice", zone = 0, destinations = {

    }},
    [24945] = { name = "Two Crowns Lavender Candy", zone = 0, destinations = {

    }},
    [24946] = { name = "Silent Forest Pinecone Sap", zone = 0, destinations = {

    }},
    [24947] = { name = "Silent Forest Dye", zone = 0, destinations = {

    }},
    [24948] = { name = "Cinderstone Airtight Stopper", zone = 0, destinations = {

    }},
    [24949] = { name = "Cinderstone Metal Trim", zone = 0, destinations = {

    }},
    [24950] = { name = "Ynystere Floral Bouquets", zone = 0, destinations = {

    }},
    [24951] = { name = "Ynystere Ceremonial Bouquets", zone = 0, destinations = {

    }},
    [24952] = { name = "Halcyona Coarse Flour", zone = 0, destinations = {

    }},
    [24953] = { name = "Halcyona Fine Flour", zone = 0, destinations = {

    }},
    [24954] = { name = "Hellswamp Mushroom Sauce", zone = 0, destinations = {

    }},
    [24955] = { name = "Hellswamp Sawdust Shavings", zone = 0, destinations = {

    }},
    [24956] = { name = "Sanddeep Powdered Pearl", zone = 0, destinations = {

    }},
    [24957] = { name = "Sanddeep Alchemic Pearls", zone = 0, destinations = {

    }},
    [24958] = { name = "Rookborne Carrot Ale", zone = 0, destinations = {

    }},
    [24959] = { name = "Rookborne Basin Mead", zone = 0, destinations = {

    }},
    [24960] = { name = "Windscour Miracle Capsule", zone = 0, destinations = {

    }},
    [24961] = { name = "Windscour Peppermints", zone = 0, destinations = {

    }},
    [24962] = { name = "Perinoor Peanut Butter", zone = 0, destinations = {

    }},
    [24963] = { name = "Perinoor All-Spice", zone = 0, destinations = {

    }},
    [26096] = { name = "Hasla Treated Bamboo", zone = 0, destinations = {

    }},
    [26097] = { name = "Hasla Duck Down", zone = 0, destinations = {

    }},
    [26472] = { name = "Solzreed Handicrafts Basket", zone = 0, destinations = {

    }},
    [26473] = { name = "Gweonid Bug Repellent Wood", zone = 0, destinations = {

    }},
    [26474] = { name = "Arcum Iris Red Leather Pack", zone = 0, destinations = {

    }},
    [26475] = { name = "Falcorth Dried Yams", zone = 0, destinations = {

    }},
    [26476] = { name = "Lilyut Special Spice", zone = 0, destinations = {

    }},
    [26477] = { name = "Tigerspine Tomato Juice", zone = 0, destinations = {

    }},
    [26478] = { name = "Dewstone Plains Onion Juice", zone = 0, destinations = {

    }},
    [26479] = { name = "Mahadevi Cold Processed Fabric", zone = 0, destinations = {

    }},
    [26480] = { name = "White Arden Steamed Pumpkin", zone = 0, destinations = {

    }},
    [26481] = { name = "Solis Fried Jujube", zone = 0, destinations = {

    }},
    [26482] = { name = "Marianople Orange Drink", zone = 0, destinations = {

    }},
    [26483] = { name = "Villanelle Candied Apples", zone = 0, destinations = {

    }},
    [26484] = { name = "Two Crowns Dried Seaweed", zone = 0, destinations = {

    }},
    [26485] = { name = "Silent Forest Aged Garlic", zone = 0, destinations = {

    }},
    [26486] = { name = "Cinderstone Pickled Olives", zone = 0, destinations = {

    }},
    [26487] = { name = "Ynystere Dried Tomatoes", zone = 0, destinations = {

    }},
    [26488] = { name = "Halcyona Anesthetic", zone = 0, destinations = {

    }},
    [26489] = { name = "Hellswamp Boiled Potatoes", zone = 0, destinations = {

    }},
    [26490] = { name = "Sanddeep Fragrant Wood", zone = 0, destinations = {

    }},
    [26491] = { name = "Rookborne Pumpkin Juice", zone = 0, destinations = {

    }},
    [26492] = { name = "Windscour Regenerating Cream", zone = 0, destinations = {

    }},
    [26493] = { name = "Perinoor Snack Pack", zone = 0, destinations = {

    }},
    [26494] = { name = "Hasla Grilled Yams", zone = 0, destinations = {

    }},
    [31831] = { name = "Gweonid Dyed Feathers", zone = 0, destinations = {

    }},
    [31832] = { name = "Marianople Duck Down", zone = 0, destinations = {

    }},
    [31833] = { name = "Dewstone Fine Thread", zone = 0, destinations = {

    }},
    [31834] = { name = "Solzreed Braised Meat", zone = 0, destinations = {

    }},
    [31835] = { name = "White Arden Trail Mix", zone = 0, destinations = {

    }},
    [31836] = { name = "Lilyut Milk Soap", zone = 0, destinations = {

    }},
    [31837] = { name = "Two Crowns Cream", zone = 0, destinations = {

    }},
    [31838] = { name = "Hellswamp Spicy Meat", zone = 0, destinations = {

    }},
    [31839] = { name = "Cinderstone Tart Mead", zone = 0, destinations = {

    }},
    [31840] = { name = "Halcyona Wheat Biscuit", zone = 0, destinations = {

    }},
    [31841] = { name = "Sanddeep Medicinal Poultice", zone = 0, destinations = {

    }},
    [31842] = { name = "Solis Alchemy Oil", zone = 0, destinations = {

    }},
    [31843] = { name = "Arcum Iris Roasted Eggs", zone = 0, destinations = {

    }},
    [31844] = { name = "Mahadevi Elephant Cookies", zone = 0, destinations = {

    }},
    [31845] = { name = "Falcorth Snowlion Yarn", zone = 0, destinations = {

    }},
    [31846] = { name = "Tigerspine Tigerspaw Pancakes", zone = 0, destinations = {

    }},
    [31847] = { name = "Silent Forest Dried Fruit", zone = 0, destinations = {

    }},
    [31848] = { name = "Villanelle Potpourri", zone = 0, destinations = {

    }},
    [31849] = { name = "Windscour Hearty Jerky", zone = 0, destinations = {

    }},
    [31850] = { name = "Perinoor Aged Spices", zone = 0, destinations = {

    }},
    [31851] = { name = "Rookborne Biscuit Sticks", zone = 0, destinations = {

    }},
    [31852] = { name = "Ynystere Preserves", zone = 0, destinations = {

    }},
    [31853] = { name = "Hasla Softened Fabric", zone = 0, destinations = {

    }},
    [31854] = { name = "Gweonid Apple Pies", zone = 0, destinations = {

    }},
    [31855] = { name = "Marianople Sweeteners", zone = 0, destinations = {

    }},
    [31856] = { name = "Dewstone Distilled Liquor", zone = 0, destinations = {

    }},
    [31857] = { name = "Solzreed Dried Food", zone = 0, destinations = {

    }},
    [31858] = { name = "White Arden Figgy Pudding", zone = 0, destinations = {

    }},
    [31859] = { name = "Lilyut Cooking Oil", zone = 0, destinations = {

    }},
    [31860] = { name = "Two Crowns Pomme Cakes", zone = 0, destinations = {

    }},
    [31861] = { name = "Hellswamp Mushroom Pot Pies", zone = 0, destinations = {

    }},
    [31862] = { name = "Cinderstone Sacred Candles", zone = 0, destinations = {

    }},
    [31863] = { name = "Halcyona Yam Pasta", zone = 0, destinations = {

    }},
    [31864] = { name = "Sanddeep Preserved Meat", zone = 0, destinations = {

    }},
    [31865] = { name = "Solis Juice Concentrate", zone = 0, destinations = {

    }},
    [31866] = { name = "Arcum Iris Lavaspice", zone = 0, destinations = {

    }},
    [31867] = { name = "Mahadevi Root Herbs", zone = 0, destinations = {

    }},
    [31868] = { name = "Falcorth Apple Tarts", zone = 0, destinations = {

    }},
    [31869] = { name = "Tigerspine Grape Jam", zone = 0, destinations = {

    }},
    [31870] = { name = "Silent Forest Pomme Candy", zone = 0, destinations = {

    }},
    [31871] = { name = "Villanelle Preserved Cherries", zone = 0, destinations = {

    }},
    [31872] = { name = "Windscour Bitter Herbs", zone = 0, destinations = {

    }},
    [31873] = { name = "Perinoor Potato Powder", zone = 0, destinations = {

    }},
    [31874] = { name = "Rookborne Fruit Leather", zone = 0, destinations = {

    }},
    [31875] = { name = "Ynystere Olive Oil", zone = 0, destinations = {

    }},
    [31876] = { name = "Hasla Cured Meat", zone = 0, destinations = {

    }},
    [31894] = { name = "Gweonid Piquant Spices", zone = 0, destinations = {

    }},
    [31895] = { name = "Marianople Face Cream", zone = 0, destinations = {

    }},
    [31896] = { name = "Dewstone Plains Toy Robots", zone = 0, destinations = {

    }},
    [31897] = { name = "Solzreed Strawberry Smoothies", zone = 0, destinations = {

    }},
    [31898] = { name = "White Arden Grilled Meat", zone = 0, destinations = {

    }},
    [31899] = { name = "Lilyut Barley Moonshine", zone = 0, destinations = {

    }},
    [31900] = { name = "Two Crowns Flowerpots", zone = 0, destinations = {

    }},
    [31901] = { name = "Hellswamp Ground Peanuts", zone = 0, destinations = {

    }},
    [31902] = { name = "Cinderstone Medicinal Powder", zone = 0, destinations = {

    }},
    [31903] = { name = "Halcyona Livestock Feed", zone = 0, destinations = {

    }},
    [31904] = { name = "Sanddeep Fried Cucumbers", zone = 0, destinations = {

    }},
    [31905] = { name = "Solis Red Spice", zone = 0, destinations = {

    }},
    [31906] = { name = "Arcum Iris Salt Crackers", zone = 0, destinations = {

    }},
    [31907] = { name = "Mahadevi Pickles", zone = 0, destinations = {

    }},
    [31908] = { name = "Falcorth Fertilizer", zone = 0, destinations = {

    }},
    [31909] = { name = "Tigerspine Seasoned Meat", zone = 0, destinations = {

    }},
    [31910] = { name = "Silent Forest Seasonings", zone = 0, destinations = {

    }},
    [31911] = { name = "Villanelle Long Noodles", zone = 0, destinations = {

    }},
    [31912] = { name = "Windscour Chilled Beverages", zone = 0, destinations = {

    }},
    [31913] = { name = "Perinoor Fried Meat", zone = 0, destinations = {

    }},
    [31914] = { name = "Rookborne Corn Hash", zone = 0, destinations = {

    }},
    [31915] = { name = "Ynystere Bouquets", zone = 0, destinations = {

    }},
    [31916] = { name = "Hasla Specialty Tea", zone = 0, destinations = {

    }},
    [32066] = { name = "Gweonid Aged Honey", zone = 0, destinations = {

    }},
    [32067] = { name = "Solzreed Aged Honey", zone = 0, destinations = {

    }},
    [32068] = { name = "Two Crowns Aged Honey", zone = 0, destinations = {

    }},
    [32069] = { name = "Halcyona Aged Honey", zone = 0, destinations = {

    }},
    [32070] = { name = "Solis Aged Honey", zone = 0, destinations = {

    }},
    [32071] = { name = "Falcorth Aged Honey", zone = 0, destinations = {

    }},
    [32072] = { name = "Villanelle Aged Honey", zone = 0, destinations = {

    }},
    [32073] = { name = "Rookborne Aged Honey", zone = 0, destinations = {

    }},
    [32076] = { name = "Dewstone Aged Salve", zone = 0, destinations = {

    }},
    [32077] = { name = "Lilyut Aged Salve", zone = 0, destinations = {

    }},
    [32078] = { name = "Cinderstone Aged Salve", zone = 0, destinations = {

    }},
    [32079] = { name = "Mahadevi Aged Salve", zone = 0, destinations = {

    }},
    [32080] = { name = "Silent Forest Aged Salve", zone = 0, destinations = {

    }},
    [32081] = { name = "Perinoor Aged Salve", zone = 0, destinations = {

    }},
    [32082] = { name = "Hasla Aged Salve", zone = 0, destinations = {

    }},
    [32085] = { name = "Marianople Aged Cheese", zone = 0, destinations = {

    }},
    [32086] = { name = "White Arden Aged Cheese", zone = 0, destinations = {

    }},
    [32087] = { name = "Hellswamp Aged Cheese", zone = 0, destinations = {

    }},
    [32088] = { name = "Sanddeep Aged Cheese", zone = 0, destinations = {

    }},
    [32089] = { name = "Arcum Iris Aged Cheese", zone = 0, destinations = {

    }},
    [32090] = { name = "Tigerspine Aged Cheese", zone = 0, destinations = {

    }},
    [32091] = { name = "Windscour Aged Cheese", zone = 0, destinations = {

    }},
    [32092] = { name = "Ynystere Aged Cheese", zone = 0, destinations = {

    }},
    [34159] = { name = "Dewstone Aged Honey", zone = 0, destinations = {

    }},
    [34160] = { name = "Lilyut Aged Honey", zone = 0, destinations = {

    }},
    [34161] = { name = "Cinderstone Aged Honey", zone = 0, destinations = {

    }},
    [34162] = { name = "Mahadevi Aged Honey", zone = 0, destinations = {

    }},
    [34163] = { name = "Silent Forest Aged Honey", zone = 0, destinations = {

    }},
    [34164] = { name = "Perinoor Aged Honey", zone = 0, destinations = {

    }},
    [34165] = { name = "Hasla Aged Honey", zone = 0, destinations = {

    }},
    [34168] = { name = "Marianople Aged Honey", zone = 0, destinations = {

    }},
    [34169] = { name = "White Arden Aged Honey", zone = 0, destinations = {

    }},
    [34170] = { name = "Hellswamp Aged Honey", zone = 0, destinations = {

    }},
    [34171] = { name = "Sanddeep Aged Honey", zone = 0, destinations = {

    }},
    [34172] = { name = "Arcum Iris Aged Honey", zone = 0, destinations = {

    }},
    [34173] = { name = "Tigerspine Aged Honey", zone = 0, destinations = {

    }},
    [34174] = { name = "Windscour Aged Honey", zone = 0, destinations = {

    }},
    [34175] = { name = "Ynystere Aged Honey", zone = 0, destinations = {

    }},
    [34178] = { name = "Gweonid Aged Salve", zone = 0, destinations = {

    }},
    [34179] = { name = "Solzreed Aged Salve", zone = 0, destinations = {

    }},
    [34180] = { name = "Two Crowns Aged Salve", zone = 0, destinations = {

    }},
    [34181] = { name = "Halcyona Aged Salve", zone = 0, destinations = {

    }},
    [34182] = { name = "Solis Aged Salve", zone = 0, destinations = {

    }},
    [34183] = { name = "Falcorth Aged Salve", zone = 0, destinations = {

    }},
    [34184] = { name = "Villanelle Aged Salve", zone = 0, destinations = {

    }},
    [34185] = { name = "Rookborne Aged Salve", zone = 0, destinations = {

    }},
    [34188] = { name = "Marianople Aged Salve", zone = 0, destinations = {

    }},
    [34189] = { name = "White Arden Aged Salve", zone = 0, destinations = {

    }},
    [34190] = { name = "Hellswamp Aged Salve", zone = 0, destinations = {

    }},
    [34191] = { name = "Sanddeep Aged Salve", zone = 0, destinations = {

    }},
    [34192] = { name = "Arcum Iris Aged Salve", zone = 0, destinations = {

    }},
    [34193] = { name = "Tigerspine Aged Salve", zone = 0, destinations = {

    }},
    [34194] = { name = "Windscour Aged Salve", zone = 0, destinations = {

    }},
    [34195] = { name = "Ynystere Aged Salve", zone = 0, destinations = {

    }},
    [34198] = { name = "Gweonid Aged Cheese", zone = 0, destinations = {

    }},
    [34199] = { name = "Solzreed Aged Cheese", zone = 0, destinations = {

    }},
    [34200] = { name = "Two Crowns Aged Cheese", zone = 0, destinations = {

    }},
    [34201] = { name = "Halcyona Aged Cheese", zone = 0, destinations = {

    }},
    [34202] = { name = "Solis Aged Cheese", zone = 0, destinations = {

    }},
    [34203] = { name = "Falcorth Aged Cheese", zone = 0, destinations = {

    }},
    [34204] = { name = "Villanelle Aged Cheese", zone = 0, destinations = {

    }},
    [34205] = { name = "Rookborne Aged Cheese", zone = 0, destinations = {

    }},
    [34208] = { name = "Dewstone Aged Cheese", zone = 0, destinations = {

    }},
    [34209] = { name = "Lilyut Aged Cheese", zone = 0, destinations = {

    }},
    [34210] = { name = "Cinderstone Aged Cheese", zone = 0, destinations = {

    }},
    [34211] = { name = "Mahadevi Aged Cheese", zone = 0, destinations = {

    }},
    [34212] = { name = "Silent Forest Aged Cheese", zone = 0, destinations = {

    }},
    [34213] = { name = "Perinoor Aged Cheese", zone = 0, destinations = {

    }},
    [34214] = { name = "Hasla Aged Cheese", zone = 0, destinations = {

    }},
    [35297] = { name = "Whirlpool Isle Refined Crystal", zone = 0, destinations = {

    }},
    [35820] = { name = "Delphinad Register", zone = 0, destinations = {

    }},
    [35821] = { name = "Fine Delphinad Pottery", zone = 0, destinations = {

    }},
    [35822] = { name = "Perdita Statue Torso", zone = 0, destinations = {

    }},
    [37465] = { name = "Gweonid Fertilizer", zone = 0, destinations = {

    }},
    [37466] = { name = "Marianople Fertilizer", zone = 0, destinations = {

    }},
    [37467] = { name = "Dewstone Fertilizer", zone = 0, destinations = {

    }},
    [37468] = { name = "Solzreed Fertilizer", zone = 0, destinations = {

    }},
    [37469] = { name = "White Arden Fertilizer", zone = 0, destinations = {

    }},
    [37470] = { name = "Lilyut Hills Fertilizer", zone = 0, destinations = {

    }},
    [37471] = { name = "Two Crowns Fertilizer", zone = 0, destinations = {

    }},
    [37472] = { name = "Hellswamp Fertilizer", zone = 0, destinations = {

    }},
    [37473] = { name = "Cinderstone Fertilizer", zone = 0, destinations = {

    }},
    [37474] = { name = "Halcyona Fertilizer", zone = 0, destinations = {

    }},
    [37475] = { name = "Sanddeep Fertilizer", zone = 0, destinations = {

    }},
    [37476] = { name = "Solis Fertilizer", zone = 0, destinations = {

    }},
    [37477] = { name = "Arcum Iris Fertilizer", zone = 0, destinations = {

    }},
    [37478] = { name = "Mahadevi Fertilizer", zone = 0, destinations = {

    }},
    [37479] = { name = "Falcorth Fertilizer", zone = 0, destinations = {

    }},
    [37480] = { name = "Tigerspine Fertilizer", zone = 0, destinations = {

    }},
    [37481] = { name = "Silent Forest Fertilizer", zone = 0, destinations = {

    }},
    [37482] = { name = "Villanelle Fertilizer", zone = 0, destinations = {

    }},
    [37484] = { name = "Windscour Fertilizer", zone = 0, destinations = {

    }},
    [37485] = { name = "Perinoor Fertilizer", zone = 0, destinations = {

    }},
    [37486] = { name = "Rookborne Fertilizer", zone = 0, destinations = {

    }},
    [37487] = { name = "Ynystere Fertilizer", zone = 0, destinations = {

    }},
    [37488] = { name = "Hasla Fertilizer", zone = 0, destinations = {

    }},
    [39379] = { name = "Delphinad Ghost Ship Stone Slab", zone = 0, destinations = {

    }},
    [39633] = { name = "Basic Cargo Pack", zone = 0, destinations = {

    }},
    [39634] = { name = "Luxury Porcelain Cargo Pack", zone = 0, destinations = {

    }},
    [39635] = { name = "Rare Wine Cargo Pack", zone = 0, destinations = {

    }},
    [39636] = { name = "Ancient Literature Cargo Pack", zone = 0, destinations = {

    }},
    [40532] = { name = "Exeloch Organic Gems", zone = 0, destinations = {

    }},
    [40533] = { name = "Nuimari Dried Roots", zone = 0, destinations = {

    }},
    [40534] = { name = "Calmlands Fern Salad", zone = 0, destinations = {

    }},
    [40535] = { name = "Heedmar Scented Oils", zone = 0, destinations = {

    }},
    [40536] = { name = "Sungold Thorn Combs", zone = 0, destinations = {

    }},
    [40537] = { name = "Marcala Scented Candles", zone = 0, destinations = {

    }},
    [41982] = { name = "Airain Dream Catchers", zone = 0, destinations = {

    }},
    [41983] = { name = "Airain Triple Stout", zone = 0, destinations = {

    }},
    [41984] = { name = "Airain Vegetable Seasoning", zone = 0, destinations = {

    }},
    [41985] = { name = "Airain Fertilizer", zone = 0, destinations = {

    }},
    [41986] = { name = "Aubre Cradle Rice Flour", zone = 0, destinations = {

    }},
    [41987] = { name = "Aubre Cradle Ethanol", zone = 0, destinations = {

    }},
    [41988] = { name = "Aubre Cradle Deviled Eggs", zone = 0, destinations = {

    }},
    [41989] = { name = "Aubre Cradle Fertilizer", zone = 0, destinations = {

    }},
    [41990] = { name = "Ahnimar Hangover Cure", zone = 0, destinations = {

    }},
    [41991] = { name = "Ahnimar Mushroom Roulette", zone = 0, destinations = {

    }},
    [41992] = { name = "Ahnimar Pressed Powder", zone = 0, destinations = {

    }},
    [41993] = { name = "Ahnimar Fertilizer", zone = 0, destinations = {

    }},
    [41994] = { name = "Karkasse Quilts", zone = 0, destinations = {

    }},
    [41995] = { name = "Karkasse Dragon Jerky", zone = 0, destinations = {

    }},
    [41996] = { name = "Karkasse Burn Cream", zone = 0, destinations = {

    }},
    [41997] = { name = "Karkasse Fertilizer", zone = 0, destinations = {

    }},
    [41998] = { name = "Sunbite Citrus Cleaner", zone = 0, destinations = {

    }},
    [41999] = { name = "Sunbite Salvation Tea", zone = 0, destinations = {

    }},
    [42000] = { name = "Sunbite Pest Poison", zone = 0, destinations = {

    }},
    [42001] = { name = "Sunbite Fertilizer", zone = 0, destinations = {

    }},
    [42002] = { name = "Rokhala Alpine Mix", zone = 0, destinations = {

    }},
    [42003] = { name = "Rokhala Auspicious Elixir", zone = 0, destinations = {

    }},
    [42004] = { name = "Rokhala Livestock Fodder", zone = 0, destinations = {

    }},
    [42005] = { name = "Rokhala Fertilizer", zone = 0, destinations = {

    }},
    [42006] = { name = "Airain Aged Honey", zone = 0, destinations = {

    }},
    [42007] = { name = "Aubre Cradle Aged Honey", zone = 0, destinations = {

    }},
    [42008] = { name = "Ahnimar Aged Honey", zone = 0, destinations = {

    }},
    [42009] = { name = "Karkasse Aged Honey", zone = 0, destinations = {

    }},
    [42010] = { name = "Sunbite Aged Honey", zone = 0, destinations = {

    }},
    [42011] = { name = "Rokhala Aged Honey", zone = 0, destinations = {

    }},
    [42012] = { name = "Airain Aged Salve", zone = 0, destinations = {

    }},
    [42013] = { name = "Aubre Cradle Aged Salve", zone = 0, destinations = {

    }},
    [42014] = { name = "Ahnimar Aged Salve", zone = 0, destinations = {

    }},
    [42015] = { name = "Karkasse Aged Salve", zone = 0, destinations = {

    }},
    [42016] = { name = "Sunbite Aged Salve", zone = 0, destinations = {

    }},
    [42017] = { name = "Rokhala Aged Salve", zone = 0, destinations = {

    }},
    [42018] = { name = "Airain Aged Cheese", zone = 0, destinations = {

    }},
    [42019] = { name = "Aubre Cradle Aged Cheese", zone = 0, destinations = {

    }},
    [42020] = { name = "Ahnimar Aged Cheese", zone = 0, destinations = {

    }},
    [42021] = { name = "Karkasse Aged Cheese", zone = 0, destinations = {

    }},
    [42022] = { name = "Sunbite Aged Cheese", zone = 0, destinations = {

    }},
    [42023] = { name = "Rokhala Aged Cheese", zone = 0, destinations = {

    }},
    [42038] = { name = "Hasla Antiquities", zone = 0, destinations = {

    }},
    [42039] = { name = "Perinoor Antiquities", zone = 0, destinations = {

    }},
    [42040] = { name = "Two Crowns Antiquities", zone = 0, destinations = {

    }},
    [42041] = { name = "White Arden Antiquities", zone = 0, destinations = {

    }},
    [44910] = { name = "Mysterious Crate", zone = 0, destinations = {

    }},
    [8001202] = { name = "Coin Chest", zone = 0, destinations = {

    }},
    [8001203] = { name = "Golden Statue Fragment", zone = 0, destinations = {

    }},
    [8001204] = { name = "Golden Treasure Chest", zone = 0, destinations = {

    }},
    [9000362] = { name = "Fish Food Supplies", zone = 0, destinations = {

    }},
    [9000414] = { name = "Fish Food Supply Pack", zone = 0, destinations = {

    }},
}
packs_helper.packsInfo = packsInfo



function packs_helper:IsASpecialtyPackById(itemId)
    if packsInfo[itemId] ~= nil then 
        return true
    else
        return false
    end
end
function packs_helper:IsASpecialtyPackByName(itemName)

end 

function packs_helper:GetSpecialtyPackIdByName(itemName)

end

function packs_helper:GetSpecialtyPackNameById(itemId)
    if packsInfo[itemId] ~= nil then 
        return packsInfo[itemId]
    else
        return nil
    end
end 

function packs_helper:GetSpecialtyPackZoneIdById(itemId)
    return packsInfo[itemId].zone
end

function packs_helper:GetSpecialtyPackZoneIdByName(itemName)

end

function packs_helper:GetSpecialtyPackRatio(itemId)

end 

function packs_helper:GetSpecialtyPackProfit(itemId)

end

function packs_helper:GetSpecialtyPackPayout(itemId)

end


return packs_helper