#!perl -w
#
# $Id: exe_wrap.pl,v 1.8 2002/12/17 12:41:43 epaepa Exp $
# This is a quick XMLTV shell routing to use with the windows exe
#
# A single EXE is needed to allow sharing of modules and dlls of all the
# programs.  If PerlAPP was run on each one, the total size would be more than
# 12MB, even leaving out PERL56.DLL!
#
# Perlapp allows you to attach pathed files, but you need the same path
# to access them.  The Makefile creates a text file of these files which is
# used to build a translation table, allowing users to just type the app name
# and not the development path.
#
# Robert Eden rmeden@yahoo.com
#

#
# check time zone
#
unless (exists $ENV{TZ})
{
    my $now    =  time();
    my $lhour  = 20; #(localtime($now))[2];
    my $ghour  = 02; # (   gmtime($now))[2];
    my $tz     = ($lhour - $ghour);
       $tz    -= 24 if $tz >  12;
       $tz    += 24 if $tz < -12;
       $tz     = sprintf("%+03d00",$tz);
       $ENV{TZ}= $tz;
} #timezone
print STDERR "Timezone is $ENV{TZ}\n";

#
# This hash maps a command name to a subroutine to run.  Most of the
# subroutines will end up being 'do "whatever"' to call another Perl
# program, but some of them could be other things for components that
# aren't written in Perl.
#
my %cmds;

#
# build file list - for Perl scripts to 'do'
#
$files=PerlApp::get_bound_file("exe_files.txt");
foreach my $exe (split(/ /,$files))
{
    next unless length($exe)>3; #ignore trash
    $_=$exe;
    s!^.+/!!g;

    my $sub;
    if ($exe eq 'tv_grab_uk' or $exe eq 'tv_grab_uk_rt') {
	# These require a share/ directory.  It's included in the
	# distribution.
	#
	my $dir = "share/xmltv/$exe";
	if (not -d 'share') {
	    die "directory $dir not found, please run me from the directory where you unpacked\n";
	}
	$sub=sub {
	    push @ARGV, '--share', $dir;
	    do $exe;
	};
    }
    else {
	$sub=sub { do $exe };
    }

    $cmds{$_}=$sub;
}

#
# and add tv_grab_nz which is a Python program
#
$cmds{tv_grab_nz}=sub {
    die <<END
Sorry, tv_grab_nz is not available in this Windows binary release,
although if you have Python installed you will be able to get it from
the xmltv source distribution.

It is hoped that future Windows binaries for xmltv will include a way
to run tv_grab_nz.
END
  ;
};

#
# validate command 
#
$cmd=shift || "blank";
if (! exists $cmds{$cmd} )
{
    die "$cmd is not a valid command. Valid commands are:\n".join(" ",keys(%cmds))."\n";
}


#
# call the appropriate routine (note, ARGV was shifted above)
#
$return=$cmds{$cmd}->();

die "$cmd:$! $@" unless (defined $return);

exit $return;
