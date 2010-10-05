#! /bin/sh
#
#  Copyright (c) 2010 Gordon Tetlow
#  All rights reserved.
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions
#  are met:
#  1. Redistributions of source code must retain the above copyright
#     notice, this list of conditions and the following disclaimer.
#  2. Redistributions in binary form must reproduce the above copyright
#     notice, this list of conditions and the following disclaimer in the
#     documentation and/or other materials provided with the distribution.
#
#  THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
#  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
#  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
#  ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
#  FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
#  DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
#  OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
#  HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
#  LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
#  OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
#  SUCH DAMAGE.
#
# $FreeBSD$

# Usage: add_to_manpath path
# Adds a variable to manpath while ensuring we don't have duplicates.
# Returns true if we were able to add something. False otherwise.
add_to_manpath() {
	case "$manpath" in
	*:$1)	decho "  Skipping duplicate manpath entry $1" 2 ;;
	$1:*)	decho "  Skipping duplicate manpath entry $1" 2 ;;
	*:$1:*)	decho "  Skipping duplicate manpath entry $1" 2 ;;
	*)	if [ -d "$1" ]; then
			decho "  Adding $1 to manpath"
			manpath="$manpath:$1"
			return 0
		fi
		;;
	esac

	return 1
}

# Usage: build_manlocales
# Builds a correct MANLOCALES variable.
build_manlocales() {
	# If the user has set manlocales, who are we to argue.
	if [ -n "$MANLOCALES" ]; then
		return
	fi

	parse_configs

	# Trim leading colon
	MANLOCALES=${manlocales#:}

	decho "Available manual locales: $MANLOCALES"
}

# Usage: build_manpath
# Builds a correct MANPATH variable.
build_manpath() {
	local IFS

	# If the user has set a manpath, who are we to argue.
	if [ -n "$MANPATH" ]; then
		return
	fi

	search_path

	decho "Adding default manpath entries"
	IFS=:
	for path in $man_default_path; do
		add_to_manpath "$path"
	done
	unset IFS

	parse_configs

	# Trim leading colon
	MANPATH=${manpath#:}

	decho "Using manual path: $MANPATH"
}

# Usage: check_cat catglob
# Checks to see if a cat glob is available.
check_cat() {
	if exists "$1"; then
		use_cat=yes
		catpage=$found
		decho "    Found catpage $catpage"
		return 0
	else
		return 1
	fi
}

# Usage: check_man manglob catglob
# Given 2 globs, figures out if the manglob is available, if so, check to
# see if the catglob is also available and up to date.
check_man() {
	if exists "$1"; then
		# We have a match, check for a cat page
		manpage=$found
		decho "    Found manpage $manpage"

		if exists "$2" && is_newer $found $manpage; then
			# cat page found and is newer, use that
			use_cat=yes
			catpage=$found
			decho "    Using catpage $catpage"
		else
			# no cat page or is older
			unset use_cat
			decho "    Skipping catpage: not found or old"
		fi
		return 0
	fi

	return 1
}

# Usage: decho "string" [debuglevel]
# Echoes to stderr string prefaced with -- if high enough debuglevel.
decho() {
	if [ $debug -ge ${2:-1} ]; then
		echo "-- $1" >&2
	fi
}

# Usage: exists glob
# Returns true if glob resolves to a real file.
exists() {
	local IFS

	# Don't accidentally inherit callers IFS (breaks perl manpages)
	unset IFS

	# Use some globbing tricks in the shell to determine if a file
	# exists or not.
	set +f
	set -- "$1" $1
	set -f

	if [ "$1" != "$2" -a -r "$2" ]; then
		found="$2"
		return 0
	fi

	return 1
}

# Usage: find_file path section subdir pagename
# Returns: true if something is matched and found.
# Search the given path/section combo for a given page.
find_file() {
	local manroot catroot mann man0 catn cat0

	manroot="$1/man$2"
	catroot="$1/cat$2"
	if [ -n "$3" ]; then
		manroot="$manroot/$3"
		catroot="$catroot/$3"
	fi

	if [ ! -d "$manroot" ]; then
		return 1
	fi
	decho "  Searching directory $manroot" 2

	mann="$manroot/$4.$2*"
	man0="$manroot/$4.0*"
	catn="$catroot/$4.$2*"
	cat0="$catroot/$4.0*"

	# This is the behavior as seen by the original man utility.
	# Let's not change that which doesn't seem broken.
	if check_man "$mann" "$catn"; then
		return 0
	elif check_man "$man0" "$cat0"; then
		return 0
	elif check_cat "$catn"; then
		return 0
	elif check_cat "$cat0"; then
		return 0
	fi

	return 1
}

# Usage: is_newer file1 file2
# Returns true if file1 is newer than file2 as calculated by mtime.
is_newer() {
	if [ $(stat -f %m $1) -gt $(stat -f %m $2) ]; then
		decho "    mtime: $1 newer than $2" 3
		return 0
	else
		decho "    mtime: $1 older than $2" 3
		return 1
	fi
}

# Usage: manpath_parse_args "$@"
# Parses commandline options for manpath.
manpath_parse_args() {
	local cmd_arg

	while getopts 'Ldq' cmd_arg; do
		case "${cmd_arg}" in
		L)	Lflag=Lflag ;;
		d)	debug=$(( $debug + 1 )) ;;
		q)	qflag=qflag ;;
		*)	manpath_usage ;;
		esac
	done >&2
}

# Usage: manpath_usage
# Display usage for the manpath(1) utility.
manpath_usage() {
	echo 'usage: manpath [-Ldq]' >&2
	exit 1
}

# Usage: manpath_warnings
# Display some warnings to stderr.
manpath_warnings() {
	if [ -z "$Lflag" -a -n "$MANPATH" ]; then
		echo "(Warning: MANPATH environment variable set)" >&2
	fi

	if [ -n "$Lflag" -a -n "$MANLOCALES" ]; then
		echo "(Warning: MANLOCALES environment variable set)" >&2
	fi
}

# Usage: man_display_page
# Display either the manpage or catpage depending on the use_cat variable
man_display_page() {
	local EQN COL NROFF PIC TBL TROFF REFER VGRIND
	local IFS l nroff_dev pipeline preproc_arg tool

	# We are called with IFS set to colon. This causes really weird
	# things to happen for the variables that have spaces in them.
	unset IFS

	# If we are supposed to use a catpage and we aren't using troff(1)
	# just zcat the catpage and we are done.
	if [ -z "$tflag" -a -n "$use_cat" ]; then
		if [ -n "$wflag" ]; then
			echo "$catpage (source: $manpage)"
			ret=0
		else
			if [ $debug -gt 0 ]; then
				decho "Command: $ZCAT $catpage | $PAGER"
				ret=0
			else
				eval "$ZCAT $catpage | $PAGER"
				ret=$?
			fi
		fi
		return
	fi

	# Okay, we are using the manpage, do we just need to output the
	# name of the manpage?
	if [ -n "$wflag" ]; then
		echo "$manpage"
		ret=0
		return
	fi

	# So, we really do need to parse the manpage. First, figure out the
	# device flag (-T) we have to pass to eqn(1) and groff(1). Then,
	# setup the pipeline of commands based on the user's request.

	# Apparently the locale flags are switched on where the manpage is
	# found not just the locale env variables.
	nroff_dev="ascii"
	case "X${use_locale}X${manpage}" in
	XyesX*/${man_lang}*${man_charset}/*)
		# I don't pretend to know this; I'm just copying from the
		# previous version of man(1).
		case "$man_charset" in
		KOI8-R)		nroff_dev="koi8-r" ;;
		ISO8859-1)	nroff_dev="latin1" ;;
		ISO8859-15)	nroff_dev="latin1" ;;
		UTF-8)		nroff_dev="utf8" ;;
		*)		nroff_dev="ascii" ;;
		esac

		NROFF="$NROFF -T$nroff_dev -dlocale=$man_lang.$man_charset"
		EQN="$EQN -T$nroff_dev"

		# Allow language specific calls to override the default
		# set of utilities.
		l=$(echo $man_lang | tr [:lower:] [:upper:])
		for tool in EQN COL NROFF PIC TBL TROFF REFER VGRIND; do
			eval "$tool=\${${tool}_$l:-\$$tool}"
		done
		;;
	*)	NROFF="$NROFF -Tascii"
		EQN="$EQN -Tascii"
		;;
	esac

	if [ -n "$MANROFFSEQ" ]; then
		set -- -$MANROFFSEQ
		while getopts 'egprtv' preproc_arg; do
			case "${preproc_arg}" in
			e)	pipeline="$pipeline | $EQN" ;;
			g)	;; # Ignore for compatability.
			p)	pipeline="$pipeline | $PIC" ;;
			r)	pipeline="$pipeline | $REFER" ;;
			t)	pipeline="$pipeline | $TBL"; use_col=yes ;;
			v)	pipeline="$pipeline | $VGRIND" ;;
			*)	usage ;;
			esac
		done
		# Strip the leading " | " from the resulting pipeline.
		pipeline="${pipeline#" | "}"
	else
		pipeline="$TBL"
		use_col=yes
	fi

	if [ -n "$tflag" ]; then
		pipeline="$pipeline | $TROFF"
	else
		pipeline="$pipeline | $NROFF"

		if [ -n "$use_col" ]; then
			pipeline="$pipeline | $COL"
		fi

		pipeline="$pipeline | $PAGER"
	fi

	if [ $debug -gt 0 ]; then
		decho "Command: $ZCAT $manpage | $pipeline"
		ret=0
	else
		eval "$ZCAT $manpage | $pipeline"
		ret=$?
	fi
}

# Usage: man_find_and_display page
# Search through the manpaths looking for the given page.
man_find_and_display() {
	local found_page locpath p path sect

	IFS=:
	for sect in $MANSECT; do
		decho "Searching section $sect" 2
		for path in $MANPATH; do
			for locpath in $locpaths; do
				p=$path/$locpath
				p=${p%/.} # Rid ourselves of the trailing /.

				# Check if there is a MACHINE specific manpath.
				if find_file $p $sect $MACHINE "$1"; then
					found_page=yes
					man_display_page
					if [ -z "$aflag" ]; then
						return
					fi
				fi

				# Check if there is a MACHINE_ARCH
				# specific manpath.
				if find_file $p $sect $MACHINE_ARCH "$1"; then
					found_page=yes
					man_display_page
					if [ -z "$aflag" ]; then
						return
					fi
				fi

				# Check plain old manpath.
				if find_file $p $sect '' "$1"; then
					found_page=yes
					man_display_page
					if [ -z "$aflag" ]; then
						return
					fi
				fi
			done
		done
	done
	unset IFS

	# Nothing? Well, we are done then.
	if [ -z "$found_page" ]; then
		echo "No manual entry for $1" >&2
		ret=1
		return
	fi
}

# Usage: man_parse_args "$@"
# Parses commandline options for man.
man_parse_args() {
	local IFS cmd_arg

	while getopts 'M:P:S:adfhkm:op:tw' cmd_arg; do
		case "${cmd_arg}" in
		M)	MANPATH=$OPTARG ;;
		P)	PAGER=$OPTARG ;;
		S)	MANSECT=$OPTARG ;;
		a)	aflag=aflag ;;
		d)	debug=$(( $debug + 1 )) ;;
		f)	fflag=fflag ;;
		h)	man_usage 0 ;;
		k)	kflag=kflag ;;
		m)	mflag=$OPTARG ;;
		o)	oflag=oflag ;;
		p)	MANROFFSEQ=$OPTARG ;;
		t)	tflag=tflag ;;
		w)	wflag=wflag ;;
		*)	man_usage ;;
		esac
	done >&2

	shift $(( $OPTIND - 1 ))

	# Check the args for incompatible options.
	case "${fflag}${kflag}${tflag}${wflag}" in
	fflagkflag*)	echo "Incompatible options: -f and -k"; man_usage ;;
	fflag*tflag*)	echo "Incompatible options: -f and -t"; man_usage ;;
	fflag*wflag)	echo "Incompatible options: -f and -w"; man_usage ;;
	*kflagtflag*)	echo "Incompatible options: -k and -t"; man_usage ;;
	*kflag*wflag)	echo "Incompatible options: -k and -w"; man_usage ;;
	*tflagwflag)	echo "Incompatible options: -t and -w"; man_usage ;;
	esac

	# Short circuit for whatis(1) and apropos(1)
	if [ -n "$fflag" ]; then
		do_whatis "$@"
		exit
	fi

	if [ -n "$kflag" ]; then
		do_apropos "$@"
		exit
	fi

	IFS=:
	for sect in $man_default_sections; do
		if [ "$sect" = "$1" ]; then
			decho "Detected manual section as first arg: $1"
			MANSECT="$1"
			shift
			break
		fi
	done
	unset IFS

	pages="$*"
}

# Usage: man_setup
# Setup various trivial but essential variables.
man_setup() {
	# Setup machine and architecture variables.
	if [ -n "$mflag" ]; then
		MACHINE_ARCH=${mflag%%:*}
		MACHINE=${mflag##*:}
	fi
	if [ -z "$MACHINE_ARCH" ]; then
		MACHINE_ARCH=$(sysctl -n hw.machine_arch)
	fi
	if [ -z "$MACHINE" ]; then
		MACHINE=$(sysctl -n hw.machine)
	fi
	decho "Using architecture: $MACHINE_ARCH:$MACHINE"

	setup_pager

	# Setup manual sections to search.
	if [ -z "$MANSECT" ]; then
		MANSECT=$man_default_sections
	fi
	decho "Using manual sections: $MANSECT"

	build_manpath
	man_setup_locale
}

# Usage: man_setup_locale
# Setup necessary locale variables.
man_setup_locale() {
	# Setup locale information.
	if [ -n "$oflag" ]; then
		decho "Using non-localized manpages"
		unset use_locale
	elif [ -n "$LC_ALL" ]; then
		parse_locale "$LC_ALL"
	elif [ -n "$LC_CTYPE" ]; then
		parse_locale "$LC_CTYPE"
	elif [ -n "$LANG" ]; then
		parse_locale "$LANG"
	fi

	if [ -n "$use_locale" ]; then
		locpaths="${man_lang}_${man_country}.${man_charset}"
		locpaths="$locpaths:$man_lang.$man_charset"
		if [ "$man_lang" != "en" ]; then
			locpaths="$locpaths:en.$man_charset"
		fi
		locpaths="$locpaths:."
	else
		locpaths="."
	fi
	decho "Using locale paths: $locpaths"
}

# Usage: man_usage [exitcode]
# Display usage for the man utility.
man_usage() {
	echo 'Usage:'
	echo ' man [-adho] [-t | -w] [-M manpath] [-P pager] [-S mansect]'
	echo '     [-m arch[:machine]] [-p [eprtv]] [mansect] page [...]'
	echo ' man -f page [...] -- Emulates whatis(1)'
	echo ' man -k page [...] -- Emulates apropos(1)'

	# When exit'ing with -h, it's not an error.
	exit ${1:-1}
}

# Usage: parse_configs
# Reads the end-user adjustable config files.
parse_configs() {
	local IFS file files

	if [ -n "$parsed_configs" ]; then
		return
	fi

	unset IFS

	# Read the global config first in case the user wants
	# to override config_local.
	if [ -r "$config_global" ]; then
		parse_file "$config_global"
	fi

	# Glob the list of files to parse.
	set +f
	files=$(echo $config_local)
	set -f

	for file in $files; do
		if [ -r "$file" ]; then
			parse_file "$file"
		fi
	done

	parsed_configs='yes'
}

# Usage: parse_file file
# Reads the specified config files.
parse_file() {
	local file line tstr var

	file="$1"
	decho "Parsing config file: $file"
	while read line; do
		decho "  $line" 2
		case "$line" in
		\#*)		decho "    Comment" 3
				;;
		MANPATH*)	decho "    MANPATH" 3
				trim "${line#MANPATH}"
				add_to_manpath "$tstr"
				;;
		MANLOCALE*)	decho "    MANLOCALE" 3
				trim "${line#MANLOCALE}"
				manlocales="$manlocales:$tstr"
				;;
		MANCONFIG*)	decho "    MANCONFIG" 3
				trim "${line#MANCONF}"
				config_local="$tstr"
				;;
		# Set variables in the form of FOO_BAR
		*_*[\ \	]*)	var="${line%%[\ \	]*}"
				trim "${line#$var}"
				eval "$var=\"$tstr\""
				decho "    Parsed $var" 3
				;;
		esac
	done < "$file"
}

# Usage: parse_locale localestring
# Setup locale variables for proper parsing.
parse_locale() {
	local lang_cc

	case "$1" in
	C)				;;
	POSIX)				;;
	[a-z][a-z]_[A-Z][A-Z]\.*)	lang_cc="${1%.*}"
					man_lang="${1%_*}"
					man_country="${lang_cc#*_}"
					man_charset="${1#*.}"
					use_locale=yes
					return 0
					;;
	*)				echo 'Unknown locale, assuming C' >&2
					;;
	esac

	unset use_locale
}

# Usage: search_path
# Traverse $PATH looking for manpaths.
search_path() {
	local IFS p path

	decho "Searching PATH for man directories"

	IFS=:
	for path in $PATH; do
		# Do a little special casing since the base manpages
		# are in /usr/share/man instead of /usr/man or /man.
		case "$path" in
		/bin|/usr/bin)	add_to_manpath "/usr/share/man" ;;
		*)	if add_to_manpath "$path/man"; then
				:
			elif add_to_manpath "$path/MAN"; then
				:
			else
				case "$path" in
				*/bin)	p="${path%/bin}/man"
					add_to_manpath "$p"
					;;
				*)	;;
				esac
			fi
			;;
		esac
	done
	unset IFS

	if [ -z "$manpath" ]; then
		decho '  Unable to find any manpaths, using default'
		manpath=$man_default_path
	fi
}

# Usage: search_whatis cmd [arglist]
# Do the heavy lifting for apropos/whatis
search_whatis() {
	local IFS bad cmd f good key keywords loc opt out path rval wlist

	cmd="$1"
	shift

	whatis_parse_args "$@"

	build_manpath
	build_manlocales
	setup_pager

	if [ "$cmd" = "whatis" ]; then
		opt="-w"
	fi

	f='whatis'

	IFS=:
	for path in $MANPATH; do
		if [ \! -d "$path" ]; then
			decho "Skipping non-existent path: $path" 2
			continue
		fi

		if [ -f "$path/$f" -a -r "$path/$f" ]; then
			decho "Found whatis: $path/$f"
			wlist="$wlist $path/$f"
		fi

		for loc in $MANLOCALES; do
			if [ -f "$path/$loc/$f" -a -r "$path/$loc/$f" ]; then
				decho "Found whatis: $path/$loc/$f"
				wlist="$wlist $path/$loc/$f"
			fi
		done
	done
	unset IFS

	if [ -z "$wlist" ]; then
		echo "$cmd: no whatis databases in $MANPATH" >&2
		exit 1
	fi

	rval=0
	for key in $keywords; do
		out=$(grep -Ehi $opt -- "$key" $wlist)
		if [ -n "$out" ]; then
			good="$good\\n$out"
		else
			bad="$bad\\n$key: nothing appropriate"
			rval=1
		fi
	done

	# Strip leading carriage return.
	good=${good#\\n}
	bad=${bad#\\n}

	if [ -n "$good" ]; then
		echo -e "$good" | $PAGER
	fi

	if [ -n "$bad" ]; then
		echo -e "$bad" >&2
	fi

	exit $rval
}

# Usage: setup_pager
# Correctly sets $PAGER
setup_pager() {
	# Setup pager.
	if [ -z "$PAGER" ]; then
		PAGER="more -s"
	fi
	decho "Using pager: $PAGER"
}

# Usage: trim string
# Trims whitespace from beginning and end of a variable
trim() {
	tstr=$1
	while true; do
		case "$tstr" in
		[\ \	]*)	tstr="${tstr##[\ \	]}" ;;
		*[\ \	])	tstr="${tstr%%[\ \	]}" ;;
		*)		break ;;
		esac
	done
}

# Usage: whatis_parse_args "$@"
# Parse commandline args for whatis and apropos.
whatis_parse_args() {
	local cmd_arg
	while getopts 'd' cmd_arg; do
		case "${cmd_arg}" in
		d)	debug=$(( $debug + 1 )) ;;
		*)	whatis_usage ;;
		esac
	done >&2

	shift $(( $OPTIND - 1 ))

	keywords="$*"
}

# Usage: whatis_usage
# Display usage for the whatis/apropos utility.
whatis_usage() {
	echo "usage: $cmd [-d] keyword [...]"
	exit 1
}



# Supported commands
do_apropos() {
	search_whatis apropos "$@"
}

do_man() {
	man_parse_args "$@"
	if [ -z "$pages" ]; then
		echo 'What manual page do you want?' >&2
		exit 1
	fi
	man_setup

	for page in $pages; do
		decho "Searching for $page"
		man_find_and_display "$page"
	done

	exit ${ret:-0}
}

do_manpath() {
	manpath_parse_args "$@"
	if [ -z "$qflag" ]; then
		manpath_warnings
	fi
	if [ -n "$Lflag" ]; then
		build_manlocales
		echo $MANLOCALES
	else
		build_manpath
		echo $MANPATH
	fi
	exit 0
}

do_whatis() {
	search_whatis whatis "$@"
}

EQN=/usr/bin/eqn
COL=/usr/bin/col
NROFF='/usr/bin/groff -S -Wall -mtty-char -man'
PIC=/usr/bin/pic
TBL=/usr/bin/tbl
TROFF='/usr/bin/groff -S -man'
REFER=/usr/bin/refer
VGRIND=/usr/bin/vgrind
ZCAT='/usr/bin/zcat -f'

debug=0
man_default_sections='1:1aout:8:2:3:n:4:5:6:7:9:l'
man_default_path='/usr/share/man:/usr/share/openssl/man:/usr/local/man'

config_global='/etc/man.conf'

# This can be overridden via a setting in /etc/man.conf.
config_local='/usr/local/etc/man.d/*.conf'

# Set noglobbing for now. I don't want spurious globbing.
set -f

case "$0" in
*apropos)	do_apropos "$@" ;;
*manpath)	do_manpath "$@" ;;
*whatis)	do_whatis "$@" ;;
*)		do_man "$@" ;;
esac