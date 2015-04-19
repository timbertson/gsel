#!/bin/bash
exec ocamlbrowser \
	-I "$(ocamlfind query lablgtk2)" \
	-I "$(ocamlfind query oUnit)" \
	-I "$(ocamlfind query xlib)" \
	;
