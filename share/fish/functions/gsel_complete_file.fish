function gsel_complete_file
	set -l tok (commandline --current-token)
	if test -n $tok
		if not test -d $tok
			# assume half-completed filename, use the parent
			set -l tok (dirname $tok)
		end
	else
		set -l tok "."
	end
	pushd $tok
	or return 1

	set -l rv (find -printf '%P\n' | gsel)
	set -l stat = $status
	popd $tok
	if test $stat -eq 0
		commandline --replace --current-token $tok/$rv" "
	end
end

bind \cf gsel_complete_file
