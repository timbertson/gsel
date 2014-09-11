open GMain
open Lwt

module SortedSet = struct
  type t = string list
  let score = String.length
  let create () : t = []
  let rec add (existing : t) (elem : string) =
    match existing with
      | [] -> [elem]
      | head :: tail ->
          if elem = head then existing (* ignore duplicates *) else
            if (score elem) < (score head)
              then elem :: existing
              else head :: (add tail elem)
end

let main () =
  ignore (GMain.init ());
  Lwt_glib.install ();

  let gui_end, wakener = Lwt.wait () in
  let quit = Lwt.wakeup wakener in
  let quit () = Lwt.wakeup wakener (); exit 0 in

  let window = GWindow.window
    ~border_width: 10
    ~screen:(Gdk.Screen.default ())
    ~decorated: false
    ~position: `CENTER
    ~title:"gsel"
    () in
  (* window#set_default_size ~width:600 ~height:400; *)
  let vbox = GPack.vbox ~spacing: 10 ~width:500 ~packing:window#add () in
  let input = GEdit.entry ~activates_default: true ~packing:vbox#pack () in
  let glist = GList.liste ~packing:vbox#pack () in
  glist#set_selection_mode `NONE;

  let all_items = ref (SortedSet.create ()) in
  let shown_items = ref [] in
  let last_query = ref "" in

  let matches needle haystack =
    (* print_endline ("Looking for "^ needle ^" in "^haystack); *)
    let nl = String.length needle in
    let hl = String.length haystack in
    let rec loop (nh, ni) (hh, hi) =
      if nh = hh then (
          (* move on to next search character *)
          let ni = succ ni
          and hi = succ hi in
          if (ni = nl) then true else
            if (hi = hl) then false else
              loop (String.get needle ni, ni) (String.get haystack hi, hi)
      ) else (
          (* move on to next potential character *)
          let hi = succ hi in
          if (hi = hl) then false else
            loop (nh, ni) (String.get haystack hi, hi)
      )
    in
    if nl = 0 then true else
      if hl = 0 then false else
        loop (String.get needle 0, 0) (String.get haystack 0, 0)
  in


  (* let last_redraw = ref 0.0 in *)
  let redraw () =
    (* let current_time = Sys.time () in *)
    (* let diff = current_time -. !last_redraw in *)
    (* if force || diff > 0.5 then begin *)
    (*   last_redraw := current_time; *)
    glist#clear_items ~start:0 ~stop:(List.length glist#children);
    shown_items := List.filter (fun item ->
      matches !last_query item
    ) !all_items;
    Printf.printf "redraw! %d items of %d\n" (List.length !shown_items) (List.length !all_items);
    flush stdout;
    List.iteri (fun i label ->
      if i < 20 then
        let (_:GList.list_item) = GList.list_item ~label ~packing:glist#append () in
        ()
    ) !shown_items
    (* end *)
    (* else print_endline ("Skipping redraw..." ^ (string_of_float diff)) *)
  in

  let update_query = fun text ->
    last_query := text;
    redraw ()
  in

  let input_loop =
    let read_loop =
      let lines = Lwt_io.read_lines Lwt_io.stdin in
      Lwt_stream.iter (fun line ->
        all_items := SortedSet.add !all_items line;
      ) lines
    in
    let update_loop =
      lwt () = Lwt_unix.sleep 0.5 in
      redraw ();
      return_unit
    in
    Lwt.pick [read_loop; update_loop]
  in

  input#connect#notify_text update_query;
  update_query "";

  let (esc, _) = GtkData.AccelGroup.parse "Escape" in
  let (ret, _) = GtkData.AccelGroup.parse "Return" in
  window#event#connect#key_release (fun evt ->
    let key = GdkEvent.Key.keyval evt in
    (* XXX constant / enum somewhere? *)
    Printf.printf "Key: %d\n" key;
    let () = match key with
      |k when k=esc -> quit ()
      |k when k=ret ->
        let selected = try Some (List.hd !shown_items) with Failure _ -> None in
        begin match selected with
          | Some str -> print_endline str; quit ()
          | None -> ()
        end
      | _ -> ()
    in
    true
  );

  window#event#connect#delete ~callback:(fun _ -> quit (); true);
  window#set_skip_taskbar_hint true;
  (* window#set_skip_pager_hint true; *)
  window#connect#destroy ~callback:quit;
  (* button#connect#clicked ~callback:(fun () -> prerr_endline "Hello World"); *)
  (* button#connect#clicked ~callback:window#destroy; *)
  window#show ();
  (* Main.main () *)

  Lwt_main.run (Lwt.join [
    gui_end;
    input_loop;
  ]);
  print_endline "ALL DONE"

let _ = Printexc.print main ()
