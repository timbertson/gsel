using Gtk;

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
		private Window window;
		private bool hidden;
		private int selected;

		public UiThread(State state) {
			this.state = state;
			this.hidden = false;
			this.window = new Window ();
			this.window.title = "First GTK+ Program";
			this.window.border_width = 10;
			this.window.window_position = WindowPosition.CENTER;
			this.window.set_default_size (350, 70);
			this.window.destroy.connect (Gtk.main_quit);

			this.entry = new Entry ();
			this.entry.changed.connect((_) => {
				this.state.query_changed(entry.get_text());
			});
			this.window.add (this.entry);

			this.window.show_all ();
			this.thread = new Thread<void*>("gtk", this.run);
		}

		public void* run() {
			stdout.printf("running gtk main()\n");
			caml_c_thread_register();
			Gtk.main();
			stdout.printf("gtk main() returned\n");
			if (!this.hidden) {
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
				this.selected = this.state.iter((item) => {
					/* foreach (string result in results) { */
						stdout.printf("TODO: result %s (%x)\n", item, (int)item);
					/* } */
				});
				return Source.REMOVE;
			});
		}

		public void hide() {
			Idle.add(() => {
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

	/* public void update_results(State state, int selected) { */
	/* 	string[] owned_items = new string[len]; */
	/* 	for (int i=0; i<len; i++) { */
	/* 		owned_items[i] = items[i].dup(); */
	/* 	} */
	/* 	state.thread->set_results(owned_items, selected); */
	/* } */

	public void hide(owned State state) {
		state.thread->hide();
	}

	public void wait(State state) {
		state.thread->join();
	}
}
