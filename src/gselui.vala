using Gtk;

namespace Gsel {
	public delegate void StringFn(string x);
	public delegate void IntFn(int x);
	public delegate void VoidFn(int x);

	public void initialize() {
		string[] args = {};
		unowned string[] _args = args;
		Gtk.init (ref _args);
		stdout.printf("GUI initialize()\n");
	}

	public void show(StringFn query_changed, IntFn selection_changed, VoidFn selection_made) {
		var window = new Window ();
		window.title = "First GTK+ Program";
		window.border_width = 10;
		window.window_position = WindowPosition.CENTER;
		window.set_default_size (350, 70);
		window.destroy.connect (Gtk.main_quit);

		var button = new Button.with_label ("Click me!");
		button.clicked.connect (() => {
			button.label = "Thank you";
		});

		// window.add (button);

		var entry = new Entry ();
		entry.text = "hai";
		window.add (entry);

		window.show_all ();
		stdout.printf("gtk main()\n");

		Gtk.main ();
	}

	public void set_query(string text) {
		stdout.printf("TODO: set_query\n");
	}

	public void set_results(string[] markup, int selected) {
		stdout.printf("TODO: set_results\n");
	}

	public void hide() {
		stdout.printf("TODO: hide\n");
	}
}
