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

	public void initialize() {
		string[] args = {};
		unowned string[] _args = args;
		Gtk.init (ref _args);
		stdout.printf("GUI initialize()\n");
	}

	public struct State {
		StringFn query_changed;
		ResultIterFn iter;
		IntFn selection_changed;
		VoidFn selection_made;
		VoidFn exit;
		UiThread* thread;
	}

	public class UiThread : Object {
		private State state;
		private Thread<void*> thread;
		private Entry entry;
		private Gtk.Window window;
		private Gtk.ListStore list_store;
		private TreeView tree_view;
		private bool hidden;

		public UiThread(State state) {
			this.state = state;
			this.hidden = false;
			this.window = new Gtk.Window ();
			this.window.title = "First GTK+ Program";
			this.window.border_width = 10;
			this.window.window_position = WindowPosition.CENTER;
			this.window.set_default_size (350, 70);
			this.window.destroy.connect (Gtk.main_quit);
			this.window.key_press_event.connect(this.on_window_key);
			this.window.add_events(EventMask.KEY_PRESS_MASK);

			this.entry = new Entry ();
			this.entry.changed.connect((_) => {
				this.state.query_changed(entry.get_text());
			});

			this.list_store = this.init_list_store();
			this.tree_view = this.init_tree_view(this.list_store);

			// The Box:
			Gtk.Box box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
			box.pack_start (this.entry, false, true, 10);
			box.pack_start (this.tree_view, true, true, 10);

			this.window.add(box);
			this.window.show_all ();
			this.thread = new Thread<void*>("gtk", this.run);
		}

		private Gtk.ListStore init_list_store() {
			return new Gtk.ListStore(1, typeof (string));
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
			cell.set ("weight_set", true);
			cell.set ("weight", 700);

			view.insert_column_with_attributes (-1, "Item", cell, "markup", 0);
			return view;
		}

		private void on_selection_changed(Gtk.TreeSelection selection) {
			this.state.selection_changed(this.get_selected_idx(selection));
		}

		private void on_selection_made(Gtk.TreePath path, TreeViewColumn column) {
			this.state.selection_made();
		}

		private int get_selected_idx(Gtk.TreeSelection selection) {
			Gtk.TreeModel model;
			Gtk.TreeIter iter;
			if (selection.get_selected (out model, out iter)) {
				TreePath path = model.get_path(iter);
				if(path != null) {
					int idx = path.get_indices()[0];
					stdout.printf("Selection is currently %d\n", idx);
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
					Gtk.main_quit();
					break;
				case Key.Return:
					this.state.selection_made();
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
			stdout.printf("running gtk main()\n");
			caml_c_thread_register();
			Gtk.main();
			stdout.printf("gtk main() returned\n");
			if (!this.hidden) {
				stdout.printf("exiting\n");
				this.state.exit();
			}
			caml_c_thread_unregister();
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
			Idle.add(() => {
				stdout.printf("hiding window\n");
				this.hidden = true;
				this.window.destroy();
				return Source.REMOVE;
			});
		}

		public void join() {
			this.thread.join();
		}
	}

	public State? show(
			StringFn query_changed,
			ResultIterFn iter,
			IntFn selection_changed,
			VoidFn selection_made,
			VoidFn exit) {
		var state = State () {
			query_changed = query_changed,
			iter = iter,
			selection_changed = selection_changed,
			selection_made = selection_made,
			exit = exit
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
		state.thread->hide();
	}

	public void wait(State state) {
		state.thread->join();
	}
}
