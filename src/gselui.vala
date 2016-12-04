using Gtk;
using Gdk;

// ocaml needs to know about threads which will
// call ocaml callbacks
extern void caml_c_thread_register();
extern void caml_c_thread_unregister();

namespace Gsel {

	[CCode (has_target = false)]
	public delegate void StringFn(string x);

	[CCode (has_target = true)]
	public delegate void StringClosure(string x);

	[CCode (has_target = false)]
	public delegate int ResultIterFn(StringClosure f);

	[CCode (has_target = false)]
	public delegate void IntFn(int x);

	[CCode (has_target = false)]
	public delegate void VoidFn();

	[CCode (has_target = false)]
	public delegate void BoolFn(bool x);

	public void initialize() {
		string[] args = {};
		unowned string[] _args = args;
		Gtk.init (ref _args);
	}

	public struct State {
		StringFn query_changed;
		ResultIterFn iter;
		IntFn selection_changed;
		BoolFn completed;
		UiThread* thread;
	}

	public class UiThread : Object {
		private State state;
		private Thread<void*> thread;
		private Entry entry;
		private Gtk.Window window;
		private Gtk.ListStore list_store;
		private TreeView tree_view;
		private bool completed;

		public UiThread(State state) {
			this.state = state;
			this.completed = false;

			var css = init_style();

			this.window = this.init_window();
			this.style(this.window, css);
			this.entry = this.init_entry();
			this.style(this.entry, css);
			this.list_store = this.init_list_store();
			this.tree_view = this.init_tree_view(this.list_store);
			this.style(this.tree_view, css);

			Gtk.Box box = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
			box.pack_start (this.entry, false, true, 0);
			box.pack_start (this.tree_view, true, true, 0);

			Gtk.Settings.get_default().set("gtk-application-prefer-dark-theme", true);

			this.window.add(box);
			this.window.show_all ();
			this.thread = new Thread<void*>("gtk", this.run);
		}

		private Gtk.ListStore init_list_store() {
			return new Gtk.ListStore(1, typeof (string));
		}

		private Gtk.Window init_window() {
			var window = new Gtk.Window ();
			window.title = "gsel";
			window.border_width = 10;
			window.window_position = WindowPosition.CENTER;
			window.set_default_size (600, 600);
			window.resizable = false;
			window.destroy.connect(on_window_destroy);
			window.key_press_event.connect(this.on_window_key);
			window.add_events(EventMask.KEY_PRESS_MASK);
			window.focus_on_map = true;
			window.decorated = false;
			window.type_hint = Gdk.WindowTypeHint.DIALOG;
			window.modal = true;
			window.destroy_with_parent = true;
			window.skip_pager_hint = true;
			window.skip_taskbar_hint = true;
			window.window_position = WindowPosition.CENTER_ON_PARENT;

			window.realize.connect(() => {
				var screen = Gdk.Screen.get_default();
				if (screen != null) {
					var parent = screen.get_active_window();
					if (parent != null) {
						var gdk_window = window.get_window();
						if (gdk_window != null) {
							// stderr.printf("setting transient\n");
							gdk_window.set_transient_for(parent);
						}
					}
				}
			});

			return window;
		}

		private CssProvider init_style() {
			var provider = new CssProvider();
			provider.load_from_data("""
				window {
					font-size: 18px;
					background: rgb(20,20,20);
				}
				entry {
					font-size: 16px;
					padding: 3px 10px;
					background: rgb(40,40,40);
					color: rgb(250, 250, 250);
				}
				treeview {
					background: rgb(25, 25, 25);
					color: rgb(200, 200, 200);
				}
				treeview:selected {
					background: rgb(61, 85, 106);
				}
			""");
			return provider;
		}

		private void style(Gtk.Widget w, CssProvider css) {
			w.get_style_context().add_provider(css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
		}

		private Gtk.Entry init_entry() {
			var entry = new Entry ();
			entry.changed.connect((_) => {
				this.state.query_changed(entry.get_text());
			});
			return entry;
		}

		private Gtk.TreeView init_tree_view(Gtk.ListStore store) {
			var view = new Gtk.TreeView.with_model(store);
			view.expand = true;
			view.enable_search = false;
			view.fixed_height_mode = true;
			view.headers_visible = false;
			view.hover_selection = true;

			view.activate_on_single_click = true;
			view.row_activated.connect(this.on_selection_made);

			var selection = view.get_selection();
			selection.mode = SelectionMode.BROWSE;
			selection.changed.connect (this.on_selection_changed);

			var cell = new Gtk.CellRendererText();
			cell.ellipsize = Pango.EllipsizeMode.START;

			view.insert_column_with_attributes (-1, "Item", cell, "markup", 0);
			return view;
		}

		private void on_selection_changed(Gtk.TreeSelection selection) {
			this.state.selection_changed(this.get_selected_idx(selection));
		}

		private void on_window_destroy(Gtk.Widget window) {
			// stderr.printf("on_window_destroy\n");
			this.complete(false);
		}

		private void on_selection_made(Gtk.TreePath path, TreeViewColumn column) {
			// stderr.printf("on_selection_made()\n");
			this.complete(true);
			this.do_hide();
		}

		private void cancel() {
			// stderr.printf("cancel()\n");
			this.complete(false);
			this.do_hide();
		}

		private void complete(bool selection_accepted) {
			// window gets nulled by this.do_hide(),
			// to ensure we don't double-call
			// stderr.printf("complete() [completed=%s]\n", this.completed ? "true" : "false");
			if (!this.completed) {
				this.completed = true;
				this.state.completed(selection_accepted);
			}
		}

		private int get_selected_idx(Gtk.TreeSelection selection) {
			Gtk.TreeModel model;
			Gtk.TreeIter iter;
			if (selection.get_selected (out model, out iter)) {
				TreePath path = model.get_path(iter);
				if(path != null) {
					int idx = path.get_indices()[0];
					return idx;
				}
			}
			return 0;
		}

		private void shift_selection(int diff) {
			var selection = this.tree_view.get_selection();
			this.set_selection(this.get_selected_idx(selection) + diff);
		}

		private void set_selection(int idx) {
			var selection = this.tree_view.get_selection();
			var path = new TreePath.from_indices(idx);
			selection.select_path(path);
		}

		private bool on_window_key(Gdk.EventKey key) {
			var HANDLED = true;
			var PROPAGATE = false;

			switch (key.keyval) {
				case Key.Escape:
					this.cancel();
					break;
				case Key.Return:
					this.state.completed(true);
					break;
				case Key.Up:
					this.shift_selection(-1);
					break;
				case Key.Down:
					this.shift_selection(1);
					break;
				case Key.Page_Up:
					this.set_selection(0);
					break;
				case Key.Page_Down:
					var num_items = this.list_store.iter_n_children(null);
					this.set_selection(int.max(0, num_items - 1));
					break;
				default:
					if ((key.state & ModifierType.CONTROL_MASK) != 0) {
						switch(key.keyval) {
							case Key.j:
								this.shift_selection(1);
								break;
							case Key.k:
								this.shift_selection(-1);
								break;
							default:
								return PROPAGATE;
						}
						return HANDLED;
					} else {
						return PROPAGATE;
					}
			}
			return HANDLED;
		}

		public void* run() {
			// stderr.printf("running gtk main()\n");
			caml_c_thread_register();
			Gtk.main();
			caml_c_thread_unregister();
			// stderr.printf("gtk main() returned\n");
			return null;
		}

		public void set_query(owned string text) {
			Idle.add(() => {
				this.entry.text = text;
				return Source.REMOVE;
			});
		}

		public void results_changed() {
			Idle.add(() => {
				this.list_store.clear();
				var selected = this.state.iter((item) => {
					Gtk.TreeIter iter;
					this.list_store.append(out iter);
					this.list_store.set(iter, 0, item);
				});
				this.set_selection(selected);
				return Source.REMOVE;
			});
		}

		public void hide() {
			// initiated by ocaml - no need to call complete()
			// stderr.printf("gsel.thread.hide()\n");
			Idle.add(() => {
				this.do_hide();
				return Source.REMOVE;
			});
		}

		private void do_hide() {
			// stderr.printf("gsel.thread.do_hide() [window=%x]\n", (int)this.window);
			if (this.window != null) {
				var window = this.window;
				this.window = null;
				window.destroy();
			}
			Gtk.main_quit();
		}

		public void join() {
			// stderr.printf("joining GTK thread\n");
			this.thread.join();
			// stderr.printf("GTK thread joined\n");
		}
	}

	public State? show(
			StringFn query_changed,
			ResultIterFn iter,
			IntFn selection_changed,
			BoolFn completed) {
		var state = State () {
			query_changed = query_changed,
			iter = iter,
			selection_changed = selection_changed,
			completed = completed
		};
		state.thread = new UiThread(state);
		return state;
	}

	public void set_query(State state, string text) {
		state.thread->set_query(text.dup());
	}

	public void results_changed(State state) {
		state.thread->results_changed();
	}

	public void hide(owned State state) {
		// stderr.printf("gsel_hide()\n");
		state.thread->hide();
	}

	public void wait(State state) {
		state.thread->join();
	}
}
