#define WNCK_I_KNOW_THIS_IS_UNSTABLE

#include <stdio.h>
#include <stdlib.h>
#include <libwnck/libwnck.h>
#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <X11/X.h>

#define NOT_NULL(x) {if(x == NULL) { fprintf(stderr, "ERROR: " #x " is null\n"); exit(1); }};

CAMLprim value ml_wnck_get_active_xid() {
	WnckScreen * screen = wnck_screen_get_default();
	gulong xid = 0;
	if(screen != NULL) {
		wnck_screen_force_update(screen);
		WnckWindow * prev = wnck_screen_get_active_window(screen);
		if(prev != NULL) {
			xid = wnck_window_get_xid(prev);
		}
	}
	return caml_copy_int32(xid);
}

void ml_wnck_activate_xid(value xid_value, value timestamp_val) {
	gulong xid = Int32_val(xid_value);
	WnckWindow * win = wnck_window_get(xid);
	if(win != NULL) {
		guint timestamp = Int32_val(timestamp_val);
		/* fprintf(stderr, "Activating @ ts=%u\n", timestamp); */
		wnck_window_activate(win, timestamp);
	/*
	} else {
		fprintf(stderr, "Can't activate, NULL window for xid %ld\n", xid);
	*/
	}
	return;
}
