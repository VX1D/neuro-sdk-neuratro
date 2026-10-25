local Filtered = {}

local FILTERED_TERMS = {
  { "nigg*", allow = { "niggard", "niggardly", "niggardliness" } }, "fagg*", "kike",
  { "retard", replacement = "idiot" }, "2 girls 1 cup", "anal", "anus", "areole", "arian", "arrse",
  "arse", "arsehole", "aryan", "ass", "assbang", "assbanged", "asses", "assfuck", "assfucker",
  "assfukka", "asshole", "assmunch", "asswhole", "autoerotic", "ballsack", "bastard", "bdsm",
  "beastial", "beastiality", "bellend", "bestial", "bestiality", "bimbo", "bimbos", "bitch",
  "bitches", "bitchin", "bitching", "blowjob", "blowjobs", "blue waffle", "bondage", "boner",
  "boob", "boobs", "booobs", "boooobs", "booooobs", "booooooobs", "booty call", "breasts",
  "brown shower", "brown showers", "buceta", "bukake", "bukkake", "bullshit", "busty", "butthole",
  "carpet muncher", "cawk", "chink", "cipa", "clit", "clitoris", "clits", "cnut", "cock",
  "cockface", "cockhead", "cockmunch", "cockmuncher", "cocks", "cocksuck", "cocksucked",
  "cocksucker", "cocksucking", "cocksucks", "cokmuncher", "coon", "cowgirl", "cowgirls", "crotch",
  "cum", "cuming", "cummer", "cumming", "cums", "cumshot", "cunilingus", "cunillingus",
  "cunnilingus", "cunt", "cuntlicker", "cuntlicking", "cunts", "deepthroat", "dick", "dickhead",
  "dildo", "dildos", "dink", "dinks", "dlck", "dog style", "dog-fucker", "doggiestyle", "doggin",
  "dogging", "doggystyle", "dong", "donkeyribber", "doosh", "dopey", "douche", "douchebag",
  "douchebags", "douchey", "duche", "dumass", "dumbass", "dumbasses", "dyke", "dykes", "eatadick",
  "eathairpie", "ejaculate", "ejaculated", "ejaculates", "ejaculating", "ejaculatings",
  "ejaculation", "ejakulate", "enlargement", "erect", "erection", "erotic", "erotism", "essohbee",
  "extacy", "extasy", "facial", "fack", "fag", "fagged", "fagging", "faggit", "faggitt", "faggot",
  "faggs", "fagot", "fagots", "fags", "faig", "faigt", "fanny", "fannybandit", "fannyflaps",
  "fannyfucker", "fanyy", "fart", "fartknocker", "fat", "fatass", "fcuk", "fcuker", "fcuking",
  "feck", "fecker", "felch", "felcher", "felching", "fellate", "fellatio", "feltch", "feltcher",
  "femdom", "fingerfuck", "fingerfucked", "fingerfucker", "fingerfuckers", "fingerfucking",
  "fingerfucks", "fingering", "fisted", "fistfuck", "fistfucked", "fistfucker", "fistfuckers",
  "fistfucking", "fistfuckings", "fistfucks", "fisting", "fisty", "flange", "flogthelog", "floozy",
  "foad", "fondle", "foobar", "fook", "fooker", "footjob", "foreskin", "freex", "frigg", "frigga",
  "fubar", "fuck", "fucka", "fuckass", "fuckbitch", "fucked", "fucker", "fuckers", "fuckface",
  "fuckhead", "fuckheads", "fuckhole", "fuckin", "fucking", "fuckings", "fuckingshitmotherfucker",
  "fuckme", "fuckmeat", "fucknugget", "fucknut", "fuckoff", "fuckpuppet", "fucks", "fucktard",
  "fucktoy", "fucktrophy", "fuckup", "fuckwad", "fuckwhit", "fuckwit", "fuckyomama", "fudgepacker",
  "fuk", "fuker", "fukker", "fukkin", "fukking", "fuks", "fukwhit", "fukwit", "futanari",
  "futanary", "fux", "fuxor", "fxck", "gae", "gai", "gangbang", "gangbanged", "gangbangs", "ganja",
  "gassyass", "gay", "gaylord", "gays", "gaysex", "gey", "gfy", "ghay", "ghey", "gigolo", "glans",
  "goatse", "godamn", "godamnit", "goddam", "goddammit", "goddamn", "goddamned", "gokkun",
  "goldenshower", "gonad", "gonads", "gook", "gooks", "gringo", "gspot", "gtfo", "guido",
  "hamflap", "handjob", "hardcoresex", "hardon", "hebe", "heeb", "hemp", "hentai", "heroin",
  "herp", "herpes", "herpy", "heshe", "hitler", "hiv", "hoar", "hoare", "hobag", "hoer", "homey",
  "homo", "homoerotic", "homoey", "honky", "hooch", "hookah", "hooker", "hoor", "hootch", "hooter",
  "hooters", "hore", "horniest", "horny", "hotsex", "howtokill", "howtomurder", "hump", "humped",
  "humping", "hussy", "hymen", "inbred", "incest", "injun", "jackass", "jackhole", "jackoff",
  "jap", "japs", "jerked", "jerkoff", "jism", "jiz", "jizm", "jizz", "jizzed", "junkie", "junky",
  "kawk", "kikes", "kinbaku", "kinky", "kinkyJesus", "kkk", "klan", "knob", "knobead", "knobed",
  "knobend", "knobhead", "knobjocky", "knobjokey", "kock", "kondum", "kondums", "kooch", "kooches",
  "kootch", "kraut", "kum", "kummer", "kumming", "kums", "kunilingus", "kwif", "kyke", "l3itch",
  "labia", "lech", "leper", "lesbians", "lesbo", "lesbos", "lez", "lezbian", "lezbians", "lezbo",
  "lezbos", "lezzie", "lezzies", "lezzy", "loin", "loins", "lube", "lust", "lusting", "lusty",
  "m-fucking", "mafugly", "mams", "masochist", "massa", "masterb8", "masterbate", "masterbating",
  "masterbation", "masterbations", "masturbate", "masturbating", "masturbation", "maxi", "menses",
  "menstruate", "menstruation", "meth", "milf", "mofo", "molest", "moolie", "mothafuck",
  "mothafucka", "mothafuckas", "mothafuckaz", "mothafucked", "mothafucker", "mothafuckers",
  "mothafuckin", "mothafucking", "mothafuckings", "mothafucks", "motherfuck", "motherfucka",
  "motherfucked", "motherfucker", "motherfuckers", "motherfuckin", "motherfucking",
  "motherfuckings", "motherfuckka", "motherfucks", "mtherfucker", "mthrfucker", "mthrfucking",
  "muff", "muffdiver", "muffpuff", "murder", "mutha", "muthafecker", "muthafuckaz", "muthafucker",
  "muthafuckker", "muther", "mutherfucker", "mutherfucking", "muthrfucking", "nad", "nads",
  "naked", "napalm", "nappy", "nazi", "nazism", "needthedick", "negro", "nig", "nigga", "niggah",
  "niggas", "niggaz", "nigger", "niggers", "niggle", "niglet", "nimrod", "ninny", "nipple",
  "nipples", "nob", "nobhead", "nobjocky", "nobjokey", "nooky", "nude", "nudes", "numbnuts",
  "nutbutter", "nutsack", "nympho", "opiate", "opium", "oral", "orally", "orgasim", "orgasims",
  "orgasm", "orgasmic", "orgasms", "orgies", "orgy", "ovary", "ovum", "ovums", "paddy", "paki",
  "pantie", "panties", "panty", "pastie", "pasty", "pawn", "pcp", "pecker", "pedo", "pedophile",
  "pedophilia", "pedophiliac", "pee", "peepee", "penetrate", "penetration", "penial", "penile",
  "penis", "penisfucker", "perversion", "peyote", "phalli", "phallic", "phonesex", "phuck", "phuk",
  "phuked", "phuking", "phukked", "phukking", "phuks", "phuq", "pigfucker", "pillowbiter", "pimp",
  "pimpis", "pinko", "piss", "pissed", "pisser", "pissers", "pisses", "pissflaps", "pissin",
  "pissing", "pissoff", "playboy", "pms", "polack", "pollock", "poon", "poontang", "poop", "porn",
  "porno", "pornography", "pornos", "potty", "prick", "pricks", "prig", "pron", "prostitute",
  "prude", "pube", "pubic", "pubis", "punkass", "punky", "puss", "pusse", "pussi", "pussies",
  "pussy", "pussyfart", "pussypalace", "pussypounder", "pussys", "puto", "queaf", "queef", "queer",
  "queero", "queers", "quicky", "quim", "racy", "rape", "raped", "raper", "raping", "rapist",
  "raunch", "rectal", "rectum", "rectus", "reefer", "reetard", "reich", "retarded", "revue",
  "rimjaw", "rimjob", "rimming", "ritard", "rtard", "rump", "rumprammer", "ruski", "sadism",
  "sadist", "sandbar", "sausagequeen", "scag", "scantily", "schizo", "schlong", "scroat", "scrog",
  "scrot", "scrote", "scrotum", "scrud", "scum", "seaman", "seamen", "seduce", "semen", "sex",
  "sexual", "shag", "shagger", "shaggin", "shagging", "shamedame", "shemale", "shibari", "shibary",
  "shit", "shitdick", "shite", "shiteater", "shited", "shitey", "shitface", "shitfuck",
  "shitfucker", "shitfull", "shithead", "shithole", "shithouse", "shiting", "shitings", "shits",
  "shitt", "shitted", "shitter", "shitters", "shitting", "shittings", "shitty", "shiz", "shota",
  "sissy", "skag", "skank", "slave", "sleaze", "sleazy", "slut", "slutbucket", "slutdumper",
  "slutkiss", "sluts", "smegma", "smut", "smutty", "snatch", "sniper", "snuff", "sodom",
  "son-of-a-bitch", "souse", "soused", "spac", "sperm", "spic", "spick", "spik", "spiks", "spooge",
  "spunk", "steamy", "stfu", "stiffy", "stoned", "strip", "strip club", "stripclub", "stroke",
  "suck", "sucked", "sucking", "sumofabiatch", "tampon", "tard", "tawdry", "teabagging", "teat",
  "teets", "teez", "terd", "teste", "testee", "testes", "testical", "testicle", "testis",
  "threesome", "throating", "thrust", "thug", "tinkle", "tit", "titfuck", "titi", "tits", "titt",
  "tittiefucker", "titties", "titty", "tittyfuck", "tittyfucker", "tittywank", "titwank", "toke",
  "toots", "tosser", "tramp", "transsexual", "trashy", "tubgirl", "turd", "tush", "twat",
  "twathead", "twats", "twatty", "twunt", "twunter", "undies", "unwed", "urinal", "urine",
  "uterus", "vag", "vagina", "valium", "viagra", "vigra", { "virgin", replacement = "person" },
  "vixen", "vodka", "vomit", "voyeur", "vulgar", "vulva", "wad", "wang", "wank", "wanker", "wanky",
  "wazoo", "wedgie", "weed", "weenie", "weewee", "weiner", "wench", "wetback", "whitey", "whiz",
  "whoar", "whoralicious", "whore", "whorealicious", "whored", "whoreface", "whorehopper",
  "whorehouse", "whores", "whoring", "wigger", "willies", "willy", "womb", "woody", "woose", "wop",
  "x-rated2g1c", "xx", "xxx", "yaoi", "yury", "holocaust", "kys", "kill yourself", "suicide",
  "hang yourself", "trann*", "simp", "incel", "beaner", "raghead", "towlehead", "camel jockey",
  "porch monkey", "tar baby", "jigaboo", "golliwog", "isis", "al qaeda", "nazis", "white power",
  "mongoloid", { "obese", replacement = "large" }, "blackface", "swatting", "doxxing",
}

local SUBSTRING_TERMS = {
  "nigger", "nigga", "niglet", "faggot", "fag", "kike", "kyke", "chink", "spic", "coon", "gook",
  "wetback", "beaner", "jigaboo", "golliwog", "wigger", "tranny", "retard", "kkk", "wop", "spook",
  "fuck", "shit", "cunt", "cock", "dick", "pussy", "bitch", "whore", "slut", "asshole", "bastard",
  "motherfucker", "dickhead", "cocksucker", "wanker", "twat", "jizz", "faggit",
}

local function stretched(terms)
  local out = {}
  for i = 1, #terms do out[i] = (terms[i]:gsub("(.)", "%1+")) end
  return out
end

local SUBSTRING_PATTERNS = stretched(SUBSTRING_TERMS)

local GLUED_SLUR_TERMS = {
  "nigger", "nigga", "niglet", "faggot", "jigaboo", "golliwog", "wetback", "beaner",
  "cocksucker", "motherfucker",
}
local GLUED_SLUR_PATTERNS = stretched(GLUED_SLUR_TERMS)

local SUBSTRING_CLEAN = {
  "scunthorpe", "shiitake", "shitake", "snigger", "sniggered", "sniggering", "sniggers",
  "cockpit", "cockpits", "cocktail", "cocktails", "peacock", "peacocks", "shuttlecock",
  "hancock", "cockatoo", "cockney", "cockroach", "cockroaches", "dickens", "dickinson",
  "niggard", "niggardly", "niggardliness", "beanery", "beaneries",
}

local function escape_pattern(text)
  return text:gsub("([^%w])", "%%%1")
end

local ALLOWED_PHRASES = {
  "lusty joker",
}

local function case_insensitive_pattern(text)
  local pat = ""
  for i = 1, #text do
    local c = text:sub(i, i)
    if c:match("%a") then
      pat = pat .. "[" .. c:lower() .. c:upper() .. "]"
    else
      pat = pat .. escape_pattern(c)
    end
  end
  return pat
end

local LEET = {
  ["1"] = "i", ["!"] = "i", ["|"] = "i", ["3"] = "e", ["4"] = "a", ["@"] = "a", ["5"] = "s",
  ["7"] = "t", ["0"] = "o", ["2"] = "z", ["6"] = "g", ["8"] = "b", ["9"] = "g", ["$"] = "s",
}

local function normalize_leetspeak(text)
  return (text:lower():gsub("[1!|34@5702689$]", LEET):gsub("[%p%s]", ""))
end

local SUBSTRING_CLEAN_NORM = {}
for i = 1, #SUBSTRING_CLEAN do
  SUBSTRING_CLEAN_NORM[normalize_leetspeak(SUBSTRING_CLEAN[i])] = true
end

local function strip_clean_words(text)
  local out = text
  for i = 1, #SUBSTRING_CLEAN do
    out = out:gsub(case_insensitive_pattern(SUBSTRING_CLEAN[i]), function(m)
      return (" "):rep(#m)
    end)
  end
  return out
end

local _compiled = nil

local function compile_patterns()
  if _compiled then return _compiled end

  local exact_set = {}
  local exact_norm = {}
  local regex_list = {}

  for i = 1, #FILTERED_TERMS do
    local entry = FILTERED_TERMS[i]
    if type(entry) == "string" then entry = { entry } end
    local term = entry[1]
    local mute = entry.replacement == nil
    local replace_with = entry.replacement or "***"

    if term:find("%*$") then
      local prefix = term:gsub("%*$", "")
      local allowset
      if entry.allow then
        allowset = {}
        for j = 1, #entry.allow do
          allowset[normalize_leetspeak(entry.allow[j])] = true
        end
      end
      regex_list[#regex_list + 1] = {
        pat = "%f[%a]" .. case_insensitive_pattern(prefix) .. "%w*",
        replace_with = replace_with,
        mute = mute,
        norm_term = normalize_leetspeak(prefix),
        is_wildcard = true,
        allow = allowset,
      }
    elseif term:match("^%a+$") then
      exact_set[term:lower()] = { rep = replace_with, mute = mute }
      exact_norm[normalize_leetspeak(term)] = true
    else
      local pat = case_insensitive_pattern(term)
      if term:find("^%w") then pat = "%f[%w]" .. pat end
      if term:find("%w$") then pat = pat .. "%f[%W]" end
      regex_list[#regex_list + 1] = {
        pat = pat,
        replace_with = replace_with,
        mute = mute,
        norm_term = normalize_leetspeak(term),
        is_wildcard = false,
        multiword = term:find("%s") ~= nil,
      }
    end
  end

  _compiled = { exact = exact_set, exact_norm = exact_norm, regex = regex_list }
  return _compiled
end

local function protect_allowed(text)
  local saved = {}
  for i = 1, #ALLOWED_PHRASES do
    local pat = "%f[%a]" .. case_insensitive_pattern(ALLOWED_PHRASES[i]) .. "%a*"
    text = text:gsub(pat, function(m)
      saved[#saved + 1] = m
      return "\1" .. #saved .. "\1"
    end)
  end
  return text, saved
end

local function restore_allowed(text, saved)
  if #saved == 0 then return text end
  return (text:gsub("\1(%d+)\1", function(n)
    return saved[tonumber(n)] or ""
  end))
end

function Filtered.sanitize(text, strict)
  if type(text) ~= "string" then
    return text and tostring(text) or ""
  end
  if text == "" then
    return ""
  end
  if strict then
    local norm = normalize_leetspeak(strip_clean_words(text))
    for i = 1, #SUBSTRING_PATTERNS do
      if norm:find(SUBSTRING_PATTERNS[i]) then
        return "***"
      end
    end
  end
  local compiled = compile_patterns()
  local exact = compiled.exact
  local exact_norm = compiled.exact_norm
  local regex = compiled.regex

  local src, saved = protect_allowed(text)

  local out = src:gsub("%a+", function(word)
    local e = exact[word:lower()]
    if e then
      return e.rep
    end
    return word
  end)

  for i = 1, #regex do
    local cp = regex[i]
    out = out:gsub(cp.pat, function(match)
      if cp.allow and cp.allow[normalize_leetspeak(match)] then
        return match
      end
      return cp.replace_with
    end)
  end

  for raw_word in src:gmatch("%S+") do
    local nw = normalize_leetspeak(raw_word)
    if #nw >= 3 then
      local hit = exact_norm[nw] and true or false
      if not hit then
        for i = 1, #regex do
          local cp = regex[i]
          local nt = cp.norm_term
          if cp.mute and not cp.multiword and nt and #nt >= 3 then
            local m
            if cp.is_wildcard then m = (nw:sub(1, #nt) == nt) else m = (nw == nt) end
            if m and not (cp.allow and cp.allow[nw]) then
              hit = true
              break
            end
          end
        end
      end
      if not hit and not SUBSTRING_CLEAN_NORM[nw] then
        for i = 1, #GLUED_SLUR_PATTERNS do
          if nw:find(GLUED_SLUR_PATTERNS[i]) then
            hit = true
            break
          end
        end
      end
      if hit then
        local pat = escape_pattern(raw_word)
        if raw_word:find("^%w") then pat = "%f[%w]" .. pat end
        if raw_word:find("%w$") then pat = pat .. "%f[%W]" end
        out = out:gsub(pat, "***")
      end
    end
  end

  local toks = {}
  for w in src:gmatch("%S+") do
    toks[#toks + 1] = normalize_leetspeak(w)
  end
  for i = 1, #regex do
    local cp = regex[i]
    if cp.mute and cp.multiword and cp.norm_term and #cp.norm_term >= 3 then
      local nt = cp.norm_term
      for s = 1, #toks do
        if toks[s]:find(nt, 1, true) then
          return "***"
        end
        local acc = toks[s]
        local j = s
        while #acc < #nt and j < #toks do
          j = j + 1
          acc = acc .. toks[j]
        end
        if acc == nt then
          return "***"
        end
      end
    end
  end

  return restore_allowed(out, saved)
end

return Filtered
