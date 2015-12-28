function complete_with_gsel
	set arg (commandline --current-token)
	if test -z $arg
		return
	end

	# remove trailing slash
	set arg (echo $arg | sed -e "s!/\$!!")

	# XXX can't get fish to expand ~ in a string, so hack it up:
	set base (echo $arg | sed -e "s!^~/!$HOME/!")
	if not test -d $base
		set arg (dirname $arg)
		set base (dirname $base)
	end
	# echo "BASE: $base" >> /tmp/fish-gsel-log

	if not pushd $arg ^/dev/null
		return
	end

	set -l dest (find -printf '%P\n' ^/dev/null | sed -e 's!^\./!!' | gsel --client)
	popd ^/dev/null

	if test -z $dest
		# echo "FAILED" >> /tmp/fish-gsel-log
		return
	end

	# echo "COMPLETED: $dest" >> /tmp/fish-gsel-log
	commandline --current-token $arg/$dest
end


# Suggested:
# bind \cf complete_with_gsel
