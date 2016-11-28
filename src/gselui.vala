using Gtk;

// ocaml needs to know about threads which will
// call ocaml callbacks
extern void caml_c_thread_register();
extern void caml_c_thread_unregister();

namespace Gsel {

	[CCode (has_target = false)]
	public delegate void StringFn(string x);

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

		public void set_query(string text) {
			var ownText = text.dup();
			Idle.add(() => {
				this.entry.text = ownText;
				return Source.REMOVE;
			});
		}

		public void set_results(string[] results) {
			/* var ownResults = results.dup(); */
			Idle.add(() => {
				this.entry.text = "TODO";
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

	public State? show(StringFn query_changed, IntFn selection_changed, VoidFn selection_made, VoidFn exit) {
		var state = State () {
			query_changed = query_changed,
			selection_changed = selection_changed,
			selection_made = selection_made,
			exit = exit
		};
		state.thread = new UiThread(state);
		return state;
	}

	public void set_query(State state, string text) {
		state.thread->set_query(text);
	}

	public void set_results(State state, string[] markup, int selected) {
		stdout.printf("TODO: set_results\n");
	}

	public void hide(owned State state) {
		state.thread->hide();
	}

	public void wait(State state) {
		state.thread->join();
	}
}
