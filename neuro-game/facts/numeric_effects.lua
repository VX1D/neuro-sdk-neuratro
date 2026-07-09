-- in facts/ (not context/) so pure fact extractors can read it without an upward facts->context dep
return {
  { field = "x_mult",  skip = 1, pre = "x", suf = " Mult", type_cond = true },
  { field = "mult",    skip = 0, pre = "+", suf = " Mult" },
  { field = "chips",   skip = 0, pre = "+", suf = " Chips" },
  { field = "h_mult",  skip = 0, pre = "+", suf = " Mult (held in hand)" },
  { field = "h_mod",   skip = 0, pre = "+", suf = " Chips (held in hand)" },
  { field = "c_mult",  skip = 0, pre = "+", suf = " Mult/card" },
  { field = "t_mult",  skip = 0, pre = "+", suf = " Mult", cond = true },
  { field = "t_chips", skip = 0, pre = "+", suf = " Chips", cond = true },
  { field = "d_mult",  skip = 0, pre = "+", suf = " Mult/discard" },
  { field = "s_mult",  skip = 0, pre = "+", suf = " Mult(conditional)" },
  { field = "p_mult",  skip = 0, pre = "+", suf = " Mult/played" },
  { field = "x_chips", skip = 1, pre = "x", suf = " Chips" },
}
