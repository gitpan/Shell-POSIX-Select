package Shell::POSIX::Select;

# Tim Maher, tim@teachmeperl.com, yumpy@cpan.org
# Fri May  2 10:29:25 PDT 2003

# TO DO: portable-ize tput stuff
# WHen lasting out of a nested loop, should reset do_prompt for outer one
# Add logic to avoid looking for same failed match 2nd time, to save cycles
# dump user's code-block with same line numbers shown in error messages for debugging ease
# Add option to embolden menu numbers, to distinguish from choices that are also numbers
# See documentation and copyright notice below =pod section below

#+ Following used to harvest REs for use, without "use"-ing Regexp::Common
#+	print STDOUT	$RE{balanced}{-parens=>'()'};
#+	print STDERR	$RE{balanced}{-parens=>'{}'};
#+ exit;


# Not using Exporter.pm; doing typeglob-based exporting,
# using adapted code from Damian's Switch.pm
our ( @EXPORT_OK );
our ($Reply, $Heading, $Prompt);
@EXPORT_OK = qw( $Heading $Prompt $Reply $Eof );

our ( $U_WARN, $REPORT, $DEBUG, $DEBUG_default, $_DEBUG,  );
our ( $U_WARN_default, $_import_called, $U_DEBUG, $DEBUG_FILT );	
our ( $DIRSEP, $sdump, $cdump, $script );	
# 
our ( @ISA, @EXPORT, $PRODUCTION, $LOGGING, $PKG, $INSTALL_TESTING,$ON,$OFF, $BOLD, $SGR0, $COLS );

BEGIN {
# print "ENV reference is $ENV{Shell_POSIX_Select_reference}\n";
# print "ENV testmode is $ENV{Shell_POSIX_Select_testmode}\n";
# die;
	$PKG  = __PACKAGE__ ;
	$LOGGING = 0;
	# Probably arrives during prompt, so nice to issue \n to get shell's prompt on next line
# Revisit; what package should this be in?
	$SIG{TERM}=$SIG{QUIT}=$SIG{INT}= sub {
		warn  caller(1), "\n";
		warn $OFF || $SGR0, "\n$0: killed by signal\n";	
		exit;
	}; 
	! defined $_import_called and $_import_called = 0;
	( $script = $0 ) =~ s|^.*/||;

}

sub import ;	# advance declaration

use File::Spec::Functions (':ALL');
use strict;
# no strict 'refs';	# no problem now


use File::Spec::Functions 0.7;
use Filter::Simple;	# some bugs in this or its relatives, that can cause compilation errors here
use Text::Balanced 1.89 qw(extract_variable extract_bracketed);

# Damian has been fixing bugs as I report them, so it's best to have latest version
# I've been testing with this as yet unrelased version
# use Text::Balanced 1.90 qw(extract_variable extract_bracketed);
use Carp;

# Why doesn't File:Spec just hand me the dir-separator char?
( $DIRSEP = catfile ( 1,2 ) ) =~ s/^1(.*)2$/$1/;

$U_DEBUG=1;
$U_DEBUG=0;

$DEBUG_FILT=4;
$DEBUG_FILT=0;

$DEBUG=1; # force verbosity level for debugging messages
$DEBUG=0; # force verbosity level for debugging messages

$REPORT=1; # report subroutines when entered
$REPORT=0; # report subroutines when entered

$DEBUG > 0 and warn "Logging is $LOGGING\n"; 

# controls messages and carp vs. warn (but that doesn't do much)
$PRODUCTION=1; 
$PRODUCTION=0; #+
$PRODUCTION and $REPORT=$DEBUG_FILT=$DEBUG=0;

sub _WARN; sub _DIE;

local $_;	# avoid clobbering user's by accident

$Shell::POSIX::Select::_Fudging=0;	#+

$Shell::POSIX::Select::_default_style='K';	# default loop-style is Kornish
$Shell::POSIX::Select::_default_prompt= "\nEnter number of choice:";
# I detest the shell's default prompt!
$Shell::POSIX::Select::_bash_prompt ='#?';
$Shell::POSIX::Select::_korn_prompt='#?';
$Shell::POSIX::Select::_generic ='#?';
$Shell::POSIX::Select::_arrows_prompt='>>';

$U_WARN_default = 1;	# for enabling user-warnings for bad interactive input


# $_import_called > 0 or import(); # ensure initialization of defaults

our $VERSION = '0.01';

my $subname=__PACKAGE__ ;	# for identifying messages from outside sub's

my $select2foreach;
$select2foreach=1;      # just translate select into foreach, for debugging
$select2foreach=0;

#	warn "Setting up video modes\n";
# I know about Term::Cap, but this seems more direct and sufficient

# disable buffering
$DEBUG > 0 and do { my $old_fh = select (STDERR); $|=1; select ($old_fh); }; #+

$Shell::POSIX::Select::_FILTER_CALLS= $Shell::POSIX::Select::_ENLOOP_CALL_COUNT= $Shell::POSIX::Select::_LOOP_COUNT=0;
# Number of select loops detected
$DEBUG > 3 and $LOGGING and warn "About to call log_files\n"; 

$LOGGING and log_files();	# open logfiles, depending on DEBUG setting

FILTER_ONLY code => \&filter, all => sub {
	$LOGGING and print SOURCE;
};

$DEBUG >2 and warn "Import_called set to: $_import_called\n";
$DEBUG >2 and warn "testmode is $Shell::POSIX::Select::_testmode";

use re 'eval';

{ # scope for declaration of pre-compiled REs
my $RE_kw1 = qr^
	(\bselect\b)
^x;	# extended-syntax, allowing comments, etc.

my $RE_kw2 = qr^
	\G(\bselect\b)
^x;	# extended-syntax, allowing comments, etc.

my $RE_decl = qr^
	(\s*
		# grab declarator if there
		(?: \b my \b| \b local \b| \b our \b )
	\s*)
^x;	# extended-syntax, allowing comments, etc.

my $RE_kw_and_decl = qr^
	\bselect\b
	\s*
	(	# Next, grab optional declarator and varname if there
		(?: \b my \b| \b local \b| \b our \b )?
		\s*
	)?
^x;	# extended-syntax, allowing comments, etc.

	# (?{ $DEBUG > 0 and defined $1 and warn "Matched the loop-var as: $1"; }) #+

	my $RE_list = qr^
	\s*
	(
#		$RE{balanced}{-parens=>'()'}
	)
	^x;	# extended-syntax, allowing comments, etc.

	my $RE_block = qr^
	\s*
	# Is following really beneficial/necessary? I think I needed it in one case - tfm
	(?= { ) 	# ensure opposite of } comes next
	(
		# now find the code-block
#		$RE{balanced}{-parens=>'{}'}
	)
	^x;	# extended-syntax, allowing comments, etc.

	sub matches2fields;
	sub enloop_codeblock;

	sub filter {
		my $subname = sub_name();
		my $last_call = 0;
		my $orig_string=$_;
		my $detect_msg='<unset>';

		++$::_FILTER_CALLS;
		$REPORT > 0 and _WARN "\n$subname entered, call #$::_FILTER_CALLS\n"; #+

		$DEBUG_FILT > 1 and warn "Really Original string:  '$_'"; #+
		$DEBUG_FILT > 1 and warn 'Size of string is: ', length $_, "\n"; #+

		$orig_string ne $_ and die "$_ got trashed";

		#/(..)/ and warn "Matched chars: '$1'\n";	# prime the pos marker

		my $maxloops = 10;	# Probably looping out of control if we get this many
		my $loopnum;

		my $first_celador;
		if ( $last_call = ($_ eq "") ) {
		$DEBUG > 1 and warn "$subname: FINAL CALL\n"; #+
			return undef ;	
		}
		else {
			$detect_msg="SELECT LOOP DETECTED";
			$orig_string ne $_ and die "$_ got trashed";

			#$DEBUG_FILT > 2 and warn "$subname: RE_kw_and_decl is: $RE_kw_and_decl\n"; #+
			#$DEBUG_FILT > 2 and warn "$subname: $RE_list is: $RE_list\n"; #+
			#$DEBUG_FILT > 2 and warn "$subname: $RE_block is: $RE_block\n"; #+

				$DEBUG > 1 and show_subs("****** Pre-Pre-WHILE ****** \n","");
			$DEBUG > 1 and $LOGGING and print LOG "\$_ is '$_'\n"; 

			$loopnum=0;
				$DEBUG > 1 and show_subs("****** Pre-WHILE ****** \n","");

			while (++$loopnum <= $maxloops) {	# keep looping until we can't find any more select loops

				$loopnum == 2 and $first_celador=$_;

				$DEBUG > 1 and show_subs("****** LOOKING FOR LOOP ****** #$loopnum\n","");
				$loopnum > 5 and warn "$subname: Might be stuck in loop\n";
				$loopnum > 10 and die "$subname: Probably was stuck in loop\n";
				$DEBUG > 3 and warn "pos is currently: ", pos(), "\n";
				pos()=0;
				/\S/ or $LOGGING and
					print LOG "\$_ is all white space or else empty\n";
				/\S/ or $DEBUG > 4 and _WARN "\$_ is all white space or else empty\n\n\n\n"; #+

				#	/(..)/ and warn "Matched chars: '$1'\n";	# prime the pos marker

				my ($matched, $can_rewrite) = 0;
				if ($select2foreach) {
					# simple conversion, for debugging basic ops
					# change one word, and select loops with all pieces
					# present are magically rendered syntactically acceptable
					# NOTE: will break select() usage!
					s/\bselect\b/foreach   /g and $matched = -1;
					# All these can be handled in one pass, so exit loop
					goto FILTER_EXIT;
				}
				else {
					my $pos;
					my ($match, $start_match);
					my ($got_kw,$got_decl, $got_loop_var, $got_list, $got_codeblock);
					my $iteration=0;
			FIND_LOOP:
					my ($loop_var, $loop_decl, $loop_list, $loop_block)= ("" x 3);
					$DEBUG_FILT > 0 and	#+
						show_subs ("String starts with: ", $_, pos() || 0, 100);	#+

					$DEBUG_FILT > 0 and warn "Pos initially at ", pos($_), "\n";

					!defined pos() and warn "AT FIND_LOOP, POS IS UNDEF\n";

					$match=$got_kw=$got_decl=$got_loop_var=$got_list=$got_codeblock="";
					my $matched=0;	# means, currently no detected loops that still need replacement

					# my $RE = ( $loopnum == 1 ? $RE_kw1 : $RE_kw2 ) ; 	# second version uses \G
					my $RE = $RE_kw1  ; 	# always restart from the beginning, of incrementally modified program
					# Same pattern good now, since pos() will have been reset by mod
					# my $RE = ( $loopnum == 1 ? $RE_kw1 : $RE_kw1 ) ; 	# second version uses \G
					$DEBUG_FILT > 1 and show_subs ("LOOKING FOR 'select' in: " , $_, pos() || 0, 10); #+
					if ( /$RE/g ) {	# try to match keyword, "select"
						++$matched ;
						$match=$1;
						$start_match=pos() - length $1;
						$got_kw=1;
						$DEBUG_FILT > 1 and show_context($`, $1, $');	#+
						$DEBUG_FILT > 1 and show_progress($match, pos(), $_);
					}
					else {
						$DEBUG_FILT > 0 and #+
							show_subs( "Out of keywords; leaving filter's while loop\n",""); #+
						# no more select keywords to process! # LOOP EXIT #1
						goto FILTER_EXIT;
					}

					$pos=pos();	# remember position

					$DEBUG_FILT > 1 and show_subs ("LOOKING FOR decl in: " , $_, pos(), 10); #+
					if (/\G$RE_decl/g) {
						++$matched ;
						$DEBUG_FILT > 0 and warn "RE_decl matched '$1'\n" , length $1, " characters\n"; #+
						$DEBUG_FILT > 1 and show_context($`, $1, $');	#+
						$loop_decl=$1;
						$match.=" $1";
						$got_decl=1;
					}
					else {
						$DEBUG_FILT > 0 and warn "RE_decl failed to match\n"; #+
						pos()=$pos; # reset to where we left off
					}
					$DEBUG_FILT > 1 and show_progress($match, pos(), $_);

					my @rest;
					$DEBUG_FILT > 1 and show_subs ("LOOKING FOR loop_var in: " , $_, pos(), 19); #+
					$DEBUG_FILT > 0 and warn "POS before ext-var is now ", pos(), "\n";

					( $loop_var, @rest ) = extract_variable( $_ );
					$DEBUG_FILT > 0 and show_subs( "POST- ext-var string is: ", $_, pos(),19);

					$DEBUG_FILT > 0 and warn "POS after ext-var is now ", pos(), "\n";

					if (defined $loop_var and $loop_var ne "" ) {
						$got_loop_var=1;
						$DEBUG_FILT > 0 and warn "Got_Loop_Var matched '$loop_var'\n";
						$match.=" $loop_var";
						$DEBUG_FILT > 2 and @rest and warn "rest contains: '@rest'\n"; #+
					}
					else {
							pos()=$pos; # reset to where we left off
							$DEBUG_FILT > 0 and warn "extract_variable failed to match\n";
					}
							$DEBUG_FILT > 0 and show_subs( "2 remaining string: ", $_, pos(),19); #+
					$DEBUG_FILT > 1 and show_progress($match, pos(), $_);

					gobble_spaces();
					$DEBUG_FILT > 1 and show_subs ("LOOKING FOR LIST in: " , $_, pos(), 10); #+
					$DEBUG_FILT > 1 and warn "Pos is currently: ", pos(), "\n"; #+

					# $DEBUG_FILT > 0 and warn "Pre-extract_bracketed ()\n";
					( $loop_list, @rest ) = extract_bracketed($_, '()');
					if (defined $loop_list and $loop_list ne "") {
						++$matched;
						$got_list=1;
						$match.=" $loop_list";
						$DEBUG_FILT > 1 and show_progress($match, pos(), $_);
					}
					else {	# no loop list; not our kind of select
						# warn "extract_bracketed failed to match\n";
						# If we didn't find loop var, they're probably using
						# select() function or syscall, not select loop
						if ($got_loop_var) {
							$DEBUG_FILT > 3 and 
								warn "$PKG: Found keyword and loop variable, but no ( LIST )!\n",
							;
							# "If { } really there, try placing 'no $PKG;' after loop to fix.\n";
						}
						else {
							$DEBUG_FILT > 3 and warn "$PKG: Found keyword, but no ( LIST )\n",
							"Must be some other use of the word\n";
						}
						$DEBUG_FILT > 0 and warn "giving up on this match; scanning for next keyword (1)";
						if (++$iteration < $maxloops) {
							goto FIND_LOOP;
						}
						else {
							_DIE "$PKG: Maximum iterations reached while looking for select loop #$loopnum";
						}
					}

					gobble_spaces();
					$DEBUG_FILT > 1 and show_subs ("LOOKING FOR BLOCK in: " , $_, pos(), 10); #+
					$DEBUG_FILT > 5 and warn "Using extract_bracketed\n"; #+

					( $loop_block, @rest ) = extract_bracketed($_, '{}');
					if (defined $loop_block and $loop_block ne "") {
						++$matched;
						$got_codeblock=1;
						$match.=" $loop_block";
						$DEBUG_FILT > 1 and show_progress($match, pos(), $_);
					}
					else {
						$DEBUG_FILT > 1 and warn "extract_block failed to match\n"; #+
						$DEBUG_FILT > 1 and show_subs( "Remaining string: ", $_, pos() ); #+
						# if $var there, can't possibly be select syscall or function use,
						# so 100% sure there's a problem

						if ($got_loop_var) {
							warn "$PKG: Found loop variable and list, but no code-block!\n",
							;
							# "If { } really there, try placing 'no $PKG;' after loop to fix.\n";
						}
						else {
							$DEBUG_FILT > 3 and warn "$PKG: Found keyword and list,",
								" but no code-block\n",
							"Must be some other use of the word\n";
						}
						$DEBUG_FILT > 0 and warn "giving up on this match; scanning for next keyword (2)";
						goto FIND_LOOP;
					}

					# and print "list_and_block matched '$&'\n";
					# defined $& and $match.=$&;
					# defined $& and $match.="$1 $2";
					#defined $& and ($loop_list, $loop_block) = ($1, $2);

					my $end_match;
					if ( $matched == 0 ) {
						$DEBUG > 1 and $detect_msg="SELECT KEYWORD *NOT* DETECTED"; #+
die" Can it ever get here?";
						goto FILTER_EXIT;
					}
					else {
						$end_match=pos();
						$detect_msg='<unset>';
						if ( $matched == 1 ) { # means "select" keyword only
							$DEBUG > 1 and $detect_msg="select used in non-looping form"; #+
							;
						}
						if ( $matched == 2 ) { # means "select" plus decl, var, list, or block
							$detect_msg="select loop incomplete; ";
							$got_list or $detect_msg.= "no (LIST) detected\n";
							$got_codeblock or $detect_msg.= "no {CODE} detected\n";
						}
						elsif ( $matched >= 3 ) {
							$DEBUG > 1 and $detect_msg="SELECT LOOP DETECTED "; #+
						}
					}

					# print "Entire match: $match\n";
					# print "Matched Text: ",
					# substr $_, $start_match,
					# 	$end_match-$start_match;

				if ( $matched > 1 ) {	# 1 just means select->foreach conversion
					$::_LOOP_COUNT++;  # counts # detected select-loops
					$DEBUG > 1 and warn "Select Loop Detected, on call #$::_FILTER_CALLS\n"; #+
					#$DEBUG > 0 and $LOGGING and print LOG "MATCHED: $&\n"; #+
					#$DEBUG > 0 and $LOGGING and print LOG "CONVERTED TO:\f$_\n"; #+
					$DEBUG > 0 and 
						warn "$PKG: Set debug to: $Shell::POSIX::Select::DEBUG\n";
				}

				# $can_rewrite indicates whether we matched the crucial
				# parts that allow replacement of the input -- the list and codeblock
				# If we got both, the $can_rewrite var shows true now
				$can_rewrite = $matched >= 2 ? 1 : 0;

				# warn "Calling MATCHES2FIELDS with \$loop_list of $loop_list\n";
				if ($can_rewrite) {
					my $replacer = enloop_codeblock
							matches2fields ( $loop_decl,
								$loop_var,
									$loop_list,
										$loop_block ),
											$::_LOOP_COUNT;
							# $DEBUG > 0 and die "Replacer: $replacer\n"; #+
									
							substr($_, $start_match, ($end_match-$start_match), $replacer );
							# print "\n\nModified \$_ is: \n$_\n";
					}
				}
			} # end while
			continue {
				$DEBUG_FILT > 2 and warn "CONTINUING FIND_LOOP\n"	;
			}
			#warn "Leaving $subname 1 \n";
		}
FILTER_EXIT:
	$Shell::POSIX::Select::filter_output="PRE-LOADING DUMP VAR, loopnum was $loopnum";
	$loopnum > 1 and $Shell::POSIX::Select::filter_output=$_;
	$loopnum == 2 and $detect_msg  !~ /SELECT LOOP DETECTED/ and
		defined $first_celador and $first_celador ne $_ and warn "celador mismatch";
		$LOGGING and print USERPROG $_;	# $_ unset 2nd call; label starts below
		# $DEBUG > 1 and warn "$ON$detect_msg, on call #$::_FILTER_CALLS$:OFF\n\n"; #+
		$DEBUG_FILT > 2 and _WARN "Leaving $subname on call #$::_FILTER_CALLS\n";
	}	# end sub filter
}	# Scope for declaration of filters' REs


sub show_progress {
	my $subname = sub_name();

	$REPORT > 0 and _WARN "$subname entered\n"; #+

	my ($match, $pos, $string) = @_;

	! defined $match  or $match eq "" and warn "$subname: \$match is empty\n";
	show_subs( "Match so far: ", $match, 0, 99);
	defined $pos and warn "POS is now $pos\n";
	show_subs( "Remaining string: ", $string, $pos, 19);
}

sub show_context {
	my $subname = sub_name();

	$REPORT > 0 and _WARN "$subname entered\n"; #+

	my ($left, $match, $right) = @_;

	$DEBUG > 0 and warn "left/match/right: $left/$match/$right";

	show_subs( "Left is", $left, -10);
	$DEBUG > 0 and warn "MATCH IS '$match'\n" , length $match, " characters\n"; #+
	show_subs( "Right is", $right, 0, 10);
}

sub filter0 {    #+
	my $orig_string=$_;

	my $subname = sub_name();    #+
	$REPORT > 0 and _WARN "\n$subname entered, call #$::_FILTER_CALLS\n"; #+

	$DEBUG_FILT > 1 and warn "Really Original string:  '$_'"; #+
	$DEBUG_FILT > 1 and warn '4: Size of string is: ', length $_, "\n"; #+
	$DEBUG_FILT > 1 and show_subs( "Original string: ", $orig_string); #+
}    #+

# Following sub converts matched elements of users source into the 
# fields we need: declaration (optional), loop_varname (optional), codeblock


sub matches2fields {
	my $subname = sub_name();
	my $default_loopvar = 0;

	$REPORT > 0 and _WARN "$subname entered\n"; #+

	my ( $debugging_code, $codeblock2,  );
	my ( $decl, $loop_var, $values, $codeblock, $fullmatch ) = @_;

	$debugging_code = "";

#	$DEBUG > 2 and warn "\$one is: $one\n"; #+

	$DEBUG > 2 and _WARN "\$decl is: $decl\n"; #+
	$DEBUG > 2 and _WARN "\$loop_var is: $loop_var\n"; #+

#+	if ( $Shell::POSIX::Select::_Fudging and $two =~ /[\000..\025]/ ) {
#+		$DEBUG > 2 and _WARN "Fudging in list for \$two; control chars there!: '$two'!\n"; #+
#+		$two = '1 ,2';
#+	}
#+	$DEBUG > 2 and _WARN "\$two is: $two\n";	#+

	$debugging_code = "";
	if ($U_DEBUG > 3) {
		$debugging_code = "\n# USER-MODE DEBUGGING CODE STARTS HERE\n";
		$debugging_code .=
		  '; $,="/"; warn "Caller is now: ", (caller 0), "\n";';
		$debugging_code .=
		  'warn "Caller 3 is now: ", ((caller 0)[3]), "\n";';
		$debugging_code .= 'warn "\@_ is: @_\n";';
		$debugging_code .= 'warn "\@ARGV is: @ARGV\n";';

	#$DEBUG > 2 and warn "LOADING looplist as @::looplist\n"; #+
	#	$debugging_code .=
	#	  'warn "\@looplist is : @Shell::POSIX::Select::looplist\n"';
		$debugging_code .= "# USER-MODE DEBUGGING CODE ENDS HERE\n\n";

		$debugging_code .= "";
	}

	#+ warn "Checking list properties";
	if ( !defined $values or $values =~ /^\s*\(\s*\)\s*$/ ) {  # ( ) is legit syntax
	# warn "values is undef or vacant";
		# Code to let user prog figure out if select loop is in sub,
		# and if so, selects @_ for default LIST
		$values =  # supply appropriate default list, depending on programmer's context
		'defined  ((( caller 0 )[3]) and ' .
			' (( caller 0 )[3])  ne "") ? @_ : @ARGV '
		  ;    
	# _WARN "$subname: Using for loop-list: $values\n"; #+
		  $DEBUG > 2 and _WARN "$subname: Using for loop-list: $values\n"; #+
	}

	$DEBUG > 2 and _WARN "\$codeblock is: $codeblock\n"; #+

		if ( defined $decl and $decl ne "" and
			defined $loop_var and $loop_var ne "" ) {
			$LOGGING and print LOG
				"LOOP: Two-part declaration,",
				" scoper is: $decl, varname is $loop_var\n";
		}
		elsif ( defined $decl and $decl ne "" and
			(! defined $loop_var or $loop_var eq "") ) {
				$LOGGING and print LOG
					"LOOP: Declaration without variable name: $decl" ;
					warn "$PKG: variable declarator ($decl) provided without variable name\n";
					warn "giving up on this match; scanning for next keyword (3)";
					goto FIND_LOOP;
		}
		elsif ( defined $loop_var and $loop_var ne "" and
			(! defined $decl or $decl eq "") ) {
			$LOGGING and print LOG
				"LOOP: Variable without declaration (okay): $loop_var"
		}
	else {
		$LOGGING and print LOG "LOOP: zero-word declaration\n";
		$DEBUG > 1 and _WARN "LOOP: zero-word declaration\n"; #+

		my $default_loopvar = 1;
		($decl, $loop_var) = qw (local $_);    # default loop var; package scope
		$DEBUG > 1 and warn "Using declaration of local and", " loop-variable of $loop_var\n"; #+
	}

	if ( !defined $codeblock or $codeblock =~ /^\s*{\s*}\s*$/ ) {
		# default codeblock prints the selection; good for grep()-like filtering
		# NOTE: Following string must start/end with {}
		$codeblock = "{
			print \"$loop_var\\n\" ; # ** USING DEFAULT CODEBLOCK **
		}";   
		$DEBUG > 1 and warn "Using default codeblock of $codeblock\n";    #+
	}

	$DEBUG > 2 and warn "$PKG: proofreading variable now"; #+
	# I've already extracted what could be a valid variable name,
	# but the regex was kinda sleazy, so it's time to validate
	# it using TEXT::BALANCED::extract_variable()
	# But I found a bug, it rejects $::var*, so exempt that form from check

	unless ($default_loopvar or $loop_var =~ /^\$::\w+/) {
		# don't check if I inserted it myself, or is in form $::stuff,
		# which extract_variable() doesn't properly extract
			# Now let's see if Damian likes it:
			$DEBUG > 1 and show_subs ("Pre-extract_variable 3\n");
		my ( $loop_var2, @rest ) = extract_variable($loop_var);
		if ( $loop_var2 ne $loop_var ) {
			$DEBUG > 1 and warn "$PKG: extracted var diff from parsed var: ", "$loop_var / extracted: $loop_var2, @rest\n"; #+
			$DEBUG > 0 and warn
			  "$PKG: varname for select loop failed validation",
			  " #$::_LOOP_COUNT: $loop_var\n";
		}
	}
	else {
		$DEBUG > 1 and warn "$subname: skipping variable validation\n"; #+
		;
	}

	!defined $decl and $decl = "";
        # okay for this to be empty string; means user wants it global, or
        # declared it before loop

	$DEBUG > 2 and _WARN "$subname: values: $values\n"; #+

	# make version of \$codeblock without curlies at either end
	( $codeblock2 = $codeblock ) =~ s/^\s*\{|\}\s*$//g;
	$DEBUG > 4 and _WARN "\$codeblock2 is: $codeblock2\n"; #+
	# $DEBUG > 4 and _WARN "\$values in m2f is: $values\n"; #+
	#+ die;

	defined $decl and $decl eq 'unset' and undef $decl; # pass as undef

	return ( $decl, $loop_var, $values, $codeblock2, $debugging_code );
}

sub enloop_codeblock {
	# Wraps code implementing select-loop around user-supplied codeblock
	my $subname = sub_name();

	$Shell::POSIX::Select::_ENLOOP_CALL_COUNT++;
	$REPORT > 0 and _WARN "\n$subname entered, call #$Shell::POSIX::Select::_ENLOOP_CALL_COUNT\n"; #+


	my ( $decl, $loop_var, $values, $codestring, $dcode, $loopnum ) = @_;
	$REPORT > 0 and _WARN "$subname entered, loopnum is $loopnum\n"; #+

	$DEBUG > 2 and _WARN "Loop var received as: $loop_var\n", " Values received as: '$values'\n", " Dcode received as: $dcode\n"; #+

	(defined $values and $values ne "") or do {
		$DEBUG > 1 and _WARN "NO VALUES! Using dummy ones"; #+
		$values = '( dummy1, dummy2 )';
	};

	my $declaration =
	  ( defined $decl and $decl ne "" ) ?  "$decl $loop_var; " .
		  ' # LOOP-VAR DECLARATION REQUESTED (perhaps by default)' :
		  " ; # NO DECLARATION OF LOOP-VAR REQUESTED";

	$DEBUG > 2 and _WARN "DECLARATION is '$declaration'\n", " loop_var is $loop_var\n"; #+

	$DEBUG > 2 and _WARN "LOOP_BLOCK is '$codestring'\n"; #+

	my $arrayname = $PKG . '::looplist';
	my $NL = '\n';

	# Now build the code for the user-prog to run
	my @parts;
	# Must start new scope first, so if user has LOOP: label before select, it applies
	# to the whole encapsulated loop
	# wrapper scope needed so user can LABEL: select(), and not try to label my label
	push @parts, qq(
	# NOTA BENE: Line 1 of this segment must start with {, so user can LABEL it
  { # **** NEW WRAPPER SCOPE FOR SELECTLOOP #$loopnum ****
		\$${PKG}::DEBUG > 1 and $loopnum == 1 and
			warn "LINE NUMBER FOR START OF USER CODE_BLOCK IS:  ", __LINE__, "\\n";
    _SEL_LOOP$loopnum: { # **** NEW SCOPE FOR SELECTLOOP #$loopnum ****
	);
# warn "LOGGING is now $LOGGING\n";
	$LOGGING and (print PART1 $parts[0] or _DIE "failed to write to PART1\n");
		$DEBUG > 2 and warn "SETTING $arrayname to $values\n"; #+

	push @parts, qq(
	# critical for values's contents to be resolved in user's scope
		local \@$arrayname=$values;

		local \$${PKG}::num_values=\@$arrayname;
		\$${PKG}::DEBUG > 2 and warn "ARRAY VALUES ARE: \@$arrayname\\n"; #+
		\$${PKG}::DEBUG > 2 and warn "NUM VALUES is \$${PKG}::num_values\\n"; #+
		\$${PKG}::DEBUG > 1 and warn "user-program debug level is \$${PKG}::U_WARN\\n"; #+

		$declaration	# loop-var declaration appears here
	);
	#+die "now" ;

	$LOGGING and (print PART2 $parts[1] or _DIE "failed to write to PART1\n");

	if ( $Shell::POSIX::Select::_Fudging and	#+
		$codestring =~ /[\000..\025]/ ) {	#+
		$DEBUG > 2 and _WARN "Fudging in code for \$codestring;" ; #+
		$DEBUG > 2 and _WARN " control chars there!: '$codestring'!\n"; #+
		$codestring = 'print';	#+
	}	#+
	$DEBUG > 2 and _WARN "\$codestring is: $codestring\n"; #+
	$DEBUG > 2 and _WARN "\$dcode is: '$dcode'\n"; #+
	$DEBUG > 2 and _WARN "\$arrayname is: $arrayname\n"; #+

	$DEBUG > 2 and !defined $dcode and _WARN "Dcode is unset"; #+
	$DEBUG > 2 and !defined $arrayname and _WARN "arrayname is unset"; #+

	# no strict 'refs';
	# _WARN "arrayname is $arrayname, and contains: @$arrayname"; #+
	# die;
	# use strict 'refs';

	$DEBUG > 2 and !defined $Shell::POSIX::Select::_autoprompt and _WARN "autoprompt is unset"; #+
	$DEBUG > 2 and !defined $codestring and _WARN "codestring is unset"; #+

!defined  $dcode and warn "DCODE";	#+
!defined  $PKG and warn "PKG";	#+
!defined  $arrayname and warn "ARRAYNAME";	#+
!defined  $NL and warn "NL";	#+
!defined  $ON and warn "ON";	#+
!defined  $OFF and warn "OFF";	#+
!defined  $BOLD and warn "BOLD";	#+
!defined  $SGR0 and warn "SGR0";	#+
!defined  $loop_var and warn "\Uloop_var";	#+
!defined  $loopnum and warn "\Uloopnum";	#+
!defined  $codestring and warn "\Ucodestring";	#+

# CODING NOTES: don't use standalone word "select" in following,
# because it triggers scan for second loop
	{	# local scope for $^W mod
	# getting one pesky "uninit var" warnings I can't resolve
	local $^W=0;
	push @parts, qq(
    $dcode;
    local (
			\$${PKG}::Prompt[$loopnum],
			\$${PKG}::menu
				) =
      ${PKG}::make_menu(
				\$${PKG}::Heading || "",
				\$${PKG}::Prompt || "" ,	# Might be overridden in make_menu
				\@$arrayname
			);

	 # no point in prompting a pipe!
		local \$${PKG}::do_prompt[$loopnum] = (-t) ?  1 : 0 ;
		$DEBUG > 2 and warn "do_prompt is \$${PKG}::do_prompt[$loopnum]\\n";
    if ( defined \$${PKG}::menu ) {             # No list, no iterations!
      while (1) {    # for repeating prompt for selections
		 # localize, so I don't have to reset $Reply for outer loop on exit from inner
		 local (\$Reply);
# warn "32";
        while (1) {    # for validating user's input
          local \$${PKG}::bad = 0;

# warn "33";
          # local decl suppresses newline on prompt when -l switch turned on
          {
            local \$\\;
            if (\$${PKG}::do_prompt[$loopnum]) {

							# When transferring from INNER to OUTER loop,
							# extra NL before prompt is visually desirable

							if ( \$${PKG}::_extra_nl) {
								print STDERR "\\n\\n";
								\$${PKG}::_extra_nl=0;
							}
							print STDERR "\$${PKG}::menu$NL$ON\$${PKG}::Prompt[$loopnum]$OFF$BOLD ";
						}
# warn "34";
          }
# warn "37";

          #			\$${PKG}::do_prompt=$Shell::POSIX::Select::_autoprompt;
          \$${PKG}::do_prompt[$loopnum]= 0; # constant prompting depends on style
# warn "38";

          if ( \$${PKG}::_testmode eq 'make'
						or \$ENV{Shell_POSIX_Select_reference}
					) {
						\$Reply = undef;
						# dump filtered source for comparison against expected
#+						\$${PKG}::dump_data=1; # seen as lone instance by compiler!
#+							\$Shell::POSIX::Select::dump_data=1;
#+						\$Shell::POSIX::Select::_TTY and 
#+							print Shell::POSIX::Select::TTY "DUMP SOURCE SET TRUE; exiting\\n";
#+						\$Shell::POSIX::Select::_TTY and
#+							print Shell::POSIX::Select::TTY "DUMP SOURCE SET TRUE; exiting\\n";	# dual
#+						\$Shell::POSIX::Select::_TTY and
#+							print Shell::POSIX::Select::TTY "Finished reference source dumps\\n";
						exit;
				}
          else {
# warn "40";
				# I get "use of uninitialized value in <HANDLE>" 
				# if I assign directly to ENV var!  Does not normally happen!
				\$^W=0;
#+ warn "Waiting for input";
						\$Eof=0;
            \$Reply = <STDIN>;
#+ warn "Got input";
				\$^W=1;

            if ( !defined( \$Reply ) ) {
              defined "$BOLD" and "$BOLD" ne "" and print STDERR "$SGR0";

              # need to undef loop var; user may check it!
              undef $loop_var;

              # last ${PKG}::_SEL_LOOP$loopnum;	# Syntax error!
              # If returning to outer loop, show the prompt for it
              # warn "User hit ^D";
              if ( $loopnum > 1 and -t ) {    # reset prompting for outer loop
                    \$${PKG}::do_prompt[$loopnum-1] = 1; \$${PKG}::_extra_nl=1;
              }
							$DEBUG > 2 and warn "Lasting out of _SEL_LOOP$loopnum\\n";
							\$Eof=1;
              last _SEL_LOOP$loopnum;
            }
				!defined \$Reply and die "REPLY accessed, while undefined";
            chomp \$Reply;

            # undo emboldening of user input
            defined "$BOLD" and "$BOLD" ne "" and print STDERR "$SGR0";

            #print STDERR "\$${PKG}::menu$NL$ON\$${PKG}::Prompt$OFF$BOLD ";
            if ( \$Reply eq "" ) {    # interpreted as re-print menu request
                  # Empty input is legit, means redisplay menu
              \$${PKG}::U_WARN > 1 and warn "\\tINPUT IS: empty\\n";
              \$${PKG}::bad = \$${PKG}::do_prompt[$loopnum] = 1;
            }
            elsif ( \$Reply =~ /\\D/ ) {    # shouldn't be any non-digit!
              \$${PKG}::U_WARN > 0
                and warn "\\tINPUT CONTAINS NON-DIGIT: '\$Reply'\\n";
              \$${PKG}::bad = 1;    # Korn and Bash shell just ignore this case
            }
            elsif ( \$Reply < 1 or \$Reply > \$${PKG}::num_values ) {
              \$${PKG}::U_WARN > 0
                and warn
                "\\t'\$Reply' IS NOT IN RANGE: 1 - \$${PKG}::num_values\\n";
              \$${PKG}::bad = 1;    # Korn and Bash shell just ignore this case
            }

            # warn "BAD is now: \$${PKG}::bad";
             \$${PKG}::bad or
							 $DEBUG > 2 and warn "About to last out of Reply Validator Loop\n";
            \$${PKG}::bad or last;    # REPLY VALIDATOR EXITED HERE
          }    # if for validating user input
# warn "99";
        }    # infinite while for validating user input
# warn "100";
#        \$Reply = \$Reply;

        $loop_var = \$$arrayname\[\$Reply - 1];    # set users' variable

        # USER'S LOOP-BLOCK BELOW
        $codestring;

        # USER'S LOOP-BLOCK ABOVE
        # Making sure there's colon (maybe
        # even two) after codestring above,
        # in case user omitted after last
        # statement in block. I might add
        # another statement below it someday!
			 $DEBUG > 2 and warn "At end of prompt-repeating loop \n";
      }    # infinite while for repeating collection of selections
			$DEBUG and warn "BEYOND end of prompt-repeating loop \n";
    }    # endif (defined \$${PKG}::menu)
    else {
      \$${PKG}::DEBUG > 0 and warn "$PKG: Select Loop #$loopnum has no list, so no iterations\\n";
    }
	# return omitted above, to get last expression's value
	# returned automatically, just like shell's version of eslect
	# timji: REMOVE KEYWOORD IN LINE ABOVE AFTER DETERMINING WHY ITS TROUBLESOME!

	);	# push onto parts ender
	}	# local scope for $^W mod

	$LOGGING and (print PART3 $parts[2] or _DIE "failed to write to PART3\n");

	push @parts, qq(
	  } # **** END NEW SCOPE FOR SELECTLOOP #$loopnum ****
	} # **** END WRAPPER SCOPE FOR SELECTLOOP #$loopnum ****
	);

	$LOGGING and (print PART4 $parts[3] or _DIE "failed to write to PART4\n");
# Following is portable PART-divider, used to isolate chunk
# with unitialized value causing  warning
# ); push @parts, qq(

	return ( join "", @parts );	# return assembled code, for user to run
}

sub make_menu {
	my $subname = sub_name();

	$REPORT > 0 and _WARN "$subname entered\n"; #+
	$DEBUG > 2 and _WARN "arguments are @_\n"; #+

	# Replacement of empty list by @_ or @ARGV happens in matches2fields
	# Here we check to see if we got arguments from somewhere
	# Note that it's not necesssarily an error if there are no values,
	# that just means we won't do any iterations

	my ($heading) = shift;
	my ($prompt) = shift;
	my (@values) = @_;
	unless (@values) {
		$DEBUG > 3 and _WARN "$subname RECEIVED NO VALUES, RETURNING NOW\n"; #+
		return ( undef, undef );    # can't make menu out of nothing!
	}
	my ( $l, $l_length ) = 0;
	my $count = 5;
	my ( $sep, $padding ) = "" x 2;
	my $choice = "";

	$DEBUG > 3 and _WARN "In 2 prep_menu; ", scalar @_, " arguments, @_\n"; #+

	# Find longest string value in selection list
	my $v_length = 0;

	for ( my $i = 0 ; $i < @values ; $i++ ) {
		$DEBUG > 2 and $LOGGING and print LOG "Testing $i\n"; #+
		( $l = length $values[$i] ) > $v_length and $v_length = $l;
	}
	$DEBUG > 3 and $LOGGING and print LOG "Longest value is $v_length chars\n";

	# Figure out lengths of labels (numbers on menu selections)
	$DEBUG > 3 and $LOGGING and print LOG "Number of values is ", scalar @values, "\n";

	$DEBUG > 4 and _WARN "\@values is: @values\n"; #+

	@values >= 10_000	? $l_length = 5 :
	@values >= 1_000	? $l_length = 4 :
	@values >= 100		? $l_length = 3 :
	@values >= 10		? $l_length = 2 :
	@values > 0			? $l_length = 1 :
	undef $l_length;

	$DEBUG > 3 and $LOGGING and print LOG "Label length is $l_length\n";

	if ( !defined $l_length ) { return undef; }

	$sep = "\040\040";
	my $l_sep = length $sep;    # separator 'tween pieces

	# Figure out how many columns per line we can print
	# 2 is for :<SP> after label

	# TIMJI: Convert to using YUMPY's Term::Size::Heuristic here, later on

	my $one_label = ( $l_length + 2 ) + $v_length + $l_sep;
	my $columns = int( $COLS / $one_label );
	$columns < 1 and $columns = 1;
#	$DEBUG > 3 and
#HERE
$LOGGING and print LOG "T-Cols, Columns, label: $COLS, $columns, $one_label\n";

	# Prompt may have been set in import() according to a submitted option;
	# if so, keep it.  If not, use shell's default
	$prompt =
		(defined $Shell::POSIX::Select::Prompt and
			$Shell::POSIX::Select::Prompt ne "") ? 
				$Shell::POSIX::Select::Prompt :
				defined $ENV{Select_POSIX_Shell_Prompt} ? $ENV{Select_POSIX_Shell_Prompt}  :
					 $Shell::POSIX::Select::_default_prompt;	
							 ;
	$DEBUG > 1 and show_subs ("Prompt set to: ", $Shell::POSIX::Select::Prompt); #+

	$DEBUG > 3 and $LOGGING and print LOG "Making menu\n";
	$DEBUG > 3 and $LOGGING and print STDERR "Making menu\n"; #+

	{
		local $, = "\n";
		$DEBUG > 2 and _WARN( "\ncolumns, l_length, v_length, sep, values", $columns, $l_length, $v_length, $sep, @values, "\n" ); #+
	}

	my $menu;
	$menu = defined $heading ? "${ON}$heading$OFF" : "" ;
   $menu.="\n";
	# $columns == 0  and die "Columns is zero!";
	for ( my $i = 0, my $j = 1 ; $i < @values ; $i++, $j++ ) {
		$menu .= sprintf "%${l_length}d) %-${v_length}s$sep", $j, $values[$i];
		$j % $columns or $menu .= sprintf "\n";    # format $count items per line

	# For 385 line list:
	# Illegal modulus zero at /pmods/yumpy/Select/Shell/POSIX/Select.pm line 764.

	}
	return ( $prompt, $menu );
}

sub log_files {
	my $subname = sub_name();
	my ($dir, $sep);

	$REPORT > 0 and _WARN "$subname entered\n"; #+

	if ( $LOGGING == 1 ) {	
		$dir = tmpdir();
		#
		# USERPROG shows my changes, with	
		# control-chars filling in as placeholders	
		# for some pieces. For debugging purposes, I	
		# find it helpful to print that out ASAP so	
		# I have something to look at if the program	
		# bombs out before SOURCE gets written out,	
		# which is the same apart from placeholders	
		# being converted to original data.	
		#
		$DEBUG > 1 and $LOGGING > 0 and warn "Opening log files\n";	
		open LOG,	"> $dir${DIRSEP}SELECT_log" or _DIE "Open failed, $!\n";
		open SOURCE,	"> $dir${DIRSEP}SELECT_source" or _DIE "Open failed, $!\n";	
		open USERPROG,	"> $dir${DIRSEP}SELECT_user_program" or _DIE "Open failed, $!\n";	
		open PART1,	"> $dir${DIRSEP}SELECT_part1" or _DIE "Open failed, $!\n";	
		open PART2,	"> $dir${DIRSEP}SELECT_part2" or _DIE "Open failed, $!\n";
		open PART3,	"> $dir${DIRSEP}SELECT_part3" or _DIE "Open failed, $!\n";	
		open PART4,	"> $dir${DIRSEP}SELECT_part4" or _DIE "Open failed, $!\n";
		$LOGGING++;	# to avoid 2nd invocation
	}	
	elsif ($LOGGING > 1) {	
		$DEBUG > 0 and warn "$subname: Logfiles opened previously\n"; 
	}	
	else {	
		$DEBUG > 0 and warn "$subname: Logfiles not opened\n"; 
	}	
}

sub sub_name {
	my $callers_name = (caller 1)[3] ;
	if  ( ! defined $callers_name ) {
			$callers_name='Main_program'; # must be call from main
}
	else  {
	$callers_name =~ s/^.*:://; # strip package name
	$callers_name .= '()'; # sub_name -> sub_name()
}  
	return $callers_name;
}

sub _WARN {
	my $subname = sub_name();
	$PRODUCTION ? carp(@_) : warn (@_);
}

sub _DIE {
	my $subname = sub_name();
	$PRODUCTION ? croak(@_) : die (@_);
}


sub ignoring_case { lc $a cmp lc $b }

sub import {
	local $_;
	my $subname = sub_name();
	my %import;
	$_import_called++;

  $REPORT > 0 and _WARN "$subname entered\n"; #+

	$DEBUG > 4 and _WARN "$subname reporting on call #$_import_called\n"; #+

	$DEBUG > 2 and _WARN "In import, got these args: @_\n"; #+

	shift;	# discard package name

	$Shell::POSIX::Select::U_WARN = $Shell::POSIX::Select::U_WARN_default;
	$Shell::POSIX::Select::_style = $Shell::POSIX::Select::_default_style;	
	# $Shell::POSIX::Select::_prompt = 
	# Prompt is now established in make_menu, during run-time
	$Shell::POSIX::Select::_autoprompt=0;

# First, peel off symbols to import, if any
# warn "Caller of $subname is ", scalar caller, "\n";
my $user_pkg=caller;
#	$DEBUG > 2 and
# print "In import, received these args: @_\n";	#+
for (my $i=0;  $i<@_; $i++) { 
	my $found=0;
	foreach (@EXPORT_OK) {	# Handle $Headings, etc.
		if ($_[$i] eq $_) { $import{$_} = $i; $found++; last; }
	}
	# stop as soon as first non-symbol encountered, so as not to
	# accidentally mess with following hash-style options
	$found==0 and last;
}
#+ %import and print "Hash is: ", %import, "\n";
#+ %import and print "Detected imports: ",  keys %import, "\n";
%import and export($user_pkg, keys %import);	# create aliases for user

# following gets "attempt to delete unreferenced scalar"!
	# %import and delete @_[values %import];
# Delete from @_ each 
map { delete $_[$_] } values %import;	# but this works
# warn "Numvals in array is ", scalar @_, "\n";

@_= grep defined,  @_;	# reset, to eliminate extracted imports
# warn "Numvals in array is now ", scalar @_, "\n";
	$DEBUG > 2 and	#+
	print "Remaining arguments: @_\n"; #+
#	$DEBUG > 4 and
#	warn "18 U_WARN set to default of $Shell::POSIX::Select::U_WARN"; #+
		# warnings sets user-program debugging level
		# debug sets module's debuging level
		my @legal_options = qw( style  prompt  testmode  warnings  debug logging );
		my %options =
			hash_options(\@legal_options, @_ );	# style => Korn, etc.

$DEBUG > 0 and	#+
	do { foreach (sort keys %options) { warn "$_/'$options{$_}'"; } }; #+

		my @styles=qw( bash  korn );
		my @prompts=qw( generic korn bash arrows );
		my @testmodes=qw( make foreach );

		my $bad;

		# timji: Loopify this section later, once it gets stable

		# "logging" enables/disables logging of filter output to file 
#+ warn "Checking logging variable\n";
		$_ = $ENV{Shell_POSIX_Select_logging} || $options{logging};
		if (defined) {
			#+ warn "It is defined\n";
			# unless ( is_unix() ) {
			# 	warn "$PKG\::$subname: logging is only for UNIX-like OSs\n";
			# }
			if (/^(\d)$/ and 0 <= $1 and $1 <=1 ) {
				$LOGGING = $_;
				$DEBUG > 0 and warn "$PKG: Set logging to: $LOGGING\n";
			}
			else {
			   _WARN "$PKG\::$subname: Invalid logging level '$_'\n";
			   $DEBUG > 1 and _DIE;
			}
		}
		else {	#+
			$DEBUG > 1 and warn "It is NOT defined\n";	#+
		}	#+

		# "debug" enables/disables informational messages while running user program
		$_ = $ENV{Shell_POSIX_Select_warnings} || $options{warnings};
		$select2foreach=0;
		if (defined) {
			if (/^\d+$/) {
				$Shell::POSIX::Select::U_WARN = $_;
				warn "$PKG: Set warnings to: $Shell::POSIX::Select::U_WARN\n";
			}
			else {
			   _WARN "$PKG\::$subname: Invalid warnings level '$_'\n";
			   $DEBUG > 1 and _DIE;
			}
		}

		# "debug" enables/disables informational messages while running user program
		$_ = $ENV{Shell_POSIX_Select_debug} || $options{debug};
		if (defined) {
			if (/^\d+$/) {
				$Shell::POSIX::Select::DEBUG = $_;
				#+ warn "$PKG: Set debug to: $Shell::POSIX::Select::DEBUG";
			}
			else {
			   _WARN "$PKG\::$subname: Invalid debug option '$_'\n";
			   $DEBUG > 1 and _DIE;
			}
		}

		$_=$ENV{Shell_POSIX_Select_style} || $options{style};
		if (defined) {
			my $found=0;
				foreach my $style (@styles) {
					if ($_ =~ /^$style$/i ) { # korn, bash,etc.
						# code as K, B, etc.
						$Shell::POSIX::Select::_style = uc substr($_,0,1);
						$found++;	# last one wins
					}
				}
				if (! $found) {
					 _WARN "$PKG\::$subname: Invalid style option '$_'\n";
					 $DEBUG > 1 and _DIE;
				}
		}

			# Bash automatically shows prompt every time, 
			# Ksh only does if user enters input of <CR> only
			my $autoprompt=0;
			if ( $Shell::POSIX::Select::_style eq 'K' ) { $autoprompt=0; }
			elsif ( $Shell::POSIX::Select::_style eq 'B' ) { $autoprompt=1; }

			$Shell::POSIX::Select::_autoprompt = $autoprompt;
			$DEBUG > 2 and warn "Autoprompt is: $Shell::POSIX::Select::_autoprompt\n"; #+
			$_ = $ENV{Shell_POSIX_Select_prompt} || $options{prompt} ;
			if (defined) {
				$_=lc $_;
				my $found=0;
				foreach my $prompt (sort @prompts) { # sorting, so "generic" choice beats shell-specific ones
					if ($_ =~ /^$prompt$/i ) {
						$_ eq 'generic' and do {
						$DEBUG > 0 and warn "Set generic prompt";
							$Shell::POSIX::Select::_prompt = 
								$Shell::POSIX::Select::_generic;
							++$found and last;
die 33;
						};
						$_ eq "korn" and do {
							$Shell::POSIX::Select::_prompt =
								$Shell::POSIX::Select::_korn_prompt;
							$found++;
							last;
						};
						$_ eq "bash" and do {
							$Shell::POSIX::Select::_prompt =
								$Shell::POSIX::Select::_bash_prompt;
							$found++;
							last;
						};
						$_ eq "arrows" and do {
							$Shell::POSIX::Select::_prompt =
								$Shell::POSIX::Select::_arrows_prompt;
							$found++;
							last;
						};
					}
					# If not a prompt keyword, must be literal prompt
						do {
							$Shell::POSIX::Select::_prompt = $_;
							$found++;
							last;
						};
				}
				if (! $found) {
					 _WARN "$PKG\::$subname: Invalid prompt option '$_'\n";
					 $DEBUG > 1 and _DIE;
				}
			}

			$Shell::POSIX::Select::dump_data=0;
			$_= $ENV{Shell_POSIX_Select_testmode} || $options{testmode} ;
			if (defined) {
				my $found=0;
				#foreach my $mode ( @testmodes ) {
					if ($_ =~ /^make$/i ) {
						$Shell::POSIX::Select::_testmode= 'make';
						$Shell::POSIX::Select::dump_data=1;
						$found++;
					}
					elsif ($_ =~ /^foreach$/i ) {
						$Shell::POSIX::Select::_testmode= 'foreach';
						$select2foreach=1;
						$found++;
					}
					else {
						$Shell::POSIX::Select::_testmode= '';
						$DEBUG > 2 and _WARN "Unrecognized testmode: $_\n";
					}
				#}
				if (! $found) {
					 _WARN "$PKG\::$subname: Invalid testmode option '$_'\n";
					 $DEBUG > 1 and _DIE;
				}
			}
		# ENV variable overrides program spec
#+		warn "Checking ENV for overriding option settings";	#+
#+		defined $ENV{Shell_POSIX_Select_style} and
#+			$Shell::POSIX::Select::_style=$ENV{Shell_POSIX_Select_style} ;
#+		defined $ENV{Shell_POSIX_Select_prompt} and
#+			$Shell::POSIX::Select::_prompt=$ENV{Shell_POSIX_Select_prompt} ;
#+		defined $ENV{Shell_POSIX_Select_debug} and
#+			$Shell::POSIX::Select::_debug=$ENV{Shell_POSIX_Select_debug} ;
#+		defined $ENV{Shell_POSIX_Select_testmode} and
#+			$Shell::POSIX::Select::_testmode=$ENV{Shell_POSIX_Select_testmode} ;

		( ! defined $Shell::POSIX::Select::_testmode or
			$Shell::POSIX::Select::_testmode eq "" ) and
			$Shell::POSIX::Select::_testmode = "";	

$DEBUG > 2 and warn "37 Testmode set to $Shell::POSIX::Select::_testmode\n";

		$DEBUG > 1 and warn "-"  x 80, "\n"; #+
		$DEBUG > 2 and #+
		_WARN "$subname: Debugging option set to: '$DEBUG'\n"; #+
		$DEBUG > 2 and _WARN "$subname: Loop-style set to: '$Shell::POSIX::Select::_style'\n"; #+
		$DEBUG > 2 and _WARN "$subname: Testmode set to: '$Shell::POSIX::Select::_testmode'\n"; #+
		$DEBUG > 2 and defined $Shell::POSIX::Select::_prompt and _WARN "$subname: Prompt set to: '$Shell::POSIX::Select::_prompt'\n"; #+
		$DEBUG > 4 and warn "88 U_WARN set to default of $Shell::POSIX::Select::U_WARN"; #+
		$DEBUG > 1 and warn "-"  x 80, "\n"; #+
		$LOGGING and log_files();

		$ENV{Shell_POSIX_Select_reference} and
			$Shell::POSIX::Select::dump_data = 'Ref_Data';
		if ( $Shell::POSIX::Select::dump_data ) {
			$Shell::POSIX::Select::_TTY=0;
			open TTY,	"> /dev/tty" or _DIE "Open of TTY failed, $!\n";	
			$Shell::POSIX::Select::_TTY=1;

# What's the OS-portable equivalent of "/dev/tty" in the above?

# print TTY "dump_data is $Shell::POSIX::Select::dump_data\n";
			$sdump =
			($Shell::POSIX::Select::dump_data =~ /[a-z]/i ? # Dir prefix, or nothing
				$Shell::POSIX::Select::dump_data : '.') . $DIRSEP . "$script.sdump" .
			($Shell::POSIX::Select::dump_data =~ /[a-z]/i ? # Dir prefix, or nothing
				'_ref' : '') ;
			($cdump = $sdump) =~ s/$script\.sdump/$script.cdump/;	# make code-dump name too
# print TTY "ENV reference is $ENV{Shell_POSIX_Select_reference}\n";
# print TTY "Shell::POSIX::Select::dump_data is $Shell::POSIX::Select::dump_data\n";
# print TTY "Sdump is $sdump\n";
# print TTY "Cdump is $cdump\n";
# 			$Shell::POSIX::Select::_TTY and
# 				print TTY "PREPARING DUMPS\n";
			# Make reference copies of dumps for distribution, or test copies,
			# depending on ENV{reference} set or testmode=make
			close STDERR or
				die "$PKG-END(): Failed to close 'STDERR', $!\n";
			open STDERR, "> $sdump" or
				die "$PKG-END(): Failed to open '$sdump' for writing, $!\n";
# HERE2
			open STDOUT, ">&STDERR" or
				die "$PKG-END(): Failed to dup STDOUT to STDERR, $!\n";
#			print TTY "${PKG}-END(): Succeeded in opening '$sdump' for writing\n";
		}

	( $ON , $OFF , $BOLD ,  $SGR0 , $COLS ) =
		display_control ($Shell::POSIX::Select::dump_data);
		# $DEBUG >2 and die "Columns returned as $ON$COLS$OFF\n"; #+
}

sub export {	# appropriated from Switch.pm
	my $subname = sub_name();

	# $offset = (caller)[2]+1;
	my $pkg = shift;
	no strict 'refs';
# All exports are scalard vars,  so strip sigils and poke in package name
#+ warn "$subname received @_\n";
	foreach ( map {  s/^\$//; $_ } @_ ) {	# must change $Reply to Reply, etc.
#+ print "Aliaser for $pkg: \$_ is $_\n";
#+ 			print "Working on Shell::POSIX::Select::$_\n";
		*{"${pkg}::$_"} =
			\${ "Shell::POSIX::Select::$_" };
				# "Shell::POSIX::Select::$_";
	}
	# *{"${pkg}::__"} = \&__ if grep /__/, @_;
	1;
}

sub hash_options {
	my $ref_legal_keys = shift;
	my %options = @_   ;
	my $num_options=keys %options;
	my %options2 ; 

	my $subname = sub_name();
	$REPORT > 0 and _WARN "$subname entered\n"; #+

	$DEBUG > 2 and warn "Legal keys are: @$ref_legal_keys\n"; #+

	# FORCING DEBUG MODE	#+
	if ( $DEBUG > 1 ) {	#+
		print "$subname: $num_options options received:\n";	#+
		foreach my $key ( sort ignoring_case keys %options) {	#+
			print "$key -> $options{$key}\n";	#+
		}	#+
	}	#+

	if ($num_options) {
		my @legit_options =
			grep { "@$ref_legal_keys" =~ /\b $_ \b/x }
				sort ignoring_case keys %options;

		my @illegit_options =
			grep { "@$ref_legal_keys" !~ /\b $_ \b/x }
				sort ignoring_case keys %options;

		@options2{sort ignoring_case @legit_options} =
			@options{sort ignoring_case @legit_options } ;
			{ # scope for local change to $,
		  local $,=' ';
		  if ($num_options > keys %options2) { # options filtered out?
			my $msg= "$PKG\::$subname:\n  Invalid options: " ;
			$msg .= "@illegit_options\n";
			_WARN "$msg\n";	# warn/carp don't handle $,  #+
			_DIE;	# Can't be conditional on DEBUG setting,
						# because that comes after this sub returns!
			}
		}

		if ( $DEBUG > 1 ) {	#+
			print "\nOptions accepted:\n";	#+
			foreach my $key ( sort ignoring_case keys %options2 ) {	#+
				defined $options2{$key} and	#+
					print "$key\t-> '$options2{$key}'\n";	#+
			}	#+
		}	#+
	}
#HERE		if ($DEBUG > 2) {	#+
			local $,="/";	#+
#+			warn "Original keys/values\n";
#+ foreach (sort keys %options) { warn "$_/'$options{$_}'   "; }
#+			warn "Final keys/values\n";
#+ foreach (sort keys %options2) { warn "$_/'$options{$_}'   "; }
#			warn "Final keys: ", keys %options2, "\n";	#+
#			warn "Original values keys: ", values keys %options, "\n";	#+
#			warn "Final values keys: ", values keys %options2, "\n";	#+
#HERE		}	#+

	return %options2;
}

sub show_subs {
		# show sub-string in reverse video, primarily for debugging
		my $subname = sub_name();
		$REPORT > 5 and _WARN "$subname entered\n"; #+

		 @_ >= 1 or die "${PKG}\::subname: no arguments\n" ;
		 my $msg=shift || '<no msg>';
		 my $string=(shift || '');
		 my $start=(shift || 0);
		 my $length=(shift || 9999);

		 $string =~ s/[^[:alpha:\d\s]]/-/g;	# control-chars screw up printing
# warn "Calling substr for parms $string/$start/$length\n";
		 warn "$msg", $ON, substr ($string, $start, $length), $OFF, "\n";
}

sub gobble_spaces {
	my $subname = sub_name();

	my $pos=pos();	# remember current position
	$DEBUG_FILT > 1 and warn "Pos now at $pos\n"; #+
	if (/\G\s+/g) {
		$DEBUG_FILT > 1 and
			warn "$subname: space gobbler matched '$&' of length ", length $&, "\n" ;
	}
	else {
		$DEBUG_FILT > 1 and warn "$subname: space gobbler matched nothing\n";
		pos()=$pos;	# reset to prior position
	}
	$pos=pos();	# identify current position
	$DEBUG_FILT > 1 and warn "$subname: Pos now at $pos\n"; #+
	$DEBUG_FILT > 0 and show_subs ("$subname: Remaining string starts with:", $_, pos($_), 10); #+
}

sub display_control {
	my $subname = sub_name();

	$REPORT > 0 and _WARN "$subname entered\n"; #+
	my $flag=shift;
	my ( $on , $off , $bold ,  $sgr0 , $cols ) ;

	# in "make" or "reference" testmodes, mustn't clutter output with coloration
	# Disable screen manips for reference source-code dumps
	unless ( $flag ) {
	if ( is_unix() and
				defined $ENV{TERM} and
					! system 'tput -V >/dev/null 2>&1' ) {
			# Always need column count
			# for menu sizing
			$cols=`tput cols`; defined $COLS and chomp ($COLS) ;
			if ($flag ne 'make') {
				$on=`tput smso`;
				$off=`tput rmso` || `tput sgr0`;
				$bold=`tput bold`;	# for prettifying screen captures
				$sgr0=`tput sgr0`;	# for prettifying screen captures
			}
		}
		else {
			$DEBUG >2 and	warn "Operating System not UNIX;", $^O, "\n"; #+
		}
		$DEBUG >2 and	warn "Columns is $ON$COLS$OFF\n"; #+
		$DEBUG > 2 and warn "Returning $on , $off , $bold , sgr0 , $cols \n";
	}
		return ($on || "", $off || "", $bold || "", $sgr0 || "", $cols || 80);
}

END { # END block
# 		$Shell::POSIX::Select::_TTY and
# 			print TTY "IN END BLOCK NOW\n"; 
# 			$Shell::POSIX::Select::_TTY and
# 		$ENV{Shell_POSIX_Select_reference} and print TTY "REF set\n";
# 			$Shell::POSIX::Select::_TTY and
#  		$ENV{Shell_POSIX_Select_dump_data} and print TTY "DS set\n";
	# print "\$script is $script\n";
	# sdump means screen-dump, cdump means code-dump
	if ( $Shell::POSIX::Select::dump_data ) {
# 		$Shell::POSIX::Select::_TTY and
# 			print TTY "IN dump source BLOCK NOW\n"; 
		if ( $ENV{Shell_POSIX_Select_reference} ) {
# 			$Shell::POSIX::Select::_TTY and
# 				print TTY "Reference variable IS defined\n";
# 			$Shell::POSIX::Select::_TTY and
# 			print TTY "Reference variable IS defined\n";	# double
			# Make reference copies of code dumps, for distribution
# 			$Shell::POSIX::Select::_TTY and
# 				print TTY "Making reference code dumps to $cdump\n";
		}
		else {
# 			$Shell::POSIX::Select::_TTY and
# 				print "TTY Reference variable not defined\n";
		}
			my $pwd=`pwd`;
# 			$Shell::POSIX::Select::_TTY and
# 				print TTY "Current dir is '$pwd'\n";
			# dump filtered source, for reference or analysis
# 			$Shell::POSIX::Select::_TTY and
# 	 	  print TTY "Attempting open of $cdump for writing\n";
			open SOURCE, "> $cdump" or
			$Shell::POSIX::Select::_TTY and
 				print TTY "$PKG-END(): Failed to open '$cdump' for writing, $!\n" and
			die;
			defined $Shell::POSIX::Select::filter_output and
				print SOURCE $Shell::POSIX::Select::filter_output or 
				die "$PKG-END(): Failed to write to '$cdump', $!\n";
#			system "ls -li $cdump $sdump";
	}

	# Screen dumping now arranged in sub import()
	#		open SCREEN, "> $script.sdump" or
	#			die "$PKG-END(): Failed to open '$script.sdump' for writing, $!\n";

	else {
		defined $SGR0 and $SGR0 ne "" and print STDERR "$SGR0";	# ensure turned off
		$DEBUG > 1 and $LOGGING and print LOG "\n$PKG finished\n"; 
	#+	$DEBUG > 1 and warn "END: Processed $::_LOOP_COUNT select loops\n";
		print STDERR "\n";	# ensure shell prompt starts on fresh line
	#+	print "Signals: " , %SIG;
	}
}

sub is_unix {
	if (
		# I'm using the $^O from File::Spec, which oughta know
		# and guessing at others; help!
		$^O !~ /^(MacOS|MSWin32|os2|VMS|epoc|NetWare|dos|cygwin)$/ix
	  ) {
			$DEBUG > 2
			  and warn "Operating System not UNIX;", $^O, "\n";    
		}
		else {
		$DEBUG > 2
		  and warn "Operating System reported as ", $^O, "\n";    
		}
	return defined $1 ? 0 : 1 ;
	}

=pod

=head1 NAME

Shell::POSIX::Select - The POSIX Shell's C<select> loop for Perl

=head1 PURPOSE

This module implements the C<select> loop of the "POSIX" shells (Bash, Korn, and derivatives)
for Perl.
That loop is unique in two ways: it's by far the friendliest feature of any UNIX shell,
and it's the I<only> UNIX shell loop that's missing from the Perl language.  Until now!

=head1 SYNOPSIS

NOTE: In the following, the enclosing square brackets I<(not typed)> identify optional elements, and vertical bars indicate mutually-exclusive choices:

select
B<[>B<[>my|local|our<]>
scalar_varB<]>
( B<[>LISTB<]> )
{ B<[>CODEB<]> } 

=for comment
C<select>
B<[>B<[>C<my>|C<local>|c<our><]>
C<scalar_var>B<]>
( B<[>C<LIST>B<]> )
{ B<[>C<CODE>B<]> } 

The required elements are the keyword C<select>,
the I<parentheses>, and the I<curly braces>.
See L<"SYNTAX"> for details.

=head1 ELEMENTARY EXAMPLES

NOTE: All non-trivial programming examples shown in this document are
distributed with this module, in the B<Scripts> directory.
See L<"ADDITIONAL EXAMPLES">
for more interesting uses of C<select>.

=head2 ship2me.plx

    use Shell::POSIX::Select;

    select $shipper ( 'UPS', 'FedEx' ) {
        print "\nYou chose: $shipper\n";
        last;
    }
    ship ($shipper, $ARGV[0]);  # prints confirmation message

I<Screen>

    ship2me.plx  '42 hemp toothbrushes'  # program invocation
    
    1) UPS   2) FedEx
    
    Enter number of choice: 2
    
    You chose: FedEx
    Your order has been processed.  Thanks for your business!


=head2 ship2me2.plx

This variation on the preceding example shows how to use a custom menu-heading and interactive prompt.

    use Shell::POSIX::Select qw($Heading $Prompt);

    $Heading='Select a Shipper' ;
    $Prompt='Enter Vendor Number: ' ;

    select $shipper ( 'UPS', 'FedEx' ) {
      print "\nYou chose: $shipper\n";
      last;
    }
    ship ($shipper, $ARGV[0]);  # prints confirmation message

I<Screen>

    ship2me2.plx '42 hemp toothbrushes'

    Select a Shipper

    1) UPS   2) FedEx

    Enter Vendor Number: 2

    You chose: FedEx
    Your order has been processed.  Thanks for your business!

=head1 BENEFITS

What's so great about this loop? It automates the generation of a numbered menu
of choices, prompts for a choice, proofreads that choice and complains if it's invalid
(at least in this enhanced implementation), and executes a code-block with a variable
set to the chosen value.  That saves a lot of coding for interactive programs --
especially if the menu consists of many values!

The benefit of bringing this loop to Perl is that it obviates the
need for future programmers
to reinvent the I<Choose-From-A-Menu> wheel.

=head1 SYNTAX

=begin comment

NOTE: Enclosing square brackets I<(never typed!)> identify optional elements in the following line, and vertical bars indicate mutually-exclusive choices:

C<select>
B<[>B<[>C<my>|C<local>|c<our><]>
C<scalar_var>B<]>
( B<[>C<LIST>B<]> )
{ B<[>C<CODE>B<]> } 

The required elements are the keyword C<select>,
the I<parentheses>, and the I<curly braces>, but
in most applications the
programmer will want to supply one
or more of the optional portions.

=end comment

Supported invocation formats include the following:

 use Shell::POSIX::Select ;

 select                 ()      { }         # Form 0
 select                 ()      { CODE }    # Form 1
 select                 (LIST)  { CODE }    # Form 2
 select         $var    (LIST)  { CODE }    # Form 3
 select my      $var    (LIST)  { CODE }    # Form 4
 select our     $var    (LIST)  { CODE }    # Form 5
 select local   $var    (LIST)  { CODE }    # Form 6

If the loop variable is omitted (as in I<Forms> I<0>, I<1> and I<2> above),
it defaults to C<$_>, C<local>ized to the loop's scope.
If the LIST is omitted (as in I<Forms> I<0> and I<1>), 
C<@ARGV> is used by default, unless the loop occurs within a subroutine, in which case 
C<@_> is used instead.
If CODE is omitted (as in I<Form> I<0>,
it defaults to a statement that B<prints> the loop variable.

The cases shown above are merely examples; all reasonable permutations are permitted, including:

 select       $var    (    )  { CODE }        
 select local $var    (LIST)  {      }

The only form that's I<not> allowed is one that specifies the loop-variable's declarator without naming the loop variable, as in: 

 select our () { } # WRONG!  Must name variable with declarator!

=head2 The Loop variable

See L<"SCOPING ISSUES"> for full details about the implications
of different types of declarations for the loop variable.

=head2 $Reply

When the interactive user responds to the C<select> loop's prompt
with a valid input (i.e., a number in the correct range),
the variable C<$Reply> is set within the loop to that number.
Of course, the actual item selected is usually of great interest than
its number in the menu, but there are cases in which access to this
number is useful (see L<"menu_ls.plx"> for an example).

=head1 OVERVIEW

This loop is syntactically similar to Perl's
C<foreach> loop, and functionally related, so we'll describe it in those terms.

 foreach $var  ( LIST ) { CODE }

The job of C<foreach> is to run one iteration of CODE for each LIST-item, 
with the current item's value placed in C<local>ized C<$var>
(or if the variable is missing, C<local>ized C<$_>).

 select  $var  ( LIST ) { CODE }

In contrast, the C<select> loop displays a numbered menu of
LIST-items on the screen, prompts for (numerical) input, and then runs an iteration
with C<$var> being set that number's LIST-item.

In other words, C<select> is like an interactive, multiple-choice version of a
C<foreach> loop.
And that's cool!  What's I<not> so cool is that
C<select> is also the I<only> UNIX shell loop that's been left out of
the Perl language.  I<Until now!>

This module implements the C<select> loop of the Korn and Bash
("POSIX") shells for Perl.
It accomplishes this through Filter::Simple's I<Source Code Filtering> service,
allowing the programmer to blithely proceed as if this control feature existed natively in Perl.

The Bash and Korn shells differ slightly in their handling
of C<select> loops, primarily with respect to the layout of the on-screen menu.
This implementation currently follows the Korn shell version most closely
(but see L<"TODO-LIST"> for notes on planned enhancements).

=head1 ENHANCEMENTS

Although the shell doesn't allow the loop variable to be omitted,
for compliance with Perlish expectations,
the C<select> loop uses C<local>ized C<$_> by default
(as does the native C<foreach> loop).  See L<"SYNTAX"> for details.

The interface and behavior of the Shell versions has been retained
where deemed desirable,
and sensibly modified along Perlish lines elsewhere.
Accordingly, the (primary) default LIST is B<@ARGV> (paralleling the Shell's B<"$@">),
menu prompts can be customized by having the script import and set B<$Prompt>
(paralleling the Shell's B<$PS3>),
and the user's response to the prompt appears in the 
variable B<$Reply> (paralleling the Shell's B<$REPLY>),
C<local>ized to the loop.

A deficiency of the shell implementation is the
inability of the user to provide a I<heading> for each C<select> menu. 
Sure, the
shell programmer can B<echo> a heading before the loop is entered and the
menu is displayed, but that approach doesn't help when an I<Outer loop> is
reentered on departure from an I<Inner loop>,
because the B<echo> preceding the I<Outer loop> won't be re-executed. 

A similar deficiency surrounds the handling of a custom prompt string, and
the need to automatically display it on moving from an inner loop 
to an outer one.

To address these deficiencies, this implementation provides the option of having a heading and prompt bound
to each C<select> loop.  See L<"IMPORTS AND OPTIONS"> for details.

Headings and prompts are displayed in reverse video on the terminal,
if possible, to make them more visually distinct.

Some shell versions simply ignore bad input,
such as the entry of a number outside the menu's valid range,
or alphabetic input.  I can't imagine any argument
in favor of this behavior being desirable when input is coming from a terminal,
so this implementation gives clear warning messages for such cases by default
(see L<"Warnings"> for details).

After a menu's initial prompt is issued, some shell versions don't
show it again unless the user enters an empty line. 
This is desirable in cases where the menu is sufficiently large as to 
cause preceding output to scroll off the screen, and undesirable otherwise.
Accordingly, an option is provided to enable or disable automatic prompting
(see L<"Prompts">).

This implementation always issues a fresh prompt 
when a terminal user submits EOF as input to a nested C<select> loop.
In such cases, experience shows it's critical to reissue the
menu of the outer loop before accepting any more input.

=begin comment

The response additionally appears in B<$ENV{REPLY}>, which warrants some discussion.
In the Shells, the automatic exporting of that variable is adjustable via
the B<set -a> or B<set -o allexport> option settings,
but given that Perl has no such mechanism for automatically
placing variables into the environment,
a decision was made to have the module do this for the user.
(This could become a configurable option
in subsequent versions, if anybody cares).

=end comment

=head1 SCOPING ISSUES

If the loop variable is named and provided with a I<declarator> (C<my>, C<our>, or C<local>),
the variable is scoped within the loop using that type of declaration.
But if the variable is named but lacks a declarator, 
no declaration is applied to the variable.

This allows, for example,
a variable declared as private I<above the loop> to be accessible
from within the loop, and beyond it,
and one declared as private I<for the loop> to be confined to it:

    select my $loopvar ( ) { }
    print "$loopvar DOES NOT RETAIN last value from loop here\n";
 -----------------------------------------------------------------------
    my $loopvar;
    select $loopvar ( ) { }
    print "$loopvar RETAINS last value from loop here\n";

With this design, 
C<select> behaves differently than the
native C<foreach> loop, which nowadays employs automatic
localization.

    foreach $othervar ( ) { } # variable localized automatically
    print "$othervar DOES NOT RETAIN last value from loop here\n";

    select $othervar ( ) { } # variable in scope, or global
    print "$othervar RETAINS last value from loop here\n";

This difference in the treatment of variables is intentional, and appropriate.
That's because the whole point of C<select>
is to let the user choose a value from a list, so it's often
critically important to be able to see, even outside the loop,
the value assigned to the loop variable.

In contrast, it's usually considered undesirable and unnecessary
for the value of the
C<foreach> loop's variable to be visible outside the loop, because
in most cases it will simply be that of the last element in the list.

Of course, in situations where the
C<foreach>-like behavior of implicit C<local>ization is desired,
the programmer has the option of declaring the C<select> loop's
variable as C<local>.

Another deficiency of the Shell versions is that it's difficult for the
programmer to differentiate between a
C<select> loop being exited via C<last>,
versus the loop detecting EOF on input.
To correct this situation,
the variable C<$Eof> can be imported and checked for a I<TRUE> value
upon exit from a C<select> loop (see L<"Eof Detection">).

=head1 IMPORTS AND OPTIONS

=head2 Syntax

 use Shell::POSIX::Select (
     '$Prompt',      # to customize per-menu prompt
     '$Heading',     # to customize per-menu heading
     '$Eof',         # T/F for Eof detection
 # Variables must come first, then key/value options
     prompt   => 'Enter number of choice:',  # or 'whatever:'
     style    => 'Bash',     # or 'Korn'
     warnings => 1,          # or 0
     debug    => 0,          # or 1-5
     logging  => 0,          # or 1
     testmode => <unset>,    # or 'make', or 'foreach'
 );

I<NOTE:> The values shown for options are the defaults, except for C<testmode>, which has none.

=head2 $Prompt

=head3 The prompt option

The C<prompt> option is intended for use in
programs that either contain a single C<select> loop, or are
content to use the same prompt for every loop.
It allows a custom interactive prompt to be set in the B<use> statement.

The prompt string should not end in a whitespace character, because
that doesn't look nice when the prompt is highlighted for display
(usually in I<reverse video>).
To offset the cursor from the prompt's end,
I<one space> is inserted automatically 
after display highlighting has been turned off. 

If the environment variable C<$ENV{Shell_POSIX_Select_prompt}>
is present,
its value overrides the one in the B<use> statement.

The default prompt is "Enter number of choice:".
To get the same prompt as provided by the Korn or Bash shell,
use C<< prompt =>> Korn >> or C<< prompt => Bash >>.

=head3 The $Prompt variable

The programmer may also modify the prompt during execution,
which may be desirable with nested loops that require different user instructions.
This is accomplished by
importing the $Prompt variable, and setting it to the desired prompt string
before entering the loop.  Note that imported variables have to be listed
as the initial arguments to the C<use> directive, and properly quoted.
See L<"order.plx"> for an example.

NOTE: If the program's input channel is not connected to a terminal,
prompting is automatically disabled
(since there's no point in soliciting input from a I<pipe>!).

=head2 $Heading

The programmer has the option of binding a heading to each loop's menu,
by importing C<$Heading> and setting it just before entering the associated loop.
See L<"order.plx"> for an example.

=head2 $Eof

A common concern with the Shell's C<select> loop is distinguishing between
cases where a loop ends due to EOF detection, versus the execution of C<break>
(like Perl's C<last>).
Although the Shell programmer can check the C<$REPLY> variable to make
this distinction, this implementation localizes its version of that variable 
(C<$Reply>) to the loop,
obviating that possibility.

Therefore, to make EOF detection as convenient and easy as possible,
the programmer may import C<$Eof> and check it for a 
I<TRUE> value after a C<select> loop.
See L<"lc_filename.plx"> for a programming example.

=head2 Styles

The C<style> options I<Korn> and I<Bash> can be used to request a more Kornish or Bashlike style of behavior.
Currently, the only difference is that the former disables, and the latter enables,
prompting for every input.  A value can be
provided for the C<style> option
using an argument of the form C<< style => 'Korn' >> to the C<use> directive.
The default setting is C<Bash>.
If the environment variable C<$ENV{Shell_POSIX_Select_style}> is
set to C<Korn> or C<Bash>,
its value overrides the one provided with the B<use> statement.

=head2 Warnings

The C<warnings> option,
whose values range from C<0> to C<1>, enables informational messages meant to help
the interactive user provide correct inputs.
The default setting is C<1>, which provides warnings about incorrect
responses to menu prompts 
(I<non-numeric>, I<out of range>, etc.).
Level C<0> turns these off. 

If the environment variable C<$ENV{Shell_POSIX_Select_warnings}> is
present, its value takes precedence.

=head2 Logging

The C<logging> option, whose value ranges from C<0> to C<1>,
causes informational messages and source code to be saved in temporary files
(primarily for debugging purposes).

The default setting is C<0>, which disables logging.

If the environment variable C<$ENV{Shell_POSIX_Select_logging}> is
present, its value takes precedence.

=head2 Debug

The C<debug> option,
whose values range from C<0> to C<9>, enables informational messages
to aid in identifying bugs.
If the environment variable C<$ENV{Shell_POSIX_Select_debug}> is
present, and set to one of the acceptable values, it takes precedence.

This option is primarly intended for the author's use, but
users who find bugs may want to enable it and email the output to
L<"AUTHOR">.  But before concluding that the problem is truly a bug
in this module, please confirm that the program runs correctly with the option 
C<< testmode => foreach >> enabled (see L<"Testmode">).

=head2 Testmode

The C<testmode> option, whose values are 'make' and 'foreach',
changes the way the program is executed.  The 'make' option is used
during the module's installation, and causes the program to dump
the modified source code and screen display to files,
and then stop (rather than interacting with the user). 

If the environment variable C<$ENV{Shell_POSIX_Select_testmode}> is
present, and set to one of the acceptable values, it takes precedence.

With the C<foreach> option enabled, the program simply translates occurrences
of C<select> into C<foreach>, which provides a useful method for 
checking that the program is syntactically correct before any serious
filtering has been applied (which can introduce syntax errors).
This works because the two loops, in their I<full forms>, have identical syntax.

Note that before you use the C<foreach> option, you I<must> fill in any
missing parts that are required by C<foreach>.

For instance,

C<select () {}> 

I<	must be rewritten as>

C<foreach (@ARGV) { print; }>

=head1 ADDITIONAL EXAMPLES

NOTE: All non-trivial programming examples shown in this document are
distributed with this module, in the B<Scripts> directory.
See L<"ELEMENTARY EXAMPLES">
for simpler uses of C<select>.

=head2 SMALL PROGRAMS

=head3 pick_file.plx

This program lets the user choose filenames to be sent to the output.
It's sort of like an
interactive Perl C<grep> function, with a live user providing the 
filtering service.
As illustrated below,
it could be used with Shell command substitution to provide selected arguments to a command.

    use Shell::POSIX::Select  (
      prompt => 'Pick File(s):' ,
      style => 'Korn'  # for automatic prompting
    );
    select ( <*> ) { }

I<Screen>

    lp `pick_file`>   # Using UNIX-like OS

    1) memo1.txt   2) memo2.txt   3) memo3.txt
    4) junk1.txt   5) junk2.txt   6) junk3.txt

    Pick File(s): 4
    Pick File(s): 2
    Pick File(s): ^D

    request id is yumpy@guru+587

=begin comment

h=ead3 long_listem.plx

This program gives the user a menu of filenames, and displays
a long-listing of each chosen one.

 use Shell::POSIX::Select ;

 select my $var (@ARGV) { system "ls -ldi '$var'" } # Maximal typing

 # OR, through use of defaults, the following is equivalent:

 select ( ) { system "ls -ldi '$_'" } # Using default var & LIST
 -----------------------------------------------------------------

I<Screen>

 long_listem.plx  *.txt

 1) memo1.txt   2) memo2.txt   3) memo3.txt
 4) junk1.txt   5) junk2.txt   6) junk3.txt

 Enter number of choice: 4

 -rw-r--r--    1 yumpy   gurus   18929 Jan  1 16:41 junk1.txt

h=ead3 browse_jpeg.plx

Here's a simple yet highly useful script.   It displays a menu of all
the JPEG files in the current directory, and then displays the chosen
ones on-screen using a backgrounded image viewer.

    use Shell::POSIX::Select ;

    $viewer='/usr/X11R6/bin/xv';   # Popular Linux viewer
    select ( <*.jpg> ) {
        system "$viewer $_ &" ;
    }

=end comment

=head3 browse_images.plx

Here's a simple yet highly useful script.   It displays a menu of all
the image files in the current directory, and then displays the chosen
ones on-screen using a backgrounded image viewer.

It uses Perl's C<grep> to filter-out filenames that don't
end in the desired extensions.

    use Shell::POSIX::Select ;

    $viewer='xv';  # Popular image viewer

    select ( grep /\.(jpg|gif|tif|png)$/i, <*> ) {
        system "$viewer $_ &" ;     # run viewer in background
    }

=begin comment

h=ead3 send_spam.plx

In the next example, the user selects an email address from a numbered menu of choices,
and then mail is sent to that address.
(Note that I'm not I<condoning> the behavior illustrated in the example;
on the contrary, I'm promoting an interactive approach in order to I<slow them down>!)

 use Shell::POSIX::Select ( prompt=>'Enter number of spamee:' ) ;

 select $spamee ( Get_all_Email_Addresses_in_Universe() ) {
         send_spam ( $spamee, '*! Make Money Fast !*' ) ;
 }

=end comment

=head3 perl_man.plx

Back in the olden days, we only had one Perl man-page. It was
voluminous, but at least you knew what argument to give the B<man>
command to get the documentaton.

Now we have over a hundred Perl man pages, with unpredictable names
that are difficult to remember.  Here's the program I use that 
allows me to select the man-page of interest from a menu.

 use Shell::POSIX::Select ;

 # Extract man-page names from the TOC portion of the output of "perldoc perl"
 select $manpage ( sort ( `perldoc perl` =~ /^\s+(perl\w+)\s/mg) ) {
     system "perldoc '$manpage'" ;
 }

I<Screen>

  1) perl5004delta     2) perl5005delta     3) perl561delta    
  4) perl56delta       5) perl570delta      6) perl571delta    
 . . .

I<This large menu spans multiple screens, but all parts can be accessed
 using your normal terminal scrolling facility.>

 Enter number of choice: 6

 
 PERL571DELTA(1)       Perl Programmers Reference Guide 

 NAME
        perl571delta - what's new for perl v5.7.1

 DESCRIPTION
        This document describes differences between the 5.7.0
        release and the 5.7.1 release.
 . . .

=head1 MEDIUM PROGRAMS

=head3 pick.plx

This more general C<pick>-ing program lets the user make selections
from arguments, if they're present, or else input, in the spirit of Perl's
C<-n> invocation option and C<< <> >> input operator.

 use Shell::POSIX::Select ;

 BEGIN {
     if (@ARGV) {
         @choices=@ARGV ;
     }
     else { # if no args, get choices from input
         @choices=<STDIN>  or  die "$0: No data\n";
         chomp @choices ;
         # STDIN already returned EOF, so must reopen
         # for terminal before menu interaction
         open STDIN, "/dev/tty"  or  die ;  # UNIX example
     }
 }
 select ( @choices ) { }   # prints selections to output

I<Sample invocations (UNIX-like system)>

    lp `pick *.txt`    # same output as shown for "pick_file"

    find . -name '*.plx' -print | pick | lp

    who |
        awk '{ print $1 }' |        # isolate user names
            pick |                  # select user names
                Mail -s 'Promote these people!'  boss


=head3 delete_file.plx

In this program, the user selects a filename 
to be deleted.  The outer loop is used to refresh the list,
so the file deleted on the previous iteration gets removed from the next menu.
The outer loop is I<labeled> (as C<OUTER>), so that the inner loop can refer to it when
necessary.

    use Shell::POSIX::Select (
        '$Eof',   # for ^D detection
        prompt=>'Choose file for deletion:'
    ) ;

  OUTER:
    while ( @files=<*.py> ) {  # loop exited from within
        select ( @files ) { 
           print STDERR  "Really delete $_? [y/n]: " ;
           my $answer = <STDIN> ;     # ^D sets $Eof below
           defined $answer  or  last OUTER ;  # exit on ^D
           $answer eq "y\n"  and  unlink  and  last ;
        }
        $Eof and last;
    }

=head3 lc_filename.plx

This example shows the benefit of importing C<$Eof>, 
so the outer loop can be exited when the user supplies
C<^D> to the inner one.

Here's how it works.
If the rename succeeds in the inner loop, execution
of C<last> breaks out of the C<select> loop;
$Eof will then be evaluated as I<FALSE>, and 
the C<while> loop will start a new C<select> loop,
with a (depleted) filename menu.  But if the user
presses C<^D> to the menu prompt, C<$Eof> will test
as I<TRUE>, triggering the exit from the C<while> loop.

    use Shell::POSIX::Select (
        '$Eof' ,
        prompt => 'Enter number (^D to exit):'
    );

    # Rename selected files from current dir to lowercase
    while (1) {    # restarts select to get updated menu
        select ( <*[A-Z]*> ) { # skip fully lower-case names
            if (rename $_, "\L$_") {
                last ;
            }
            else {
               warn "$0: rename failed for $_: $!\n";
           }
        }
        $Eof  and  last ;   # Handle <^D> to menu prompt
    }

I<Screen>

 lc_filename.plx

 1) Abe.memo   2) Zeke.memo
 Enter number (^D to exit): 1

 1) Zeke.memo
 Enter number (^D to exit): ^D

=head3 order.plx

This program sets a custom prompt and heading for each of
its two loops, and shows the use of a label on the outer loop.

 use Shell::POSIX::Select qw($Prompt $Heading);
 
 $Heading="\n\nQuantity Menu:";
 $Prompt="Choose Quantity:";
 
 OUTER:
 select my $quantity (1..4) {
    $Heading="\nSize Menu:" ;
    $Prompt='Choose Size:' ;

    select my $size ( qw (L XL) ) {
        print "You chose $quantity units of size $size\n" ;
        last OUTER ;    # Order is complete
    }
 }

I<Screen>

 order.plx

 Quantity Menu:
 1)  1    2)  2    3)  3    4)  4
 Choose Quantity: 4

 Size Menu:
 1) L   2) XL
 Choose Size: <^D>       (changed my mind about the quantity)

 Quantity Menu:
 1)  1    2)  2    3)  3    4)  4
 Choose Quantity: 2

 Size Menu:
 1)  L    2)  XL
 Choose Size: 2
 You chose 2 units of size XL

=head1 LARGE PROGRAMS

=head3 browse_records.plx

This program shows how you can implement a "record browser",
that builds a menu from the designated field of each record, and then
shows the record associated with the selected field. 

To use a familiar
example, we'll browse the UNIX password file by user-name.

 use Shell::POSIX::Select ( style => 'Korn' );
 
 if (@ARGV != 2  and  @ARGV != 3) {
     die "Usage: $0 fieldnum filename [delimiter]" ;
 }
 
 # Could also use Getopt:* module for option parsing
 ( $field, $file, $delim) = @ARGV ;
 if ( ! defined $delim ) {
     $delim='[\040\t]+' # SP/TAB sequences
 }
 
 $field-- ;  # 2->1, 1->0, etc., for 0-based indexing
 
 foreach ( `cat "$file"` ) {
     # field is the key in the hash, value is entire record
     $f2r{ (split /$delim/, $_)[ $field ] } = $_ ;
 }
 
 # Show specified fields in menu, and display associated records
 select $record ( sort keys %f2r ) {
     print "$f2r{$record}\n" ;
 }

I<Screen>

 browsrec.plx  '1'  /etc/passwd  ':'

  1) at     2) bin       3) contix   4) daemon  5) ftp     6) games
  7) lp     8) mail      9) man     10) named  11) news   12) nobody
 13) pop   14) postfix  15) root    16) spug   17) sshd   18) tim

 Enter number of choice: 18

 tim:x:213:100:Tim Maher:/home/tim:/bin/bash

 Enter number of choice: ^D

=head3 menu_ls.plx

This program shows a prototype for a menu-oriented front end
to a UNIX command, that prompts the user for command-option choices,
assembles the requested command, and then runs it.

It employs the user's numeric choice,
stored in the C<$Reply> variable, to extract from an array the command
option associated with each option description.

 use Shell::POSIX::Select qw($Heading $Prompt $Eof) ;

 # following avoids used-only once warning
 my ($type, $format) ;
 
 # Would be more Perlish to associate choices with options
 # via a Hash, but this approach demonstrates $Reply variable
 
 @formats = ( 'regular', 'long' ) ;
 @fmt_opt = ( '',        '-l'   ) ;
 
 @types   = ( 'only non-hidden', 'all files' ) ;
 @typ_opt = ( '',                '-a' ,      ) ;
 
 print "** LS-Command Composer **\n\n" ;
 
 $Heading="\n**** Style Menu ****" ;
 $Prompt= "Choose listing style:" ;
 OUTER:
 select $format ( @formats ) {
     $user_format=$fmt_opt[ $Reply - 1 ] ;
 
     $Heading="\n**** File Menu ****" ;
     $Prompt="Choose files to list:" ;
     select $type ( @types ) {   # ^D restarts OUTER
         $user_type=$typ_opt[ $Reply - 1 ] ;
         last OUTER ;    # leave loops once final choice obtained
     }
 }
 $Eof  and  exit ;   # handle ^D to OUTER
 
 # Now construct user's command
 $command="ls  $user_format  $user_type" ;
 
 # Show command, for educational value
 warn "\nPress <ENTER> to execute \"$command\"\n" ;

 # Now wait for input, then run command
 defined <>  or  print "\n"  and  exit ;    
 
 system $command ;    # finally, run the command
 
I<Screen>

 menu_ls
 
 ** LS-Command Composer **
 
 1) regular    2) long
 Choose listing format: 2
 
 1) only non-hidden   2) all files
 Choose files to list:  2 
 
 Press <ENTER> to execute "ls -l -a" <ENTER>

 total 13439
 -rw-r--r--    1 yumpy   gurus    1083 Feb  4 15:41 README
 -rw-rw-r--    6 yumpy   gurus     277 Dec 17 14:36 .exrc.mmkeys
 -rw-rw-r--    7 yumpy   gurus     285 Jan 16 18:45 .exrc.podkeys
 $

=head1 BUGS

=head2 UNIX Orientation

I've been a UNIX programmer since 1976, and a Linux proponent since
1992, so it's most natural for me to program for those platforms.
Accordingly, this early release has some minor features that are only
allowed, or perhaps only entirely functional, on UNIX-like systems.
I'm open to suggestions on how to implement some of these features in
a more portable manner.

Some of the programming examples are also 
UNIX oriented, but it should be easy enough for those specializing on
other platforms to make the necessary adapations. 8-}

=head2 Terminal Display Modes

These have been tested under UNIX/Linux, and work as expected,
using B<tput>.  When time permits, I'll convert to a portable
implementation that will support other OSs.

=head2 Incorrect Line Numbers in Warnings

Because this module inserts new source code into your program,
Perl messages that reference line numbers will refer to a
different source file than you wrote.  For this reason,
only messages referring to lines before the first C<select>
loop in your program will be correct.

If you're on a UNIX-like system, by enabling the C<debugging>
and C<logging> options (see L<"Debug"> and L<"Logging">), you can
get an on-screen report of the proper offset to apply to interpret
the line numbers of the source code that gets dumped to the
F</tmp/SELECT_source> file.  Of course, if everything works correctly,
you'll have little reason to look at the source. 8-}

=head2 Comments can Interfere with Filtering

Because of the way Filter::Simple works,
ostensibly "commented-out" C<select> loops like the following
can actually break your program:

 # select (@ARGV)
 # { ; }
 select (@ARGV) { ; }

=for comment
That's because current versions of Filter::Simple
perform substitutions for "select (...) {...}" even
in the I<commented-out lines> of your program, which leads this module to
introduce syntax errors into your program.

A future version of Filter::Simple
(or more precisely Text::Balanced, on which on which it depends)
may correct this problem.

In any case, there's an easy workaround for the commented-out select
loop problem; just
change I<se>lect into I<es>lect when you comment it out, and there'll
be no problem.

For other problems involving troublesome text within comments, see 
L<"Failure to Identify select Loops">.

=head2 Occasional Failure to Identify C<select> Loops

When a properly formed C<select> loop appears in certain contexts,
such as before a line containing certain patterns of dollar signs,
it will not be properly identified and translated into standard Perl.
The following is such an example:

    use Shell::POSIX::Select;
    select (@names) { print ; }
    # $X$

The failure of the filtering routine to rewrite the loop causes the
compiler to throw a fatal error, which prevents the program from running.
This is either due to a bug in Filter::Simple, or one of the modules on
which it depends.
Until this is resolved, you can
handle such cases by explicitly turning filtering off before the offending
code is encountered, using the B<no> directive:

    use Shell::POSIX::Select;     # filtering ON
    select (@names) { print ; }

    no Shell::POSIX::Select;      # filtering OFF
    # $X$

=head2 Restrictions on Loop-variable Names

Due to a bug in most versions of Text::Balanced,
loop-variable names that look like Perl operators,
including C<$m>, C<$a>, C<$s>, C<$y>, C<$tr>,
C<$qq>, C<$qw>, C<$qr>, and C<$qx>, and possibly others,
cause syntax errors.
Newer
versions of that module
(unreleased at the time of this writing)
have corrected this problem, 
so download the latest version if you must use such names.

=begin comment

h=ead2 Solaris "Killed" Bug

The module works properly under B<Solaris 9> (B<SunOS 5.9>),
except for some reason it always prints C<Killed> before printing the
expected output.  Anybody have a clue about this?

(All the development occurred under Linux, where this symptom
doesn't occur.)

=end comment

=head2 Please Report Bugs!

This is a non-trivial program, that does some fairly complex parsing
and data munging,
so I'm sure there are some latent bugs awaiting your discovery.
Please share them with me, by emailing the offending code,
and/or the diagnostic messages enabled by the I<debug>
option setting (see L<"IMPORTS AND OPTIONS">).

=head1 TODO-LIST

=head2 More Shell-like Menus

In a future release, there could be options for
more accurately emulating Bash and Korn-style behavior,
if anybody cares (the main difference is in how the
items are ordered in the menus).

=head2 More Extensive Test Suite

More tests are needed, especially for the complex and tricky cases.

=head1 MODULE DEPENDENCIES

 File::Spec::Functions
 Text::Balanced
 Filter::Simple

=head1 EXPORTS: Default

 $Reply

This variable is C<local>ized to each C<select> loop,
and provides the menu-number of the most recent valid selection.
For an example of its use, see L<"menu_ls.plx">.

=head1 EXPORTS: Optional

 $Heading
 $Prompt
 $Eof

See L<"IMPORTS AND OPTIONS"> for details.

=head1 SCRIPTS

 browse_images
 browse_jpeg
 browse_records
 delete_file
 lc_filename
 long_listem
 menu_ls
 order
 perl_man
 pick
 pick_file

=head1 AUTHOR

 Tim Maher
 Consultix
 yumpy@cpan.org
 http://www.teachmeperl.com

=head1 ACKNOWLEDGEMENTS

I probably never would have even attempted to write this module
if it weren't for the provision of Filter::Simple by Damian Conway, 
which I ruthlessly exploited to make a hard job easy. 

I<The Damian> also gave useful tips
during the module's development, for which I'm grateful.

I I<definitely> wouldn't have ever written this module, if I hadn't
found myself writing a chapter on I<Looping> for my upcoming 
B<Manning Publications> book,
and once again lamenting the fact that the most friendly Shell loop
was still missing from Perl. 
So in a fit of zeal, I vowed to rectify that oversight!

I hope you find this module as useful as I do! 8-}

For more examples of how this loop can be used in Perl programs,
watch for my upcoming book, I<Minimal Perl: for Shell Users and Programmers>
(see
L<http://teachmeperl.com/mp4sh.html>) in early fall, 2003.

=head1 SEE ALSO

 man ksh    # on UNIX or UNIX-like systems

 man bash    # on UNIX or UNIX-like systems

=head1 DON'T SEE ALSO

B<perldoc -f select>, which has nothing to do with this module
(the names just happen to match up).

=head1 LICENSE

Copyright (C) 2002-2003, Timothy F. Maher.  All rights reserved. 

This module is free software;
you can redistribute it and/or modify it under the same terms as Perl itself.

=cut

# vi:ts=2 sw=2:

1;
