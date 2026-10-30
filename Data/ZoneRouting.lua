local _, ns = ...

-- VENDORED FROM EVERYTHING QUESTS - keep in step by hand.
--   EQ Data/QuestChains/_Index.lua            -> ns.CAT and ns.ZONE_CATEGORIES
--   EQ Data/QuestChains/_QuestLineRouting.lua -> ns.QUESTLINE_ROUTING
-- An index only: the quests inside each questline come from C_QuestLine at runtime.
-- Blizzard exposes no per-zone quest total, so this file cannot be replaced by an API -
-- zone story achievements, campaign chapters and GetAvailableQuestLines were each tried
-- against a live client and none answers. An unrouted zone shows no bar rather than a
-- wrong number, which is EQ's own behavior.

ns.CAT = {
    CAMPAIGN          = 1100,
    EVERSONG_WOODS    = 1101,
    ZULAMAN           = 1102,
    HARANDAR          = 1103,
    VOIDSTORM         = 1104,
    ARATOR            = 1105,
    WAR_LIGHT_SHADOW  = 1106,
    CURSE_OF_ULATEK   = 1107,
    VOID_ACROPOLIS    = 1108,
    SUNSTRIDER_OMNIUM = 1109,
    COILED_ISLE       = 1110,
    PROMISE_OF_TOMORROW = 1111,
}

-- Eversong Woods lists Silvermoon City (2393) on purpose so the city shows the zone's
-- progress. Eversong itself (2395) is listed too, unlike Everything Quests' copy: the name
-- match compares English names, so it found Eversong on English clients only. Keep 2395 on a sync.
ns.ZONE_CATEGORIES = {
    [ns.CAT.CAMPAIGN]          = { name = "Midnight Campaign",           mapIDs = {},       campaignID = 270 },
    [ns.CAT.WAR_LIGHT_SHADOW]  = { name = "The War of Light and Shadow", mapIDs = {},       campaignID = 284 },
    [ns.CAT.EVERSONG_WOODS]    = { name = "Eversong Woods",              mapIDs = { 2393, 2395 } },
    [ns.CAT.ZULAMAN]           = { name = "Zul'Aman",                    mapIDs = { 2437 } },
    [ns.CAT.HARANDAR]          = { name = "Harandar",                    mapIDs = { 2413 } },
    [ns.CAT.ARATOR]            = { name = "Arator",                      mapIDs = {} },
    [ns.CAT.VOIDSTORM]         = { name = "Voidstorm",                   mapIDs = { 2405 } },
    [ns.CAT.CURSE_OF_ULATEK]   = { name = "The Curse of Ula'tek",        mapIDs = { 2424 } },
    [ns.CAT.SUNSTRIDER_OMNIUM] = { name = "The Sunstrider Omnium",       mapIDs = {} },
    [ns.CAT.VOID_ACROPOLIS]    = { name = "Void Acropolis",              mapIDs = { 2599 } },
    [ns.CAT.COILED_ISLE]       = { name = "The Coiled Isle",             mapIDs = { 2512 } },
    [ns.CAT.PROMISE_OF_TOMORROW] = { name = "The Promise of Tomorrow",   mapIDs = {},       campaignID = 349 },
}

ns.QUESTLINE_ROUTING = {
    [5719] = { cat = ns.CAT.EVERSONG_WOODS, name = "Whispers in the Twilight" },
    [5720] = { cat = ns.CAT.EVERSONG_WOODS, name = "Shadowfall" },
    [5721] = { cat = ns.CAT.EVERSONG_WOODS, name = "Ripple Effects" },
    [5931] = { cat = ns.CAT.EVERSONG_WOODS, name = "Fear and Fel" },
    [6020] = { cat = ns.CAT.EVERSONG_WOODS, name = "Flowers for Amalthea" },
    [5949] = { cat = ns.CAT.EVERSONG_WOODS, name = "Sunbath, Take Me Away" },
    [5805] = { cat = ns.CAT.EVERSONG_WOODS, name = "Port Detective" },
    [5812] = { cat = ns.CAT.EVERSONG_WOODS, name = "Lesser Evil" },
    [5898] = { cat = ns.CAT.EVERSONG_WOODS, name = "One Adventurous Hatchling" },
    [5969] = { cat = ns.CAT.EVERSONG_WOODS, name = "Far Striding" },
    [5989] = { cat = ns.CAT.EVERSONG_WOODS, name = "Tailor Troubles" },
    [6018] = { cat = ns.CAT.EVERSONG_WOODS, name = "Blinding Sun" },
    [5993] = { cat = ns.CAT.EVERSONG_WOODS, name = "Runestone Rumbles" },
    [5908] = { cat = ns.CAT.EVERSONG_WOODS, name = "Paladin Rescue" },
    [5937] = { cat = ns.CAT.EVERSONG_WOODS, name = "How to Train Your Protege" },
    [6030] = { cat = ns.CAT.EVERSONG_WOODS, name = "Scootin' Through Silvermoon" },
    [5781] = { cat = ns.CAT.EVERSONG_WOODS, name = "Aspiring Academic" },
    [5784] = { cat = ns.CAT.EVERSONG_WOODS, name = "The Drinking Debt" },
    [5804] = { cat = ns.CAT.EVERSONG_WOODS, name = "Theft Tracking" },
    [5958] = { cat = ns.CAT.EVERSONG_WOODS, name = "Daggerspine Landing" },
    [6301] = { cat = ns.CAT.EVERSONG_WOODS, name = "Into the Labyrinth" },
    [5722] = { cat = ns.CAT.ZULAMAN, name = "Dis Was Our Land" },
    [5723] = { cat = ns.CAT.ZULAMAN, name = "Path of De Hashey" },
    [5938] = { cat = ns.CAT.ZULAMAN, name = "Where War Slumbers" },
    [5724] = { cat = ns.CAT.ZULAMAN, name = "De Amani Never Die" },
    [5778] = { cat = ns.CAT.ZULAMAN, name = "Healing the Spirit" },
    [6048] = { cat = ns.CAT.ZULAMAN, name = "Sawdust to Sawdust" },
    [5981] = { cat = ns.CAT.ZULAMAN, name = "Between Two Trolls" },
    [5901] = { cat = ns.CAT.ZULAMAN, name = "Sorrowing Kin" },
    [5905] = { cat = ns.CAT.ZULAMAN, name = "Unlikely Friends" },
    [5971] = { cat = ns.CAT.ZULAMAN, name = "The Voice of Nalorakk" },
    [6011] = { cat = ns.CAT.ZULAMAN, name = "Reclaiming De Honor" },
    [5939] = { cat = ns.CAT.ZULAMAN, name = "Vengeance for Tolbani" },
    [5988] = { cat = ns.CAT.ZULAMAN, name = "The Loa of Murlocs" },
    [5999] = { cat = ns.CAT.ZULAMAN, name = "No Fear" },
    [6042] = { cat = ns.CAT.ZULAMAN, name = "Bitter Honor" },
    [6055] = { cat = ns.CAT.ZULAMAN, name = "The Sound of Her Voice" },
    [5950] = { cat = ns.CAT.ZULAMAN, name = "A Venomous History" },
    [6044] = { cat = ns.CAT.ZULAMAN, name = "Beyond the Walls" },
    [5975] = { cat = ns.CAT.ZULAMAN, name = "Something Vile This Way Comes" },
    [6045] = { cat = ns.CAT.ZULAMAN, name = "River Walkers of the Prowl" },
    [6052] = { cat = ns.CAT.ZULAMAN, name = "Bloodstains" },
    [5728] = { cat = ns.CAT.VOIDSTORM, name = "Into the Abyss" },
    [5729] = { cat = ns.CAT.VOIDSTORM, name = "The Night's Veil" },
    [5730] = { cat = ns.CAT.VOIDSTORM, name = "Dawn of Reckoning" },
    [6010] = { cat = ns.CAT.VOIDSTORM, name = "The Void Peers Back" },
    [5943] = { cat = ns.CAT.VOIDSTORM, name = "Shadow Puppets" },
    [5933] = { cat = ns.CAT.VOIDSTORM, name = "The Nethersent" },
    [5962] = { cat = ns.CAT.VOIDSTORM, name = "The Nightbreaker" },
    [6028] = { cat = ns.CAT.VOIDSTORM, name = "Pathogenic Problem" },
    [6013] = { cat = ns.CAT.VOIDSTORM, name = "A Voice Inside" },
    [5987] = { cat = ns.CAT.VOIDSTORM, name = "Shadowguard's Shadow" },
    [6019] = { cat = ns.CAT.VOIDSTORM, name = "A Gift Given Freely" },
    [5964] = { cat = ns.CAT.VOIDSTORM, name = "Breaking the Triad" },
    [6022] = { cat = ns.CAT.VOIDSTORM, name = "Go Low, Go Loud" },
    [6017] = { cat = ns.CAT.VOIDSTORM, name = "Secrets in the Dark" },
    [6014] = { cat = ns.CAT.VOIDSTORM, name = "Oaths to Family" },
    [5961] = { cat = ns.CAT.VOIDSTORM, name = "To Be Changed" },
    [5936] = { cat = ns.CAT.VOIDSTORM, name = "A Dance with the Devil" },
    [6012] = { cat = ns.CAT.VOIDSTORM, name = "A Domanaar's Best Friend" },
    [6001] = { cat = ns.CAT.VOIDSTORM, name = "A More Potent Foe" },
    [5725] = { cat = ns.CAT.HARANDAR, name = "Of Caves and Cradles" },
    [5726] = { cat = ns.CAT.HARANDAR, name = "Call of the Goddess" },
    [5907] = { cat = ns.CAT.HARANDAR, name = "A Goblin in Harandar" },
    [5909] = { cat = ns.CAT.HARANDAR, name = "The Legend of Aln'sharan" },
    [5935] = { cat = ns.CAT.HARANDAR, name = "Late Bloomers" },
    [5952] = { cat = ns.CAT.HARANDAR, name = "The Greenspeaker's Vigil" },
    [5944] = { cat = ns.CAT.HARANDAR, name = "Peril Among Petals" },
    [5960] = { cat = ns.CAT.HARANDAR, name = "Haranir Never Say Die" },
    [5966] = { cat = ns.CAT.HARANDAR, name = "Harandar's Kitchen" },
    [6036] = { cat = ns.CAT.HARANDAR, name = "Silence at Fungara Village" },
    [5977] = { cat = ns.CAT.HARANDAR, name = "Cultivating Hope" },
    [6039] = { cat = ns.CAT.HARANDAR, name = "Hunter's Rights" },
    [6038] = { cat = ns.CAT.HARANDAR, name = "A Palette of Feelings" },
    [6040] = { cat = ns.CAT.HARANDAR, name = "Predator Reintroduction" },
    [6032] = { cat = ns.CAT.HARANDAR, name = "Bloomtown" },
    [5910] = { cat = ns.CAT.HARANDAR, name = "The Grudge Pit" },
    [5932] = { cat = ns.CAT.HARANDAR, name = "Trials of the Shulka" },
    [5750] = { cat = ns.CAT.ARATOR, name = "The Path of Light" },
    [5751] = { cat = ns.CAT.ARATOR, name = "Regrets of the Past" },
    [6050] = { cat = ns.CAT.CURSE_OF_ULATEK, name = "Legacy of the Amani" },
    [6229] = { cat = ns.CAT.CURSE_OF_ULATEK, name = "An Island of Fangs" },
    [6230] = { cat = ns.CAT.CURSE_OF_ULATEK, name = "Ghosts of the Past" },
    [6231] = { cat = ns.CAT.CURSE_OF_ULATEK, name = "Original Sin" },
    [6232] = { cat = ns.CAT.CURSE_OF_ULATEK, name = "The Battle for Atal'Utek" },
    [6272] = { cat = ns.CAT.VOID_ACROPOLIS, name = "Umbral Blitz" },
    [6309] = { cat = ns.CAT.VOID_ACROPOLIS, name = "Assault and Strike Back: Val" },
    [6275] = { cat = ns.CAT.SUNSTRIDER_OMNIUM, name = "The Sunstrider Omnium" },
    -- Map 2512, added in 12.1. The other eight questlines the client reports there are already
    -- routed to Zul'Aman above, and a routed category wins over the map that surfaced it.
    [6114] = { cat = ns.CAT.COILED_ISLE, name = "Bone Deep" },
    [6115] = { cat = ns.CAT.COILED_ISLE, name = "Renown of Midnight" },
    [6128] = { cat = ns.CAT.COILED_ISLE, name = "A Fiery Blast from the Past" },
    [6224] = { cat = ns.CAT.COILED_ISLE, name = "Something Vile This Way Comes" },
    [6276] = { cat = ns.CAT.COILED_ISLE, name = "Strange Friends in Odd Places" },
    [6277] = { cat = ns.CAT.COILED_ISLE, name = "Ancient Anthropology" },
    [6302] = { cat = ns.CAT.COILED_ISLE, name = "Living Legend" },
    -- Deliberately unlike Everything Quests, which routes 6121 to CURSE_OF_ULATEK: that
    -- category's only mapID is 2424 and the zone bar runs off this copy, so matching it would
    -- make Atal'Utek count 14 quests from a zone the player is not in. GetAvailableQuestLines
    -- does not report campaign chapters, so a sync cannot re-derive this row - do not drop it.
    [6121] = { cat = ns.CAT.COILED_ISLE, name = "The Call of the Void" },
    -- EQ sources the campaign spine live through C_CampaignInfo, so campaign questlines
    -- are deliberately absent here
}
