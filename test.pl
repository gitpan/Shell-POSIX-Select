#! /usr/bin/perl

# Tim Maher, tim@teachmeperl.com
# Sun May  4 00:30:52 PDT 2003

use File::Spec::Functions;
use Test::More ;

# two extra for the use/require_ok() tests
plan tests => $num_tests * 2  + 2;

# NOTE: Reference-data generation is triggered through an ENV var

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'


BEGIN {

	# must tell it where to find module, before it's installed
	$ENV{PERL5LIB}.='blib/lib:blib/arch';	# needed for test programs
	unshift @INC, 'blib/lib', 'blib/arch' ;	# My solaris 9 box needs this too!

	$DEBUG = 1; 	# Should only be set >2 on UNIX-like OS
	$DEBUG = 4; 	# Should only be set >2 on UNIX-like OS
	$DEBUG = 0; 
	$test_compile = 1;	# fails due to control-char "placeholders" in source
	$test_compile = 0;

	$ref_dir='Ref_Data';
	$cbugs_dir='Compile_Bugs';
	$rbugs_dir='Run_Bugs';
	$test_dir='Test_Progs';

	# @Testdirs=( $test_dir, $ref_dir, $cbugs_dir, $rbugs_dir );

	chdir 'Test_Progs' or die "$!";
	$DEBUG >2 and system "ls -l ";

	@testfiles= grep ! /^\.|\.bak$|dump$|_ref$|bogus$/, <*>;

	# restrict to one file, if testing
	$DEBUG > 2 and @testfiles = $testfiles[0];
	# @testfiles = 'arrayvar';

	chdir( updir() ) or die "$!";

	chomp @testfiles;
	$num_tests = scalar @testfiles;
	$DEBUG and
		warn "There are $num_tests test scripts, and 2 tests on each\n";
	
	if (! -d $ref_dir or ! -r _ or ! -w _ or ! -x _ ) {
		mkdir $ref_dir or chmod 755, $ref_dir or
				die "$0: Failed to make $ref_dir\n";
	}
	else { $DEBUG >2 and system "ls -ld $ref_dir";  }
}	# end BEGIN

# MAKE THE REFERENCE FILES?

if (
		# 1 or
		$ENV{Shell_POSIX_Select_reference}
	) {
	
	# create source-code and screen-dump reference databases
	# If module generates same data on user's platform, test passes

	print "\nMAKING REFERENCE DATA\n";
	`uname -n` eq "guru\n"  or
	die "Hey! The generation of reference data is only for the author to do\n";

	$counter=0;
	foreach (@testfiles) {
		++$counter;
		print STDERR "$counter $_\n";
		$screen="$_.sdump" ;
		$screenR=catfile ($ref_dir, "${screen}_ref");
		$code="$_.cdump" ;
		$codeR=catfile ($ref_dir, "${code}_ref");
#		print "Code is $codeR\n";
#		print "Screen is $screenR\n";
		unlink $codeR, $screenR;	# discard old copies
		# system "ls -l $codeR $screenR";

		$ENV{Shell_POSIX_Select_testmode}='make' ;
		$ENV{Shell_POSIX_Select_reference}=1 ;
		# Or maybe just eval the code?
		$script = catfile( 'Test_Progs', $_ );
		system "perl '$script'" ;
		if ($?) {
			warn "$0: Reference code-dump of $_ failed with code $?\n";
			# $DEBUG >2 and system "ls -ld $_ $codeR $screenR";
			die;
		}
		else {
			$error=`egrep 'syntax | aborted' $screenR 2>/dev/null`;
			$? or
				die "Compilation failed for '$screenR'\n\n$error\n";
		}
		# Screen file can be empty, so just check existence and perms
		check_file ($screenR) or die "$screenR is bad\n";
		check_file ($codeR) and -s $codeR or die "$codeR is bad\n" ;
		if ( $test_compile ) {
			system "perl -wc '$codeR' 2>/tmp/$_.diag" ;
			if ($?) {
				print STDERR "$0: Reference code-dump of $_ ",
				print STDERR "failed to compile, code $?\n";
				$DEBUG >2 and system "ls -ld $_ $codeR $screenR";
				die "$0: Compilation test for $codeR failed\n";
			}
		}
		$DEBUG >2 and system "ls -l $codeR $screenR";
	}
	$ENV{Shell_POSIX_Select_reference} = undef;
	print "\n\n";
}

# On *every* run, compare the reference data to newly dumped output

print "TESTING MODULE AGAINST REFERENCE DATA\n\n";

# warn "\@INC is now @INC\n";
use_ok('Shell::POSIX::Select') or die;
require_ok('Shell::POSIX::Select');

# Configure ENV vars so module dumps the requried data
$ENV{Shell_POSIX_Select_reference}="";
$ENV{Shell_POSIX_Select_testmode}='make' ;

foreach (@testfiles) {
	$DEBUG and warn "\nDumping data for $_\n";
	$screen="$_.sdump" ;
	$screenR=catfile ($ref_dir, "${screen}_ref");
	$code="$_.cdump" ;
	$codeR=catfile ($ref_dir, "${code}_ref");

	$script = catfile( 'Test_Progs', $_ );
	# Later on, insert check for "*bogus" scripts to return error
	system "perl '$script'" ;
	$err=$?;

	$DEBUG >2 and system "echo; ls -rlt . | tail -4 ";
	if ( $err ) { $DEBUG and warn "Module returned $? for $_, $!"; }
	if ( ! -e $code  or  ! -f _  or  ! -r _  or  ! -s _ ) {
		warn "$code is bad\n";
		# system "ls -ld '$code'";
		next;
	}
	elsif (! -e $screen or ! -f _ or ! -r _ ) {	# empty could be legit
		warn "Screen dump for $_ failed: $!\n";
		# Keep the evidence for investigation
		next;
	}
	# Do cheap file-size comp first; string comparison later if needed
	if (-s $code != -s $codeR) {
		warn "Code dumps unequally sized for $_: ",
			-s $code,  " vs. ", -s $codeR, "\n";
		$DEBUG >2 and system "ls -li $code $codeR";
		fail ($code);	# force test to report failure
	}
	if (-s $screen != -s $screenR) {
		warn "Screen dumps unequally sized for $_: ",
			-s $screen,  " vs. ", -s $screenR, "\n";
		$DEBUG >2 and system "ls -li $screen $screenR";
		fail ($screen);	# force tests to report failure
	}
	else {
		# Files don't obviously differ, so next step is to compare bytes
		open C,		"$code"    or die "$0: Failed to open ${code}, $!\n";
		open C_REF,	"$codeR"   or die "$0: Failed to open ${code}_ref, $!\n";
		open S,		"$screen"  or die "$0: Failed to open ${screen}, $!\n";

		open S_REF, "$screenR" or die "$0: Failed to open ${screen}_ref, $!\n";

		undef $/;	# file-slurping mode
		defined ($NEW=<C>) or die "$0: Failed to read $code, $!\n";
		defined ($REF=<C_REF>) or die "$0: Failed to read $codeR, $!\n";

		# if ($_ =~ /bug$/) { warn "BUG FILE: $_\n"; }

		$ret = ok ($NEW eq $REF, $code);  # logical and doesn't work!
		$DEBUG > 0 and system ( "ls -ld $code $codeR" ) ;
		$ret or warn "Check $code for clues\n";
		$ret and !$DEBUG and unlink $code;

		defined ($NEW=<S>) or die "$0: Failed to read $screen, $!\n";
		defined ($REF=<S_REF>) or die "$0: Failed to read $screenR, $!\n";

		$ret = ok ($NEW eq $REF, $screen);
		$DEBUG > 0 and system ( "ls -ld $screen $screenR" ) ;
		$ret or warn "Check $screen for clues\n" and exit;
		$ret and !$DEBUG and unlink $screen;
	}
}
exit 0;

sub check_file {
	my $file=shift || die "check_file: No argument supplied\n";

	unless (-e $file and -f _ and -r _ ) {
		warn "$0: Reference file $codeR is bad\n"; return 0;
	}
	else { return 1; }
}

# vi:sw=4 ts=4:
