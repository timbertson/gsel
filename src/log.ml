let enable_debug = ref false
let debug fmt =
  if !enable_debug
    then (prerr_string "[gsel]: "; Printf.kfprintf (fun ch -> output_char ch '\n'; flush ch) stderr fmt)
    else Printf.ifprintf stderr fmt


