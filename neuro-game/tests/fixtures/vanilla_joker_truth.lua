local T = {}
local function E(key, list) T[key] = list end

E("j_joker",        {{kind="mult", scope="hand", val=4,   gate=nil,       ref=4328}})
E("j_misprint",     {{kind="mult", scope="hand", val="0..23", gate=nil,   ref=4074, random=true}})
E("j_stuntman",     {{kind="chips",scope="hand", val=250, gate=nil,       ref=4087}})
E("j_cavendish",    {{kind="xmult",scope="hand", val=3,   gate=nil,       ref=4376}})
E("j_gros_michel",  {{kind="mult", scope="hand", val=15,  gate=nil,       ref=4370}})
E("j_abstract",     {{kind="mult", scope="hand", val="3*jokers", gate=nil,ref=4052}})
E("j_wee",          {{kind="chips",scope="hand", val="acc", gate=nil,     ref=4221}})
E("j_square",       {{kind="chips",scope="hand", val="acc", gate=nil,     ref=4249}})
E("j_runner",       {{kind="chips",scope="hand", val="acc", gate=nil,     ref=4256}})
E("j_ice_cream",    {{kind="chips",scope="hand", val="acc", gate=nil,     ref=4263}})

for _, s in ipairs{ {"j_jolly","mult",8,"Pair"},{"j_zany","mult",12,"Three of a Kind"},
  {"j_mad","mult",10,"Two Pair"},{"j_crazy","mult",12,"Straight"},{"j_droll","mult",10,"Flush"},
  {"j_sly","chips",50,"Pair"},{"j_wily","chips",100,"Three of a Kind"},{"j_clever","chips",80,"Two Pair"},
  {"j_devious","chips",100,"Straight"},{"j_crafty","chips",80,"Flush"},
  {"j_duo","xmult",2,"Pair"},{"j_trio","xmult",3,"Three of a Kind"},{"j_family","xmult",4,"Four of a Kind"},
  {"j_order","xmult",3,"Straight"},{"j_tribe","xmult",2,"Flush"} } do
  E(s[1], {{kind=s[2], scope="hand", val=s[3], gate="hand_type:"..s[4], ref=4027}})
end

E("j_half",         {{kind="mult", scope="hand", val=20,  gate="hand_size<=3",     ref=4046}})
E("j_stencil",      {{kind="xmult",scope="hand", val="acc",gate="empty_slots>0",   ref=4314}})
E("j_acrobat",      {{kind="xmult",scope="hand", val=3,   gate="last_hand",        ref=4062}})
E("j_mystic_summit",{{kind="mult", scope="hand", val=15,  gate="discards==0",      ref=4068}})
E("j_banner",       {{kind="chips",scope="hand", val="30*discards", gate="discards>0", ref=4081}})
E("j_supernova",    {{kind="mult", scope="hand", val="played(type)", gate="per_hand_type", ref=4104}})
E("j_flower_pot",   {{kind="xmult",scope="hand", val=3,   gate="4_suits",          ref=4180}})
E("j_seeing_double",{{kind="xmult",scope="hand", val=2,   gate="club+other",       ref=4213}})
E("j_castle",       {{kind="chips",scope="hand", val="acc",gate="chips>0",         ref=4228}})
E("j_blue_joker",   {{kind="chips",scope="hand", val="2*deck", gate="deck>0",      ref=4235}})
E("j_erosion",      {{kind="mult", scope="hand", val="4*missing", gate="missing>0",ref=4242}})
E("j_stone",        {{kind="chips",scope="hand", val="25*stone", gate="stone>0",   ref=4270}})
E("j_steel_joker",  {{kind="xmult",scope="hand", val="1+0.2*steel", gate="steel>0",ref=4277}})
E("j_bull",         {{kind="chips",scope="hand", val="2*$",  gate="$>0",           ref=4284}})
E("j_drivers_license",{{kind="xmult",scope="hand",val=3,   gate="16_enhanced",     ref=4291}})
E("j_blackboard",   {{kind="xmult",scope="hand", val=3,   gate="all_held_black",   ref=4299}})
E("j_fortune_teller",{{kind="mult",scope="hand", val="tarots", gate="tarots>0",    ref=4364}})
E("j_card_sharp",   {{kind="xmult",scope="hand", val=3,   gate="type_repeat",      ref=4388}})
E("j_bootstraps",   {{kind="mult", scope="hand", val="2*floor($/5)", gate="$>=5",  ref=4394}})
E("j_caino",        {{kind="xmult",scope="hand", val="acc",gate="acc>1",           ref=4400}})
E("j_loyalty_card", {{kind="xmult",scope="hand", val=4,   gate="every_6th_hand",   ref=4006}})
for _, k in ipairs{"j_ceremonial","j_swashbuckler","j_trousers","j_ride_the_bus","j_flash","j_popcorn","j_green_joker","j_red_card"} do
  E(k, {{kind="mult", scope="hand", val="acc", gate="acc>0", ref=4322}})
end
for _, k in ipairs{"j_constellation","j_vampire","j_hologram","j_obelisk","j_lucky_cat","j_campfire",
  "j_glass","j_hit_the_road","j_madness","j_ramen","j_throwback","j_yorick"} do
  E(k, {{kind="xmult", scope="hand", val="acc", gate=nil, ref=4027}})
end

E("j_photograph",   {{kind="xmult",scope="card", val=2,  gate="first_face_only", ref=3472, at_most_once=true}})
E("j_idol",         {{kind="xmult",scope="card", val=2,  gate="rank+suit_of_the_round", ref=3506}})
E("j_scary_face",   {{kind="chips",scope="card", val=30, gate="face",  ref=3515}})
E("j_smiley",       {{kind="mult", scope="card", val=5,  gate="face",  ref=3522}})
E("j_scholar",      {{kind="chips",scope="card", val=20, gate="ace",   ref=3538},
                     {kind="mult", scope="card", val=4,  gate="ace",   ref=3538}})
E("j_walkie_talkie",{{kind="chips",scope="card", val=10, gate="10_or_4", ref=3546},
                     {kind="mult", scope="card", val=4,  gate="10_or_4", ref=3546}})
E("j_fibonacci",    {{kind="mult", scope="card", val=8,  gate="A2358", ref=3564}})
E("j_even_steven",  {{kind="mult", scope="card", val=4,  gate="even",  ref=3575}})
E("j_odd_todd",     {{kind="chips",scope="card", val=31, gate="odd",   ref=3585}})
for _, s in ipairs{ {"j_greedy_joker","Diamonds"},{"j_lusty_joker","Hearts"},
  {"j_wrathful_joker","Spades"},{"j_gluttenous_joker","Clubs"} } do
  E(s[1], {{kind="mult", scope="card", val=3, gate="suit:"..s[2], ref=3596}})
end
E("j_onyx_agate",   {{kind="mult", scope="card", val=7,  gate="suit:Clubs",  ref=3612}})
E("j_arrowhead",    {{kind="chips",scope="card", val=50, gate="suit:Spades", ref=3619}})
E("j_bloodstone",   {{kind="xmult",scope="card", val=1.5,gate="suit:Hearts+odds 1in2", ref=3626, prob=0.5}})
E("j_ancient",      {{kind="xmult",scope="card", val=1.5,gate="suit_of_the_round", ref=3634}})
E("j_triboulet",    {{kind="xmult",scope="card", val=2,  gate="K_or_Q", ref=3641}})

E("j_shoot_the_moon",{{kind="mult",scope="held", val=13, gate="Queen", ref=3651, note="h_mult hardcoded 13"}})
E("j_baron",        {{kind="xmult",scope="held", val=1.5,gate="King",  ref=3666}})
E("j_raised_fist",  {{kind="mult", scope="held", val="2*nominal", gate="lowest_held_only", ref=3699, at_most_once=true}})

E("j_baseball",     {{kind="xmult",scope="joker",val=1.5,gate="uncommon_joker", ref=3780}})

E("j_sock_and_buskin",{{kind="reps",scope="retrigger",val=1,gate="played face", ref=3727}})
E("j_hanging_chad", {{kind="reps",scope="retrigger",val=2,gate="first scoring card", ref=3735}})
E("j_dusk",         {{kind="reps",scope="retrigger",val=1,gate="last hand", ref=3743}})
E("j_selzer",       {{kind="reps",scope="retrigger",val=1,gate="every scoring card, 10 hands", ref=3750}})
E("j_hack",         {{kind="reps",scope="retrigger",val=1,gate="2345", ref=3757}})
E("j_mime",         {{kind="reps",scope="retrigger",val=1,gate="held cards", ref=3770}})

return T
