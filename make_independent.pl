#!/usr/bin/perl
use strict;
use warnings;
use Mac::PropertyList qw(parse_plist_file);
use File::Copy;
use File::Basename;

#Copyright (c) Sjors Gielen, 2013
#All rights reserved.
#
#Redistribution and use in source and binary forms, with or without
#modification, are permitted provided that the following conditions are met:
#    * Redistributions of source code must retain the above copyright
#      notice, this list of conditions and the following disclaimer.
#    * Redistributions in binary form must reproduce the above copyright
#      notice, this list of conditions and the following disclaimer in the
#      documentation and/or other materials provided with the distribution.
#    * Neither the name of the authors of this application nor the
#      names of its contributors may be used to endorse or promote products
#      derived from this software without specific prior written permission.
#
#THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
#ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
#WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
#DISCLAIMED. IN NO EVENT SHALL SJORS GIELEN OR CONTRIBUTORS BE LIABLE FOR ANY
#DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
#(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
#LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
#ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
#SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

my $VERSION = "1.0";

my $DRYRUN = 0;
if(@ARGV > 1 && $ARGV[0] eq "-n") {
	$DRYRUN = 1;
	shift @ARGV;
}

my ($app, $file) = @ARGV;
if(!$app || $app eq "--help" || $app eq "-h") {
	usage();
	exit(1);
}

# Sanity checks on $app

if(!-d $app) {
	warn "Not a directory: $app\n";
	usage();
	exit(1);
}

if(!-f "$app/Contents/Info.plist") {
	warn "Not a valid .app (Info.plist is missing): $app\n";
	usage();
	exit(1);
}

if(!$file) {
	my $info = parse_plist_file("$app/Contents/Info.plist");
	if(!$info) {
		warn "Not a valid .app: failed to read Info.plist\n";
		usage();
		exit(1);
	}
	$file = "Contents/MacOS/" . $info->{"CFBundleExecutable"}->as_perl;
	if(!$file) {
		warn "Not a valid .app (CFBundleExecutable key is missing): $app\n";
		usage();
		exit(1);
	}
}

# Sanity checks on $file
if(!-f "$app/$file") {
	warn "Parameter does not exist: $app/$file\n";
	usage();
	exit(1);
}

my $libdir = "$app/Contents/Libraries";
my $has_libdir = -d $libdir;
fix($app, $file, "$app/$file", 0);

sub fix {
	my ($app, $real_file, $dryrun_file, $level) = @_;
	my $filepath = $DRYRUN ? $dryrun_file : "$app/$real_file";
	my @otool_output = split /\n/, `otool -X -L "$filepath"`;
	my $own_name     = `otool -X -D "$filepath"`;
	1 while chomp $own_name;

	my $spaces = "  " x $level;
	print "${spaces}$filepath\n";
	$spaces .= "  ";

	foreach my $otool_line (@otool_output) {
		my ($dylib) = $otool_line =~ /(\S.+) \(compatibility version/;
		if(!$dylib) {
			warn "${spaces}Did not understand output of otool for file $filepath:\n";
			warn "${spaces}$otool_line\n";
			next;
		}
		if($own_name && $dylib eq $own_name) {
			# The first entry in otool -L output for a library is
			# always the library itself, skip that line, it has
			# already been fixed if copied by us
			next;
		}
		if(is_system_lib($dylib)) {
			# skip system lib
			next;
		} elsif(is_app_lib($dylib)) {
			# skip lib already in app
			next;
		} elsif(is_relative_path($dylib)) {
			warn "${spaces}Invalid dynamic linker line in file: $filepath\n";
			warn "${spaces}$otool_line\n";
			next;
		}

		make_lib_dir($app, $spaces);
		my ($newpath, $newpath_relative) = copy_lib($dylib, $app, $spaces);
		fix_install_name($filepath, $dylib, $newpath, $spaces);
		fix_own_install_name("$app/$newpath_relative", $newpath, $spaces);

		# Now that this lib is imported, recursively run ourselves on
		# it
		fix($app, $newpath_relative, $dylib, $level + 1);
	}
}

sub is_system_lib {
	my ($lib) = @_;

	foreach(qw(/usr/lib /lib /System)) {
		if($lib =~ /^\Q$_\E/) {
			return 1;
		}
	}

	return 0;
}

sub is_app_lib {
	my ($lib) = @_;
	return $lib =~ /^\@(?:executable|loader)_path/;
}

sub is_relative_path {
	my ($lib) = @_;
	return substr($lib, 0, 1) ne '/';
}

sub make_lib_dir {
	my ($app, $s) = @_;
	if(!$has_libdir) {
		$has_libdir = 1;
		print "${s}Create directory: $libdir\n";
		return if $DRYRUN;
		mkdir $libdir or die "${s}Could not make library directory $libdir: $!\n";
	}
}

sub copy_lib {
	my ($lib, $app, $s) = @_;
	my $basename = basename($lib);
	my $newpath = "$libdir/$basename";
	my $int_path = "\@loader_path/../Libraries/$basename";
	my $relative_path = "Contents/Libraries/$basename";
	if(!-f $newpath) {
		#print "${s}Copy $lib into app\n";
		unless($DRYRUN) {
			copy($lib, $newpath) or die "${s}Failed to copy: $!\n";
		}
	}

	return ($int_path, $relative_path);
}

sub fix_install_name {
	my ($file, $old, $new, $s) = @_;
	my @cmd = ("install_name_tool", "-change", $old, $new, $file);
	#print "${s}Adapt location of lib '$old' in $file\n";
	return if $DRYRUN;
	system(@cmd) == 0 or die "${s}Failed to install_name_tool1: $?\n";
}

sub fix_own_install_name {
	my ($file, $new, $s) = @_;
	my @cmd = ("install_name_tool", "-id", $new, $file);
	#print "${s}Adapt own location in $file\n";
	return if $DRYRUN;
	system(@cmd) == 0 or die "${s}Failed to install_name_tool2: $?\n";
}

sub usage {
	warn "Usage: $0 [-n] <path to .app> [relative path to file]\n";
	warn <<USAGE;

Finds all .dylibs used by the given file (or, if not given, the executable of
the .app), and copies them into the .app, updating any internal links. Works
recursively on all copied .dylibs too. If the -n option is given, only outputs
what it should have done, but does not actually change anything.
USAGE
	warn "Version $VERSION, written by Sjors Gielen.\n";
}
